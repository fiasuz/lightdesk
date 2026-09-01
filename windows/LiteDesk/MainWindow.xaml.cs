using System.Windows;
using System.Windows.Controls;
using LiteDesk.Services;
using LiteDesk.Views;

namespace LiteDesk;

// Single-window, screen-swap navigation. Server/Tunnel live here (not on
// HomeView) so hosting stays available — the address in "Mening manzilim"
// keeps working — even while the window is showing an active viewer
// session; HomeView reads their current state whenever it's (re)created.
public partial class MainWindow : Window
{
    public HostServer Server { get; } = new();
    public CloudflareTunnelService Tunnel { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        Closing += (_, _) =>
        {
            Server.Stop();
            Tunnel.Stop();
        };
        // Bound here (not in HomeView) so it fires and can be answered
        // regardless of which screen is currently navigated to.
        Server.ConnectionRequested += OnConnectionRequested;
        NavigateHome();
    }

    public void NavigateHome() => Navigate(new HomeView(this));

    public void NavigateToSession(ViewerClient client, string host) => Navigate(new ViewerView(this, client, host));

    private void Navigate(UserControl view)
    {
        ContentHost.Content = view;
    }

    private void OnConnectionRequested(string? address)
    {
        Dispatcher.Invoke(() =>
        {
            ConnectionRequestAddressText.Text = address ?? "—";
            ConnectionRequestOverlay.Visibility = Visibility.Visible;
        });
    }

    private void ApproveConnectionButton_Click(object sender, RoutedEventArgs e)
    {
        ConnectionRequestOverlay.Visibility = Visibility.Collapsed;
        Server.ApproveConnection();
    }

    private void DeclineConnectionButton_Click(object sender, RoutedEventArgs e)
    {
        ConnectionRequestOverlay.Visibility = Visibility.Collapsed;
        Server.DeclineConnection();
    }
}
