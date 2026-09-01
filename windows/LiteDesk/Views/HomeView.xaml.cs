using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using LiteDesk.Localization;
using LiteDesk.Services;

namespace LiteDesk.Views;

// Unified home screen matching the "01 Ulanish" mockup: a "my address"
// panel (host role) and a "connect to other" panel (viewer role) shown
// together, no separate mode-select step. Hosting itself (Server/Tunnel) is
// owned by MainWindow, not this view, so the address keeps working while
// the window navigates to an active viewer session (see MainWindow) and
// back — a fresh HomeView just re-reads whatever state is already running.
public partial class HomeView : UserControl
{
    private const int Port = 5900;

    private readonly MainWindow _window;
    private readonly DispatcherTimer _hostPingTimer = new() { Interval = TimeSpan.FromSeconds(2) };
    private readonly DispatcherTimer _hostElapsedTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly System.Diagnostics.Stopwatch _hostSessionStopwatch = new();
    private string _pin = "";
    private string? _connectionCode;
    private bool _viewerConnected;

    public HomeView(MainWindow window)
    {
        InitializeComponent();
        _window = window;

        LanguageCombo.SelectedIndex = (int)LocalizationManager.Instance.Language;
        LanguageCombo.SelectionChanged += LanguageCombo_SelectionChanged;

        _window.Server.ViewerConnected += OnViewerConnected;
        _window.Server.ViewerDisconnected += OnViewerDisconnected;
        _window.Server.ServerError += OnServerError;
        _window.Server.PongReceived += OnHostPongReceived;
        _window.Server.OutgoingStatsUpdated += OnHostStatsUpdated;
        _window.Tunnel.StateChanged += OnTunnelStateChanged;

        _hostPingTimer.Tick += (_, _) => _ = _window.Server.SendPingAsync();
        _hostElapsedTimer.Tick += (_, _) => HostElapsedText.Text = _hostSessionStopwatch.Elapsed.ToString(@"hh\:mm\:ss");

        RefreshHostStatusText();

        if (_window.Server.IsRunning)
        {
            _pin = _window.Server.CurrentPassword ?? "";
            ApplyTunnelState(_window.Tunnel.CurrentState);
            if (_window.Server.HasViewer) BeginConnectedUi();
        }
        else
        {
            StartHosting();
        }

        Unloaded += (_, _) =>
        {
            _window.Server.ViewerConnected -= OnViewerConnected;
            _window.Server.ViewerDisconnected -= OnViewerDisconnected;
            _window.Server.ServerError -= OnServerError;
            _window.Server.PongReceived -= OnHostPongReceived;
            _window.Server.OutgoingStatsUpdated -= OnHostStatsUpdated;
            _window.Tunnel.StateChanged -= OnTunnelStateChanged;
            _hostPingTimer.Stop();
            _hostElapsedTimer.Stop();
        };
    }

    private static string Loc(string key) => LocalizationManager.Instance[key];

    private static string GenerateRandomPin() => Random.Shared.Next(100000, 1000000).ToString();

    private void StartHosting()
    {
        _pin = GenerateRandomPin();
        MyAddressText.Text = Loc("Home.MyAddress.Opening");

        (bool success, string? error) = _window.Server.Start(Port, _pin);
        if (!success)
        {
            MyAddressText.Text = $"{Loc("Common.Error")}: {error}";
            return;
        }

        _window.Tunnel.Start(Port);
    }

    private void ApplyTunnelState(TunnelState state)
    {
        switch (state.Status)
        {
            case TunnelStatus.Running:
                _connectionCode = BuildConnectionCode(_pin, state.Url!);
                MyAddressText.Text = _connectionCode;
                CopyButton.IsEnabled = true;
                ShareButton.IsEnabled = true;
                break;
            case TunnelStatus.Failed:
                _connectionCode = null;
                MyAddressText.Text = $"{Loc("Common.Error")}: {state.Error}";
                CopyButton.IsEnabled = false;
                ShareButton.IsEnabled = false;
                break;
            default:
                _connectionCode = null;
                MyAddressText.Text = Loc("Home.MyAddress.Opening");
                CopyButton.IsEnabled = false;
                ShareButton.IsEnabled = false;
                break;
        }
    }

    // Bundles the PIN and tunnel host into the single code the connect
    // panel parses (see TryParseConnectionCode) — the viewer never has to
    // paste the raw tunnel link separately. The ".trycloudflare.com" suffix
    // is stripped here (and re-added on parse) purely to keep the shared
    // code shorter/cleaner.
    private static string BuildConnectionCode(string pin, string url)
    {
        string host = url;
        foreach (string prefix in new[] { "https://", "http://" })
        {
            if (host.StartsWith(prefix, StringComparison.Ordinal)) host = host[prefix.Length..];
        }
        host = host.TrimEnd('/');
        if (host.EndsWith(TunnelDomainSuffix, StringComparison.Ordinal))
        {
            host = host[..^TunnelDomainSuffix.Length];
        }
        return $"{pin}-{host}";
    }

    // Every Cloudflare quick tunnel lives under this domain — stripped off
    // the shared code above so the user never sees or types it, re-added by
    // TryParseConnectionCode.
    internal const string TunnelDomainSuffix = ".trycloudflare.com";

