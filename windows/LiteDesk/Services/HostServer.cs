using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using LiteDesk.Native;
using LiteDesk.Protocol;

namespace LiteDesk.Services;

// Host-mode WebSocket server. Port of the host-mode block of src/main.js:
// raw TcpListener (not HttpListener — see WebSocketHandshake.cs for why) +
// hand-rolled RFC6455 upgrade + WebSocket.CreateFromStream, single-viewer
// enforcement (extra connections get a "busy" close), password auth gate.
// Owns a ScreenCapture (started/stopped on ViewerConnected/Disconnected)
// whose frames are pushed to the viewer via SendFrameAsync, and a
// MouseInjector that incoming mouse-* messages are enqueued into.
public sealed class HostServer
{
    private readonly object _viewerLock = new();
    private readonly ScreenCapture _screenCapture = new();
    private readonly MouseInjector _mouseInjector = new();

    private TcpListener? _listener;
    private CancellationTokenSource? _cts;
    private WebSocket? _viewerSocket;
    private string _password = "";

    public event Action? ViewerConnected;
    public event Action? ViewerDisconnected;
    public event Action<string>? ServerError;
    public event Action<WireMessage>? MouseMessageReceived;

    public bool IsRunning => _listener is not null;

    public HostServer()
    {
        // Capture only runs while someone's actually watching — start/stop
        // it (and the mouse injector) off the same connected/disconnected
        // events the UI subscribes to, rather than for the whole lifetime
        // of "host mode is on".
        ViewerConnected += OnViewerConnectedStartCaptureAndInjection;
        ViewerDisconnected += OnViewerDisconnectedStopCaptureAndInjection;

        _screenCapture.FrameCaptured += frame => _ = SendFrameAsync(frame);
        _screenCapture.CaptureError += msg => ServerError?.Invoke(msg);
    }

    private void OnViewerConnectedStartCaptureAndInjection()
    {
        (int width, int height) = ScreenCapture.GetPrimaryMonitorSize();
        _mouseInjector.FrameWidth = width;
        _mouseInjector.FrameHeight = height;
        _mouseInjector.Start();
        _screenCapture.Start();
    }

    private void OnViewerDisconnectedStopCaptureAndInjection()
    {
        _screenCapture.Stop();
        _mouseInjector.Stop();
    }

    public (bool Success, string? Error) Start(int port, string password)
    {
        Stop();
        _password = password;

        try
        {
            _listener = new TcpListener(IPAddress.Any, port);
            _listener.Start();
        }
        catch (Exception ex)
        {
            _listener = null;
            return (false, ex.Message);
        }

        _cts = new CancellationTokenSource();
        _ = AcceptLoopAsync(_listener, _cts.Token);
        return (true, null);
    }

    public void Stop()
    {
        _cts?.Cancel();
        _cts = null;

        try { _listener?.Stop(); } catch { /* ignore */ }
        _listener = null;

        _screenCapture.Stop();
        _mouseInjector.Stop();

        lock (_viewerLock)
        {
            try { _viewerSocket?.Abort(); } catch { /* ignore */ }
            _viewerSocket = null;
        }
    }

    // Sends a raw JPEG byte buffer as one binary WebSocket message to the
    // single authenticated viewer, if any — matches the wire protocol's "no
    // envelope, frame boundary is the WS frame boundary" contract.
    public async Task SendFrameAsync(byte[] jpegBytes)
    {
        WebSocket? socket;
        lock (_viewerLock) { socket = _viewerSocket; }
        if (socket is null || socket.State != WebSocketState.Open) return;

        try
        {
            await socket.SendAsync(jpegBytes, WebSocketMessageType.Binary, true, CancellationToken.None)
                .ConfigureAwait(false);
        }
        catch
        {
            // Viewer likely disconnected; the connection's receive loop will
            // observe the close and raise ViewerDisconnected.
        }
    }

