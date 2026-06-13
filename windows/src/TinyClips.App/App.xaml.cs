using System.Diagnostics;
using CommunityToolkit.Mvvm.Input;
using H.NotifyIcon;
using H.NotifyIcon.Core;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
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

        // In H.NotifyIcon's default PopupMenu mode the flyout is rendered as a native
        // Win32 menu that invokes each item's Command (not the XAML Click event), so
        // every item must supply an ICommand to be interactive.
        var screenshotItem = new MenuFlyoutItem
        {
            Text = "Screenshot",
            Command = new RelayCommand(() => Debug.WriteLine("TODO: Screenshot capture not implemented yet."))
        };
        menuFlyout.Items.Add(screenshotItem);

        var videoItem = new MenuFlyoutItem
        {
            Text = "Record Video",
            Command = new RelayCommand(() => Debug.WriteLine("TODO: Video capture not implemented yet."))
        };
        menuFlyout.Items.Add(videoItem);

        var gifItem = new MenuFlyoutItem
        {
            Text = "Record GIF",
            Command = new RelayCommand(() => Debug.WriteLine("TODO: GIF capture not implemented yet."))
        };
        menuFlyout.Items.Add(gifItem);

        menuFlyout.Items.Add(new MenuFlyoutSeparator());

        var settingsItem = new MenuFlyoutItem
        {
            Text = "Settings",
            Command = new RelayCommand(OpenSettingsWindow)
        };
        menuFlyout.Items.Add(settingsItem);

        var exitItem = new MenuFlyoutItem
        {
            Text = "Exit",
            Command = new RelayCommand(ExitApplication)
        };
        menuFlyout.Items.Add(exitItem);

        _taskbarIcon = new TaskbarIcon
        {
            ToolTipText = "Tiny Clips",
            IconSource = new BitmapImage(new Uri("ms-appx:///Assets/TrayIcon.ico")),
            ContextFlyout = menuFlyout,
            // Show the menu on either left- or right-click, with no delay on left-click.
            MenuActivation = PopupActivationMode.LeftOrRightClick,
            NoLeftClickDelay = true
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
        _settingsWindow?.Close();
        Application.Current.Exit();
        // No persistent host window keeps the process alive, so force termination
        // to guarantee the user can always quit from the tray menu.
        Environment.Exit(0);
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