    // Accepts either a pasted full URL (https://xxxx.trycloudflare.com) or a
    // bare hostname (xxxx.trycloudflare.com) and returns just the host part.
    private static string NormalizeTunnelAddress(string input)
    {
        if (input.Contains("://", StringComparison.Ordinal) && Uri.TryCreate(input, UriKind.Absolute, out Uri? parsed))
        {
            return parsed.Host;
        }
        return input.TrimEnd('/');
    }

    // A connection code (as shown in "Mening manzilim") is "<6-digit
    // PIN>-<tunnel subdomain>", e.g. "123456-actual-words". Splitting on the
    // fixed 6-digit PIN prefix (rather than the first "-") is what keeps
    // this safe even though the tunnel subdomain itself contains hyphens.
    private static bool TryParseConnectionCode(string raw, out string host, out string pin)
    {
        host = string.Empty;
        pin = string.Empty;

        string trimmed = raw.Trim();
        if (trimmed.Length <= 7) return false;

        string candidatePin = trimmed[..6];
        if (!candidatePin.All(char.IsDigit)) return false;
        if (trimmed[6] != '-') return false;

        string normalizedHost = NormalizeTunnelAddress(trimmed[7..]);
        if (string.IsNullOrEmpty(normalizedHost)) return false;
        if (!normalizedHost.EndsWith(TunnelDomainSuffix, StringComparison.Ordinal))
        {
            normalizedHost += TunnelDomainSuffix;
        }

        host = normalizedHost;
        pin = candidatePin;
        return true;
    }

    private void OnTunnelStateChanged(TunnelState state)
    {
        Dispatcher.Invoke(() => ApplyTunnelState(state));
    }

    private void OnViewerConnected()
    {
        Dispatcher.Invoke(BeginConnectedUi);
    }

    private void BeginConnectedUi()
    {
        _viewerConnected = true;
        HostStatusDot.Fill = (Brush)FindResource("OkBrush");
        RefreshHostStatusText();
        HostStatsPanel.Visibility = Visibility.Visible;
        HostPingText.Text = "—";
        HostFpsText.Text = "—";
        HostElapsedText.Text = "00:00:00";
        _hostSessionStopwatch.Restart();
        _hostElapsedTimer.Start();
        _hostPingTimer.Start();
    }

    private void OnViewerDisconnected()
    {
        Dispatcher.Invoke(() =>
        {
            _viewerConnected = false;
            HostStatusDot.Fill = (Brush)FindResource("SubtitleBrush");
            RefreshHostStatusText();
            HostStatsPanel.Visibility = Visibility.Collapsed;
            _hostElapsedTimer.Stop();
            _hostPingTimer.Stop();
            _hostSessionStopwatch.Reset();
        });
    }

    private void RefreshHostStatusText()
    {
        HostStatusText.Text = _viewerConnected ? Loc("Home.MyAddress.Connected") : Loc("Home.MyAddress.Waiting");
    }

    // Real round-trip time from a ping this side sent — see
    // HostServer.SendPingAsync / PongReceived. Never simulated.
    private void OnHostPongReceived(double rttMs)
    {
        Dispatcher.Invoke(() => HostPingText.Text = $"{Math.Round(rttMs)} ms");
    }

    // Real outgoing capture rate/throughput — see HostServer.OutgoingStatsUpdated,
    // computed from the actual frames pushed to the viewer.
    private void OnHostStatsUpdated(int fps, double kbps)
    {
        Dispatcher.Invoke(() => HostFpsText.Text = fps.ToString());
    }

    private void OnServerError(string message)
    {
        Dispatcher.Invoke(() => MyAddressText.Text = $"{Loc("Common.Error")}: {message}");
    }

    private void CopyButton_Click(object sender, RoutedEventArgs e)
    {
        if (_connectionCode is not null) Clipboard.SetText(_connectionCode);
    }

    private void ShareButton_Click(object sender, RoutedEventArgs e)
    {
        // No native share sheet on Windows for this — clipboard is the
        // practical equivalent (matches Copy) until a real share target
        // exists.
        if (_connectionCode is not null) Clipboard.SetText(_connectionCode);
    }

    private void NewAddressButton_Click(object sender, RoutedEventArgs e)
    {
        _window.Server.Stop();
        _window.Tunnel.Stop();
        StartHosting();
    }

    private void LanguageCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (LanguageCombo.SelectedIndex < 0) return;
        LocalizationManager.Instance.Language = (AppLanguage)LanguageCombo.SelectedIndex;
        RefreshHostStatusText();
    }

    private async void ConnectButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryParseConnectionCode(ConnectAddressBox.Text, out string host, out string password))
        {
            SetConnectStatus(Loc("Home.Connect.InvalidCode"), isError: true);
            return;
        }

        SetConnectStatus(Loc("Home.Connect.Connecting"), isError: false);
        ConnectButton.IsEnabled = false;

        var client = new ViewerClient();
        var (success, error, _, _) = await client.ConnectAsync(host, password);

        ConnectButton.IsEnabled = true;

        if (!success)
        {
            SetConnectStatus($"{Loc("Common.Error")}: {error}", isError: true);
            client.Disconnect();
            return;
        }

        SetConnectStatus(string.Empty, isError: false);
        _window.NavigateToSession(client, host);
    }

    private void SetConnectStatus(string text, bool isError)
    {
        ConnectStatusText.Text = text;
        ConnectStatusText.Foreground = (Brush)FindResource(isError ? "ErrBrush" : "SubtitleBrush");
    }
}
