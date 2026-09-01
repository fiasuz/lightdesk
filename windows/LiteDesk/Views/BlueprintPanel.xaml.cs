using System.Windows.Controls;

namespace LiteDesk.Views;

// "Blueprint" panel look (hairline border + four outward corner brackets)
// lives entirely in the implicit ControlTemplate in App.xaml. A plain
// ContentControl — not a UserControl — because a UserControl's own compiled
// NameScope gets conflated by the XAML compiler when this same type is
// nested inside itself (as it is in HomeView.xaml), producing a spurious
// MC3093 "name already registered in another scope" error. A templated
// Control's ControlTemplate content is its own proper NameScope boundary,
// so nesting works.
public class BlueprintPanel : ContentControl
{
}
