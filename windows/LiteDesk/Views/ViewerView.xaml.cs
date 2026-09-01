using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using LiteDesk.Localization;
using LiteDesk.Native;
using LiteDesk.Protocol;
using LiteDesk.Services;

namespace LiteDesk.Views;

// "02 Faol seans" — renders incoming JPEG frames onto RemoteImage and
// captures local mouse/keyboard input over it, normalized to the same 0..1
// coordinate convention the wire protocol uses. The connect form itself
// lives on HomeView now; this view only ever handles an already-connected
// ViewerClient handed to it by MainWindow.NavigateToSession.
public partial class ViewerView : UserControl
{
    private const int MouseThrottleMs = 25; // matches MOUSE_THROTTLE_MS in viewer.js

    private readonly MainWindow _window;
    private readonly ViewerClient _client;
    private readonly Stopwatch _stopwatch = Stopwatch.StartNew();
    // Not long.MinValue: `now - _lastMouseMoveMs` in RemoteImage_MouseMove
    // overflows a signed long when subtracting MinValue (wraps to a huge
    // negative number in unchecked arithmetic), which made the throttle
    // check permanently true — every mouse-move was silently dropped,
    // forever, from the very first call onward. -MouseThrottleMs guarantees
    // `now - _lastMouseMoveMs >= MouseThrottleMs` on the first real call
    // (now is always >= 0) without any overflow risk.
    private long _lastMouseMoveMs = -MouseThrottleMs;

    // Session readout in the topbar: FPS is a real count of frames that
    // arrived in the last second (Interlocked because frames land on the
    // WebSocket receive thread, not the UI thread — see OnFrameReceived);
    // ping is a real round-trip time from PingMessage/PongMessage; elapsed
    // time is a real stopwatch started on connect. None of these are
    // simulated.
    private readonly Stopwatch _sessionStopwatch = new();
    private readonly DispatcherTimer _statsTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly DispatcherTimer _pingTimer = new() { Interval = TimeSpan.FromSeconds(2) };
    private int _framesSinceLastTick;

    public ViewerView(MainWindow window, ViewerClient client, string host)
    {
        InitializeComponent();
        _window = window;
        _client = client;

        RemoteInfoText.Text = string.Format(LocalizationManager.Instance["Session.ConnectedTo"], host);

        _client.FrameReceived += OnFrameReceived;
        _client.ConnectionClosed += OnConnectionClosed;
        _client.PongReceived += OnPongReceived;
        _statsTimer.Tick += (_, _) =>
        {
            FpsText.Text = Interlocked.Exchange(ref _framesSinceLastTick, 0).ToString();
            ViewerElapsedText.Text = _sessionStopwatch.Elapsed.ToString(@"hh\:mm\:ss");
        };
        _pingTimer.Tick += (_, _) => _ = _client.SendPingAsync();

        Loaded += (_, _) =>
        {
            RemoteImage.Focus();
            _framesSinceLastTick = 0;
            FpsText.Text = "—";
            PingText.Text = "—";
            ViewerElapsedText.Text = "00:00:00";
            _sessionStopwatch.Restart();
            _statsTimer.Start();
            _pingTimer.Start();
        };

        Unloaded += (_, _) =>
        {
            _client.FrameReceived -= OnFrameReceived;
            _client.ConnectionClosed -= OnConnectionClosed;
            _client.PongReceived -= OnPongReceived;
            _statsTimer.Stop();
            _pingTimer.Stop();
            _client.Disconnect();
        };
    }

    private void DisconnectButton_Click(object sender, RoutedEventArgs e)
    {
        _client.Disconnect();
        _window.NavigateHome();
    }

    private void OnConnectionClosed()
    {
        Dispatcher.Invoke(() => _window.NavigateHome());
    }

    private void OnPongReceived(double rttMs)
    {
        Dispatcher.Invoke(() => PingText.Text = $"{Math.Round(rttMs)} ms");
    }

