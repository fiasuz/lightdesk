using System.Windows;
using System.Windows.Controls;
using LiteDesk.Views;

namespace LiteDesk;

// Single-window, screen-swap navigation, mirroring the current Electron app's
// single BrowserWindow that loads index.html/host.html/viewer.html — no
// multi-window/MVVM framework, just a ContentControl whose content is swapped.
public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        NavigateHome();
    }

    public void NavigateHome() => Navigate(new HomeView(this));
    public void NavigateHost() => Navigate(new HostView(this));
    public void NavigateViewer() => Navigate(new ViewerView(this));

    private void Navigate(UserControl view)
    {
        ContentHost.Content = view;
    }
}
