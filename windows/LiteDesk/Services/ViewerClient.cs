using System.IO;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using LiteDesk.Protocol;

namespace LiteDesk.Services;

// Viewer-mode WebSocket client. Port of the viewer-mode block of
// src/main.js: ClientWebSocket (fully RFC6455-compliant out of the box, no
// hand-rolled framing needed on this side), auth handshake, then a receive
// loop that surfaces binary frames and forwards outgoing mouse events.
// FrameReceived hands back raw JPEG bytes; Views/ViewerView.xaml.cs decodes
// and renders them and drives SendMouseEventAsync from local input.
public sealed class ViewerClient
{
    private ClientWebSocket? _socket;
    private CancellationTokenSource? _cts;

    // ClientWebSocket allows only one outstanding SendAsync at a time; a
    // second concurrent call throws InvalidOperationException. MouseMove
    // fires fire-and-forget on every pointer move (up to ~40/s), so without
    // serializing here, a move whose send is still in flight when the next
    // one starts would throw and get silently dropped by the catch below —
    // live cursor movement would go missing while rarer MouseDown/Up sends
    // (which don't overlap) kept working.
    private readonly SemaphoreSlim _sendLock = new(1, 1);

    public event Action<byte[]>? FrameReceived;
    public event Action? ConnectionClosed;

    public bool IsConnected => _socket?.State == WebSocketState.Open;

    public async Task<(bool Success, string? Error, int Width, int Height)> ConnectAsync(string ip, int port, string password)
    {
        Disconnect();

        var socket = new ClientWebSocket();
        var cts = new CancellationTokenSource();

        try
        {
            await socket.ConnectAsync(new Uri($"ws://{ip}:{port}/"), cts.Token).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            socket.Dispose();
            cts.Dispose();
            return (false, ex.Message, 0, 0);
        }

        _socket = socket;
        _cts = cts;

        try
        {
            var auth = new AuthMessage { Password = password };
            string authJson = JsonSerializer.Serialize(auth, auth.GetType());
            await socket.SendAsync(Encoding.UTF8.GetBytes(authJson), WebSocketMessageType.Text, true, cts.Token)
                .ConfigureAwait(false);

            string? replyJson = await ReceiveOneTextMessageAsync(socket, cts.Token).ConfigureAwait(false);
            if (replyJson is null)
            {
                return (false, "Ulanib bo'lmadi (server yopiq yoki band)", 0, 0);
            }

            WireMessage? reply = WireMessageParser.TryParse(replyJson);
            switch (reply)
            {
                case AuthOkMessage ok:
                    _ = ReceiveLoopAsync(socket, cts.Token);
                    return (true, null, ok.Width, ok.Height);
                case AuthFailMessage:
                    return (false, "Parol noto'g'ri", 0, 0);
                default:
                    return (false, "Kutilmagan javob", 0, 0);
            }
        }
        catch (Exception ex)
        {
            return (false, ex.Message, 0, 0);
        }
    }

    public void Disconnect()
    {
        _cts?.Cancel();
        _cts?.Dispose();
        _cts = null;

        try { _socket?.Abort(); } catch { /* ignore */ }
        _socket?.Dispose();
        _socket = null;
    }

    // Sends mouse-move/down/up/scroll messages while connected; driven by
    // Views/ViewerView.xaml.cs's local input capture.
    public async Task SendMouseEventAsync(WireMessage message)
    {
        ClientWebSocket? socket = _socket;
        if (socket is null || socket.State != WebSocketState.Open) return;

        await _sendLock.WaitAsync().ConfigureAwait(false);
        try
        {
            if (socket.State != WebSocketState.Open) return;

            string json = JsonSerializer.Serialize(message, message.GetType());
            await socket.SendAsync(Encoding.UTF8.GetBytes(json), WebSocketMessageType.Text, true, CancellationToken.None)
                .ConfigureAwait(false);
        }
        catch
        {
            // Connection likely closing; the receive loop will raise
            // ConnectionClosed.
        }
        finally
        {
            _sendLock.Release();
        }
    }

    private static async Task<string?> ReceiveOneTextMessageAsync(ClientWebSocket socket, CancellationToken ct)
    {
        var buffer = new ArraySegment<byte>(new byte[64 * 1024]);
        using var ms = new MemoryStream();

        WebSocketReceiveResult result;
        do
        {
            result = await socket.ReceiveAsync(buffer, ct).ConfigureAwait(false);
            if (result.MessageType == WebSocketMessageType.Close) return null;
            ms.Write(buffer.Array!, buffer.Offset, result.Count);
        } while (!result.EndOfMessage);

        return Encoding.UTF8.GetString(ms.ToArray());
    }

    private async Task ReceiveLoopAsync(ClientWebSocket socket, CancellationToken ct)
    {
        var buffer = new ArraySegment<byte>(new byte[256 * 1024]);

        try
        {
            while (socket.State == WebSocketState.Open && !ct.IsCancellationRequested)
            {
                using var ms = new MemoryStream();
                WebSocketMessageType? messageType = null;
                WebSocketReceiveResult result;
                bool closed = false;

                do
                {
                    result = await socket.ReceiveAsync(buffer, ct).ConfigureAwait(false);
                    messageType ??= result.MessageType;
                    if (result.MessageType == WebSocketMessageType.Close) { closed = true; break; }
                    ms.Write(buffer.Array!, buffer.Offset, result.Count);
                } while (!result.EndOfMessage);

                if (closed) break;

                if (messageType == WebSocketMessageType.Binary)
                {
                    FrameReceived?.Invoke(ms.ToArray());
                }
                // Text messages other than the initial auth-ok/auth-fail
                // aren't expected post-handshake in this protocol; ignore.
            }
        }
        catch (Exception ex) when (ex is WebSocketException or OperationCanceledException or ObjectDisposedException)
        {
            // Falls through to ConnectionClosed below.
        }
        finally
        {
            ConnectionClosed?.Invoke();
        }
    }
}