    // Frames arrive on the WebSocket receive loop's background thread, not
    // the UI thread — must marshal onto the Dispatcher before touching
    // RemoteImage.
    private void OnFrameReceived(byte[] jpegBytes)
    {
        Interlocked.Increment(ref _framesSinceLastTick);
        _ = Dispatcher.InvokeAsync(() =>
        {
            try
            {
                using var ms = new MemoryStream(jpegBytes);
                BitmapFrame frame = BitmapFrame.Create(ms, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
                RemoteImage.Source = frame;
            }
            catch
            {
                // Ignore malformed/partial frame — matches viewer.js's
                // try/catch around createImageBitmap.
            }
        });
    }

    private void RemoteImage_MouseMove(object sender, MouseEventArgs e)
    {
        long now = _stopwatch.ElapsedMilliseconds;
        if (now - _lastMouseMoveMs < MouseThrottleMs) return;
        _lastMouseMoveMs = now;

        if (!TryGetNormalizedPosition(e, out double x, out double y)) return;
        _ = _client.SendMouseEventAsync(new MouseMoveMessage { X = x, Y = y });
    }

    private void RemoteImage_MouseDown(object sender, MouseButtonEventArgs e)
    {
        // Clicking the remote surface is also how keyboard focus lands back
        // on it (e.g. after the user was typing in the connection-address
        // box on HomeView, or clicked some other window and came back).
        RemoteImage.Focus();
        if (!TryGetNormalizedPosition(e, out double x, out double y)) return;
        _ = _client.SendMouseEventAsync(new MouseDownMessage { X = x, Y = y, Button = ButtonName(e.ChangedButton) });
    }

    private void RemoteImage_MouseUp(object sender, MouseButtonEventArgs e)
    {
        _ = _client.SendMouseEventAsync(new MouseUpMessage { Button = ButtonName(e.ChangedButton) });
    }

    private void RemoteImage_MouseWheel(object sender, MouseWheelEventArgs e)
    {
        // WPF's Delta uses the OPPOSITE sign convention from a browser
        // `wheel` event's deltaY — see the original inline note in the
        // pre-redesign ViewerView.xaml.cs (git history) for the full
        // reasoning; only vertical scroll is wired (Dx is always 0), since
        // WPF has no standard horizontal wheel event without a raw
        // WM_MOUSEHWHEEL hook.
        double dy = -e.Delta;
        _ = _client.SendMouseEventAsync(new MouseScrollMessage { Dx = 0, Dy = dy });
        e.Handled = true;
    }

    // Held-down modifier/navigation keys (Alt, Tab, arrows, F10, ...) surface
    // through e.Key == Key.System or would otherwise be swallowed by WPF's
    // own accelerator/focus-navigation handling before a plain KeyDown
    // handler ever sees them — using Preview* and marking e.Handled = true
    // is what keeps them from also acting locally (menu access keys, tab
    // focus movement) while forwarding them to the remote host.
    private void RemoteImage_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (!TrySendKeyEvent(e, isDown: true)) return;
        e.Handled = true;
    }

    private void RemoteImage_PreviewKeyUp(object sender, KeyEventArgs e)
    {
        if (!TrySendKeyEvent(e, isDown: false)) return;
        e.Handled = true;
    }

    private bool TrySendKeyEvent(KeyEventArgs e, bool isDown)
    {
        Key key = e.Key == Key.System ? e.SystemKey : e.Key;
        int virtualKey = KeyInterop.VirtualKeyFromKey(key);
        string? code = KeyCodeMap.DomCode(virtualKey);
        if (code is null) return false;

        WireMessage message = isDown ? new KeyDownMessage { Code = code } : new KeyUpMessage { Code = code };
        _ = _client.SendMouseEventAsync(message);
        return true;
    }

    private void RemoteImage_ContextMenuOpening(object sender, ContextMenuEventArgs e)
    {
        // Matches viewer.js: canvas.addEventListener('contextmenu', e =>
        // e.preventDefault()) — right-click is a remote "right click", not
        // a local context menu.
        e.Handled = true;
    }

    private static string ButtonName(MouseButton button) => button switch
    {
        MouseButton.Right => "right",
        MouseButton.Middle => "middle",
        _ => "left",
    };

    // Maps a mouse position (relative to RemoteImage) into the 0..1
    // normalized coordinate space the wire protocol uses. Critical: this
    // must account for Stretch="Uniform" letterboxing — the control's
    // ActualWidth/ActualHeight can have a different aspect ratio than the
    // JPEG frame, so the image is scaled to fit and centered, leaving
    // pillarbox/letterbox bars that are NOT part of the remote screen.
    // Returns false (skip sending) if the position falls in a bar.
    private bool TryGetNormalizedPosition(MouseEventArgs e, out double x, out double y)
    {
        x = y = 0;

        if (RemoteImage.Source is not BitmapSource source) return false;

        double controlWidth = RemoteImage.ActualWidth;
        double controlHeight = RemoteImage.ActualHeight;
        double imageWidth = source.PixelWidth;
        double imageHeight = source.PixelHeight;
        if (controlWidth <= 0 || controlHeight <= 0 || imageWidth <= 0 || imageHeight <= 0) return false;

        double scale = Math.Min(controlWidth / imageWidth, controlHeight / imageHeight);
        double displayedWidth = imageWidth * scale;
        double displayedHeight = imageHeight * scale;
        double offsetX = (controlWidth - displayedWidth) / 2.0;
        double offsetY = (controlHeight - displayedHeight) / 2.0;

        Point p = e.GetPosition(RemoteImage);
        double localX = p.X - offsetX;
        double localY = p.Y - offsetY;

        if (localX < 0 || localY < 0 || localX > displayedWidth || localY > displayedHeight) return false;

        x = Math.Min(Math.Max(localX / displayedWidth, 0), 1);
        y = Math.Min(Math.Max(localY / displayedHeight, 0), 1);
        return true;
    }
}
