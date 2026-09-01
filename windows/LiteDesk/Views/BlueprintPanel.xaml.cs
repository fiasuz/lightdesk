using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;

namespace LiteDesk.Views;

// PanelContent (rather than the inherited Content) carries the payload so
// nested XAML still reads naturally — see BlueprintPanel.xaml's comment for
// why Content itself can't be reused here.
[ContentProperty(nameof(PanelContent))]
public partial class BlueprintPanel : UserControl
{
    public static readonly DependencyProperty PanelContentProperty =
        DependencyProperty.Register(nameof(PanelContent), typeof(object), typeof(BlueprintPanel));

    public object PanelContent
    {
        get => GetValue(PanelContentProperty);
        set => SetValue(PanelContentProperty, value);
    }

    public BlueprintPanel()
    {
        InitializeComponent();
    }
}
