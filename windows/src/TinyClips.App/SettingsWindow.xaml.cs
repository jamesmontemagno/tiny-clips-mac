using Microsoft.UI.Xaml;

namespace TinyClips.App;

public sealed partial class SettingsWindow : Window
{
    public SettingsWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
    }
}
