using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using LiteDesk.Services;

namespace LiteDesk.Views;

// Native port of src/renderer/host.js. Screen capture and mouse injection
// are not wired in yet (Phase 3 / Phase 4) — starting host mode here only
// stands up the WebSocket server and shows connection status.
public partial class HostView : UserControl
{
    private readonly MainWindow _window;
    private readonly HostServer _server = new();
    private readonly CloudflareTunnelService _tunnel = new();
    private string? _connectionCode;

    public HostView(MainWindow window)
    {
        InitializeComponent();
        _window = window;

        PasswordBox.Text = GenerateRandomPin();

        _server.ViewerConnected += OnViewerConnected;
        _server.ViewerDisconnected += OnViewerDisconnected;
        _server.ServerError += OnServerError;
        _tunnel.StateChanged += OnTunnelStateChanged;

        Unloaded += (_, _) =>
        {
            _server.Stop();
            _tunnel.Stop();
        };
    }

    private static string GenerateRandomPin()
    {
        int pin = Random.Shared.Next(100000, 1000000);
        return pin.ToString();
    }

    private void BackLink_Click(object sender, MouseButtonEventArgs e)
    {
        _server.Stop();
        _tunnel.Stop();
        _window.NavigateHome();
    }

    private void StartButton_Click(object sender, RoutedEventArgs e)
    {
        string password = PasswordBox.Text.Trim();
        if (string.IsNullOrEmpty(password))
        {
            SetSetupStatus("Parol kiriting", isError: true);
            return;
        }

        if (!int.TryParse(PortBox.Text, out int port)) port = 5900;

        SetSetupStatus("Ishga tushirilmoqda...", isError: false);

        (bool success, string? error) = _server.Start(port, password);
        if (!success)
        {
            SetSetupStatus($"Xato: {error}", isError: true);
            return;
        }

        PinDisplayText.Text = password;
        IpListText.Text = FormatLocalIps();
        SetupCard.Visibility = Visibility.Collapsed;
        RunningCard.Visibility = Visibility.Visible;

        if (TunnelCheckBox.IsChecked == true)
        {
            _tunnel.Start(port);
        }
        else
        {
            TunnelStatusText.Visibility = Visibility.Collapsed;
        }
    }

    private void StopButton_Click(object sender, RoutedEventArgs e)
    {
        _server.Stop();
        _tunnel.Stop();
        TunnelStatusText.Visibility = Visibility.Collapsed;
        RunningCard.Visibility = Visibility.Collapsed;
        SetupCard.Visibility = Visibility.Visible;
        SetSetupStatus(string.Empty, isError: false);
    }

    private void OnTunnelStateChanged(TunnelState state)
    {
        Dispatcher.Invoke(() =>
        {
            switch (state.Status)
            {
                case TunnelStatus.Starting:
                    TunnelStatusText.Text = "Internet tunnel ochilmoqda...";
                    TunnelStatusText.Foreground = (Brush)FindResource("SubtitleBrush");
                    TunnelStatusText.Visibility = Visibility.Visible;
                    CopyCodeButton.Visibility = Visibility.Collapsed;
                    break;
                case TunnelStatus.Running:
                    _connectionCode = BuildConnectionCode(PinDisplayText.Text, state.Url!);
                    TunnelStatusText.Text = $"Ulanish kodi: {_connectionCode}";
                    TunnelStatusText.Foreground = (Brush)FindResource("OkBrush");
                    TunnelStatusText.Visibility = Visibility.Visible;
                    CopyCodeButton.Visibility = Visibility.Visible;
                    break;
                case TunnelStatus.Failed:
                    TunnelStatusText.Text = $"Internet tunnel xatosi: {state.Error}";
                    TunnelStatusText.Foreground = (Brush)FindResource("ErrBrush");
                    TunnelStatusText.Visibility = Visibility.Visible;
                    CopyCodeButton.Visibility = Visibility.Collapsed;
                    break;
                default:
                    TunnelStatusText.Visibility = Visibility.Collapsed;
                    CopyCodeButton.Visibility = Visibility.Collapsed;
                    break;
            }
        });
    }

    // Bundles the PIN and tunnel host into the single code the viewer's
    // "Ulanish kodi" field parses (see ViewerView.TryParseConnectionCode) —
    // the viewer no longer needs the raw tunnel link pasted separately. The
    // ".trycloudflare.com" suffix is stripped here (and re-added by the
    // viewer when parsing) so the user never has to see or type it.
    private static string BuildConnectionCode(string pin, string url)
    {
        string host = url;
        foreach (string prefix in new[] { "https://", "http://" })
        {
            if (host.StartsWith(prefix, StringComparison.Ordinal)) host = host[prefix.Length..];
        }
        host = host.TrimEnd('/');
        if (host.EndsWith(ViewerView.TunnelDomainSuffix, StringComparison.Ordinal))
        {
            host = host[..^ViewerView.TunnelDomainSuffix.Length];
        }
        return $"{pin}-{host}";
    }

    private void CopyCodeButton_Click(object sender, RoutedEventArgs e)
    {
        if (_connectionCode is not null) Clipboard.SetText(_connectionCode);
    }

    private void OnViewerConnected()
    {
        Dispatcher.Invoke(() =>
        {
            ConnStatusText.Text = "Ulandi — masofaviy foydalanuvchi sichqonchani boshqarmoqda";
            ConnStatusText.Foreground = (Brush)FindResource("OkBrush");
        });
    }

    private void OnViewerDisconnected()
    {
        Dispatcher.Invoke(() =>
        {
            ConnStatusText.Text = "Ulanish kutilmoqda...";
            ConnStatusText.Foreground = (Brush)FindResource("TextBrush");
        });
    }

    private void OnServerError(string message)
    {
        Dispatcher.Invoke(() => SetSetupStatus($"Server xatosi: {message}", isError: true));
    }

    private void SetSetupStatus(string text, bool isError)
    {
        SetupStatusText.Text = text;
        SetupStatusText.Foreground = (Brush)FindResource(isError ? "ErrBrush" : "SubtitleBrush");
    }

    // Port of the "get-local-ips" IPC handler in src/main.js.
    private static string FormatLocalIps()
    {
        var ips = new List<string>();

        foreach (NetworkInterface ni in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (ni.OperationalStatus != OperationalStatus.Up) continue;

            foreach (UnicastIPAddressInformation addr in ni.GetIPProperties().UnicastAddresses)
            {
                if (addr.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                if (System.Net.IPAddress.IsLoopback(addr.Address)) continue;
                ips.Add(addr.Address.ToString());
            }
        }

        return ips.Count > 0
            ? string.Join(", ", ips) + " manzillaridan biri"
            : "IP manzil topilmadi";
    }
}
