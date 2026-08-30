using System.Windows.Controls;
using System.Windows.Input;

namespace LiteDesk.Views;

// Native port of src/renderer/index.html — two mode buttons, no other state.
public partial class HomeView : UserControl
{
    private readonly MainWindow _window;

    public HomeView(MainWindow window)
    {
        InitializeComponent();
        _window = window;
    }

    private void HostModeButton_Click(object sender, MouseButtonEventArgs e) => _window.NavigateHost();

    private void ViewerModeButton_Click(object sender, MouseButtonEventArgs e) => _window.NavigateViewer();
}
