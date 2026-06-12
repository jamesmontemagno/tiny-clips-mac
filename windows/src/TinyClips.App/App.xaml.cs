using System.Diagnostics;
using H.NotifyIcon;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using TinyClips.Core.Models;
using TinyClips.Core.Services;

namespace TinyClips.App;

public partial class App : Application
{
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

        var menuFlyout = new MenuFlyout();

        var screenshotItem = new MenuFlyoutItem { Text = "Screenshot" };
        screenshotItem.Click += (_, _) => Debug.WriteLine("TODO: Screenshot capture not implemented yet.");
        menuFlyout.Items.Add(screenshotItem);

        var videoItem = new MenuFlyoutItem { Text = "Record Video" };
        videoItem.Click += (_, _) => Debug.WriteLine("TODO: Video capture not implemented yet.");
        menuFlyout.Items.Add(videoItem);

        var gifItem = new MenuFlyoutItem { Text = "Record GIF" };
        gifItem.Click += (_, _) => Debug.WriteLine("TODO: GIF capture not implemented yet.");
        menuFlyout.Items.Add(gifItem);

        menuFlyout.Items.Add(new MenuFlyoutSeparator());

        var settingsItem = new MenuFlyoutItem { Text = "Settings" };
        settingsItem.Click += (_, _) => OpenSettingsWindow();
        menuFlyout.Items.Add(settingsItem);

        var exitItem = new MenuFlyoutItem { Text = "Exit" };
        exitItem.Click += (_, _) => ExitApplication();
        menuFlyout.Items.Add(exitItem);

        _taskbarIcon = new TaskbarIcon
        {
            ToolTipText = "Tiny Clips",
            IconSource = new GeneratedIconSource
            {
                Text = "TC",
                FontSize = 24,
                Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.CornflowerBlue),
                Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.White)
            },
            ContextFlyout = menuFlyout
        };

        _taskbarIcon.ForceCreate();
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
        Application.Current.Exit();
    }

    private void ApplyTheme()
    {
        var settings = Services.GetRequiredService<ISettingsService>();
        RequestedTheme = settings.Theme switch
        {
            AppTheme.Light => ApplicationTheme.Light,
            AppTheme.Dark => ApplicationTheme.Dark,
            _ => ApplicationTheme.Light
        };
    }
}

