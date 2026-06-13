using System.Diagnostics;
using System.Windows.Input;
using CommunityToolkit.Mvvm.Input;
using H.NotifyIcon;
using H.NotifyIcon.Core;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using TinyClips.Core.Capture;
using TinyClips.Core.Models;
using TinyClips.Core.Services;

namespace TinyClips.App;

public partial class App : Application
{
    private static readonly FontFamily FluentIconFont = new("Segoe Fluent Icons");

    private TaskbarIcon? _taskbarIcon;
    private SettingsWindow? _settingsWindow;

    public static IServiceProvider Services { get; private set; } = null!;

    public App()
    {
        InitializeComponent();
        Services = new ServiceCollection()
            .AddTinyClipsCore()
            .BuildServiceProvider();

        ApplyTheme();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        CreateTrayIcon();
    }

    private void CreateTrayIcon()
    {
        if (_taskbarIcon is not null)
        {
            return;
        }

        var hotKeys = Services.GetRequiredService<IHotKeyService>();

        var menuFlyout = new MenuFlyout();

        menuFlyout.Items.Add(CreateMenuItem(
            text: "Screenshot",
            glyph: "\uE722",
            acceleratorText: hotKeys.GetBinding(CaptureType.Screenshot).DisplayString,
            command: new AsyncRelayCommand(CaptureScreenshotAsync)));

        menuFlyout.Items.Add(CreateMenuItem(
            text: "Record Video",
            glyph: "\uE714",
            acceleratorText: hotKeys.GetBinding(CaptureType.Video).DisplayString,
            command: new RelayCommand(() => Debug.WriteLine("TODO: Video capture not implemented yet."))));

        menuFlyout.Items.Add(CreateMenuItem(
            text: "Record GIF",
            glyph: "\uE786",
            acceleratorText: hotKeys.GetBinding(CaptureType.Gif).DisplayString,
            command: new RelayCommand(() => Debug.WriteLine("TODO: GIF capture not implemented yet."))));

        menuFlyout.Items.Add(new MenuFlyoutSeparator());

        menuFlyout.Items.Add(CreateMenuItem(
            text: "Settings",
            glyph: "\uE713",
            acceleratorText: null,
            command: new RelayCommand(OpenSettingsWindow)));

        menuFlyout.Items.Add(CreateMenuItem(
            text: "Exit",
            glyph: "\uE7E8",
            acceleratorText: null,
            command: new RelayCommand(ExitApplication)));

        _taskbarIcon = new TaskbarIcon
        {
            ToolTipText = "Tiny Clips",
            IconSource = new BitmapImage(new Uri("ms-appx:///Assets/TrayIcon.ico")),
            ContextFlyout = menuFlyout,
            // SecondWindow renders the real WinUI MenuFlyout (rounded corners, acrylic,
            // shadow, Fluent styling) instead of the legacy Win32 popup menu.
            ContextMenuMode = ContextMenuMode.SecondWindow,
            // Show the menu on either left- or right-click, with no delay on left-click.
            MenuActivation = PopupActivationMode.LeftOrRightClick,
            NoLeftClickDelay = true
        };

        _taskbarIcon.ForceCreate();
    }

    private static MenuFlyoutItem CreateMenuItem(string text, string glyph, string? acceleratorText, ICommand command)
    {
        var item = new MenuFlyoutItem
        {
            Text = text,
            Icon = new FontIcon
            {
                Glyph = glyph,
                FontFamily = FluentIconFont
            },
            Command = command
        };

        if (!string.IsNullOrEmpty(acceleratorText))
        {
            item.KeyboardAcceleratorTextOverride = acceleratorText;
        }

        return item;
    }

    private async Task CaptureScreenshotAsync()
    {
        try
        {
            // Give the tray menu a moment to dismiss so it isn't part of the capture.
            await Task.Delay(150);

            var screenshots = Services.GetRequiredService<IScreenshotService>();
            var path = await screenshots.CaptureFullScreenAsync();

            RevealInExplorer(path);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Screenshot capture failed: {ex}");
        }
    }

    private static void RevealInExplorer(string path)
    {
        try
        {
            Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"")
            {
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to reveal file in Explorer: {ex}");
        }
    }

    private void OpenSettingsWindow()
    {
        if (_settingsWindow is null)
        {
            _settingsWindow = new SettingsWindow();
            _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        }

        _settingsWindow.Activate();
    }

    private void ExitApplication()
    {
        _taskbarIcon?.Dispose();
        _taskbarIcon = null;
        _settingsWindow?.Close();
        Application.Current.Exit();
        // No persistent host window keeps the process alive, so force termination
        // to guarantee the user can always quit from the tray menu.
        Environment.Exit(0);
    }

    private void ApplyTheme()
    {
        var settings = Services.GetRequiredService<ISettingsService>();

        // RequestedTheme can only be set once, before any window is created. Leaving it
        // unset for AppTheme.Default lets the app follow the current system theme.
        switch (settings.Theme)
        {
            case AppTheme.Light:
                RequestedTheme = ApplicationTheme.Light;
                break;
            case AppTheme.Dark:
                RequestedTheme = ApplicationTheme.Dark;
                break;
        }
    }
}

