using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LiteDesk.Protocol;
using LiteDesk.Services;

namespace LiteDesk.Views;

// Native port of src/renderer/viewer.js: renders incoming JPEG frames onto
// RemoteImage and captures local mouse input over it, normalized to the
// same 0..1 coordinate convention the wire protocol uses.
public partial class ViewerView : UserControl
{
    private const int MouseThrottleMs = 25; // matches MOUSE_THROTTLE_MS in viewer.js

    private readonly MainWindow _window;
    private readonly ViewerClient _client = new();
    private readonly Stopwatch _stopwatch = Stopwatch.StartNew();
    private long _lastMouseMoveMs = long.MinValue;

    public ViewerView(MainWindow window)
    {
        InitializeComponent();
        _window = window;

        _client.FrameReceived += OnFrameReceived;
        _client.ConnectionClosed += OnConnectionClosed;

        Unloaded += (_, _) => _client.Disconnect();
    }

    private void BackLink_Click(object sender, MouseButtonEventArgs e)
    {
        _client.Disconnect();
        _window.NavigateHome();
    }

    private async void ConnectButton_Click(object sender, RoutedEventArgs e)
    {
        string ip = IpBox.Text.Trim();
        string password = PasswordBox.Text.Trim();
        if (!int.TryParse(PortBox.Text, out int port)) port = 5900;

        if (string.IsNullOrEmpty(ip) || string.IsNullOrEmpty(password))
        {
            SetStatus("IP va parolni kiriting", isError: true);
            return;
        }

        SetStatus("Ulanmoqda...", isError: false);
        ConnectButton.IsEnabled = false;

        var (success, error, _, _) = await _client.ConnectAsync(ip, port, password);
        ConnectButton.IsEnabled = true;

        if (!success)
        {
            SetStatus($"Xato: {error}", isError: true);
            return;
        }

        RemoteInfoText.Text = $"{ip}:{port} bilan ulanildi";
        RemoteImage.Source = null;
        SetupScreen.Visibility = Visibility.Collapsed;
        RemoteScreen.Visibility = Visibility.Visible;
    }

    private void DisconnectButton_Click(object sender, RoutedEventArgs e)
    {
        _client.Disconnect();
        BackToSetup();
    }

    private void OnConnectionClosed()
    {
        Dispatcher.Invoke(BackToSetup);
    }

    private void BackToSetup()
    {
        RemoteScreen.Visibility = Visibility.Collapsed;
        SetupScreen.Visibility = Visibility.Visible;
        SetStatus("Ulanish uzildi", isError: true);
    }

    private void SetStatus(string text, bool isError)
    {
        StatusText.Text = text;
        StatusText.Foreground = (Brush)FindResource(isError ? "ErrBrush" : "SubtitleBrush");
    }

    // Frames arrive on the WebSocket receive loop's background thread, not
    // the UI thread — must marshal onto the Dispatcher before touching
    // RemoteImage.
    private void OnFrameReceived(byte[] jpegBytes)
    {
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

    // TEMP DIAGNOSTIC — remove once the live-move bug is root-caused.
    private static void DebugLog(string line)
    {
        try
        {
            string path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "litedesk-viewer-debug.log");
            System.IO.File.AppendAllText(path, $"{DateTime.Now:HH:mm:ss.fff} VIEW {line}{Environment.NewLine}");
        }
        catch { /* diagnostic only */ }
    }

    private void RemoteImage_MouseMove(object sender, MouseEventArgs e)
    {
        long now = _stopwatch.ElapsedMilliseconds;
        if (now - _lastMouseMoveMs < MouseThrottleMs)
        {
            DebugLog("MouseMove fired, throttled");
            return;
        }
        _lastMouseMoveMs = now;

        if (!TryGetNormalizedPosition(e, out double x, out double y))
        {
            DebugLog("MouseMove fired, TryGetNormalizedPosition FAILED (outside displayed image / no frame yet)");
            return;
        }
        DebugLog($"MouseMove fired, sending x={x:F3} y={y:F3}");
        _ = _client.SendMouseEventAsync(new MouseMoveMessage { X = x, Y = y });
    }

    private void RemoteImage_MouseDown(object sender, MouseButtonEventArgs e)
    {
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
        // `wheel` event's deltaY: WPF positive = wheel rotated
        // forward/away from the user (traditionally scrolls content up),
        // while a JS wheel event's positive deltaY means "scroll down"
        // (the convention src/mouseControl.js's dy handling was written
        // against, and that Windows' own MouseInjector.Scroll — see its
        // inline comment — passes straight through to SendInput without
        // re-inverting). Negating here is the best reasoning available
        // without a real mouse to test against; verify the net direction
        // feels right end-to-end (viewer wheel -> wire -> host cursor)
        // once this and the host build both run on real hardware.
        //
        // Only vertical scroll is wired — WPF has no standard horizontal
        // wheel event without a raw WM_MOUSEHWHEEL hook, so Dx is always 0
        // here (a deliberate simplification vs. the browser-based viewer,
        // which does forward trackpad deltaX).
        double dy = -e.Delta;
        _ = _client.SendMouseEventAsync(new MouseScrollMessage { Dx = 0, Dy = dy });
        e.Handled = true;
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