    private async Task AcceptLoopAsync(TcpListener listener, CancellationToken ct)
    {
        try
        {
            while (!ct.IsCancellationRequested)
            {
                TcpClient client = await listener.AcceptTcpClientAsync(ct).ConfigureAwait(false);
                _ = HandleClientAsync(client, ct);
            }
        }
        catch (Exception ex) when (ex is OperationCanceledException or ObjectDisposedException)
        {
            // Normal on Stop().
        }
        catch (Exception ex)
        {
            ServerError?.Invoke(ex.Message);
        }
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken ct)
    {
        using (client)
        {
            NetworkStream stream = client.GetStream();

            bool handshakeOk;
            try
            {
                handshakeOk = await WebSocketHandshake.PerformServerHandshakeAsync(stream, ct).ConfigureAwait(false);
            }
            catch
            {
                return;
            }
            if (!handshakeOk) return;

            WebSocket socket = WebSocket.CreateFromStream(
                stream, isServer: true, subProtocol: null, keepAliveInterval: TimeSpan.Zero);

            bool busy;
            lock (_viewerLock) { busy = _viewerSocket is not null; }

            if (busy)
            {
                // Matches src/main.js: socket.close(1000, 'busy') for any
                // connection attempt while one viewer is already active.
                try
                {
                    await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "busy", ct).ConfigureAwait(false);
                }
                catch { /* ignore */ }
                return;
            }

            try
            {
                await RunConnectionAsync(socket, ct).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                ServerError?.Invoke(ex.Message);
            }
            finally
            {
                bool wasViewer;
                lock (_viewerLock)
                {
                    wasViewer = ReferenceEquals(_viewerSocket, socket);
                    if (wasViewer) _viewerSocket = null;
                }
                if (wasViewer) ViewerDisconnected?.Invoke();
            }
        }
    }

    private async Task RunConnectionAsync(WebSocket socket, CancellationToken ct)
    {
        var buffer = new ArraySegment<byte>(new byte[64 * 1024]);
        bool authenticated = false;

        while (socket.State == WebSocketState.Open && !ct.IsCancellationRequested)
        {
            string? text = await ReceiveTextMessageAsync(socket, buffer, ct).ConfigureAwait(false);
            if (text is null) break;

            WireMessage? msg = WireMessageParser.TryParse(text);
            if (msg is null) continue;

            if (!authenticated)
            {
                // Matches src/main.js: "if (!socket.authenticated) return"
                // for anything before a successful auth message.
                if (msg is not AuthMessage auth) continue;

                if (auth.Password == _password)
                {
                    authenticated = true;
                    (int w, int h) = ScreenCapture.GetPrimaryMonitorSize();
                    await SendJsonAsync(socket, new AuthOkMessage { Width = w, Height = h }, ct).ConfigureAwait(false);

                    lock (_viewerLock) { _viewerSocket = socket; }
                    ViewerConnected?.Invoke();
                }
                else
                {
                    await SendJsonAsync(socket, new AuthFailMessage(), ct).ConfigureAwait(false);
                    try
                    {
                        await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, null, ct).ConfigureAwait(false);
                    }
                    catch { /* ignore */ }
                    break;
                }
                continue;
            }

            if (msg is MouseMoveMessage or MouseDownMessage or MouseUpMessage or MouseScrollMessage)
            {
                _mouseInjector.Enqueue(msg);
                MouseMessageReceived?.Invoke(msg);
            }
        }
    }

    private static async Task SendJsonAsync(WebSocket socket, WireMessage message, CancellationToken ct)
    {
        string json = JsonSerializer.Serialize(message, message.GetType());
        byte[] bytes = Encoding.UTF8.GetBytes(json);
        await socket.SendAsync(bytes, WebSocketMessageType.Text, true, ct).ConfigureAwait(false);
    }

    // ReceiveAsync can fragment a logical message across multiple calls
    // (unlike Node's `ws`, which hands back one assembled Buffer per
    // 'message' event) — loop until EndOfMessage before treating the bytes
    // as a complete JSON text message.
    private static async Task<string?> ReceiveTextMessageAsync(WebSocket socket, ArraySegment<byte> buffer, CancellationToken ct)
    {
        using var ms = new MemoryStream();

        while (true)
        {
            WebSocketReceiveResult result;
            try
            {
                result = await socket.ReceiveAsync(buffer, ct).ConfigureAwait(false);
            }
            catch (Exception ex) when (ex is WebSocketException or OperationCanceledException or ObjectDisposedException)
            {
                return null;
            }

            if (result.MessageType == WebSocketMessageType.Close)
            {
                try
                {
                    await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, null, ct).ConfigureAwait(false);
                }
                catch { /* ignore */ }
                return null;
            }

            if (result.MessageType == WebSocketMessageType.Binary)
            {
                // The host never expects binary from a viewer in this
                // protocol; drain the rest of the frame so the stream stays
                // in sync, then keep waiting for a real text message.
                while (!result.EndOfMessage)
                {
                    result = await socket.ReceiveAsync(buffer, ct).ConfigureAwait(false);
                }
                continue;
            }

            ms.Write(buffer.Array!, buffer.Offset, result.Count);
            if (result.EndOfMessage)
            {
                return Encoding.UTF8.GetString(ms.ToArray());
            }
        }
    }
}
