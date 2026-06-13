using System.Diagnostics;
using System.IO;
using System.Windows.Input;
using CommunityToolkit.Mvvm.Input;
using H.NotifyIcon;
using H.NotifyIcon.Core;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;
using TinyClips.Core.Capture;
using TinyClips.Core.Models;
using TinyClips.Core.Services;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using Windows.Storage.Streams;

namespace TinyClips.App;

public partial class App : Application
{
    private static readonly FontFamily FluentIconFont = new("Segoe Fluent Icons");

    // Segoe Fluent Icons glyphs.
    private const string GlyphScreenshot = "\uE722";
    private const string GlyphVideo = "\uE714";
    private const string GlyphGif = "\uE786";
    private const string GlyphStop = "\uE71A";
    private const string GlyphRegion = "\uE7A8";

    private TaskbarIcon? _taskbarIcon;
    private SettingsWindow? _settingsWindow;
    private MenuFlyoutItem? _videoItem;
    private MenuFlyoutItem? _gifItem;
    private GlobalHotKeyManager? _hotKeyManager;
    private DispatcherQueue? _dispatcher;

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
        _dispatcher = DispatcherQueue.GetForCurrentThread();

        RegisterNotifications();
        WireRecordingEvents();
        CreateTrayIcon();
        RegisterGlobalHotKeys();
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
            glyph: GlyphScreenshot,
            acceleratorText: hotKeys.GetBinding(CaptureType.Screenshot).DisplayString,
            command: new AsyncRelayCommand(CaptureScreenshotAsync)));

        menuFlyout.Items.Add(CreateMenuItem(
            text: "Capture Region",
            glyph: GlyphRegion,
            acceleratorText: null,
            command: new AsyncRelayCommand(CaptureRegionAsync)));

        _videoItem = CreateMenuItem(
            text: "Record Video",
            glyph: GlyphVideo,
            acceleratorText: hotKeys.GetBinding(CaptureType.Video).DisplayString,
            command: new AsyncRelayCommand(ToggleVideoAsync));
        menuFlyout.Items.Add(_videoItem);

        _gifItem = CreateMenuItem(
            text: "Record GIF",
            glyph: GlyphGif,
            acceleratorText: hotKeys.GetBinding(CaptureType.Gif).DisplayString,
            command: new AsyncRelayCommand(ToggleGifAsync));
        menuFlyout.Items.Add(_gifItem);

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

            var settings = Services.GetRequiredService<ICaptureSettings>();
            if (settings.ScreenshotCountdownEnabled && settings.ScreenshotCountdownDuration > 0)
            {
                await CountdownWindow.RunAsync(settings.ScreenshotCountdownDuration);
            }

            var screenshots = Services.GetRequiredService<IScreenshotService>();
            var path = await screenshots.CaptureFullScreenAsync();

            await CopyToClipboardAsync(path, CaptureType.Screenshot);
            RevealInExplorer(path);
            ShowSaveToast(path);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Screenshot capture failed: {ex}");
        }
    }

    private async Task CaptureRegionAsync()
    {
        try
        {
            // Let the tray menu dismiss before the overlay appears.
            await Task.Delay(150);

            var monitors = Services.GetRequiredService<IMonitorService>();
            var monitor = monitors.GetPrimaryMonitor();
            if (monitor is null)
            {
                return;
            }

            var region = await RegionSelectWindow.RunAsync(monitor);
            if (region is not { } selected)
            {
                return;
            }

            var screenshots = Services.GetRequiredService<IScreenshotService>();
            var path = await screenshots.CaptureRegionAsync(selected);

            await CopyToClipboardAsync(path, CaptureType.Screenshot);
            RevealInExplorer(path);
            ShowSaveToast(path);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Region capture failed: {ex}");
        }
    }

    private async Task ToggleVideoAsync()
    {
        var video = Services.GetRequiredService<IVideoRecordingService>();
        var gif = Services.GetRequiredService<IGifRecordingService>();

        try
        {
            if (video.IsRecording)
            {
                await video.StopAsync();
                return;
            }

            if (gif.IsRecording)
            {
                return;
            }

            // Let the tray menu dismiss before the recording starts.
            await Task.Delay(150);

            var settings = Services.GetRequiredService<ICaptureSettings>();
            if (settings.VideoCountdownEnabled && settings.VideoCountdownDuration > 0)
            {
                await CountdownWindow.RunAsync(settings.VideoCountdownDuration);
            }

            await video.StartAsync();
            UpdateRecordingState();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Video recording toggle failed: {ex}");
            UpdateRecordingState();
        }
    }

    private async Task ToggleGifAsync()
    {
        var video = Services.GetRequiredService<IVideoRecordingService>();
        var gif = Services.GetRequiredService<IGifRecordingService>();

        try
        {
            if (gif.IsRecording)
            {
                await gif.StopAsync();
                return;
            }

            if (video.IsRecording)
            {
                return;
            }

            await Task.Delay(150);

            var settings = Services.GetRequiredService<ICaptureSettings>();
            if (settings.GifCountdownEnabled && settings.GifCountdownDuration > 0)
            {
                await CountdownWindow.RunAsync(settings.GifCountdownDuration);
            }

            await gif.StartAsync();
            UpdateRecordingState();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"GIF recording toggle failed: {ex}");
            UpdateRecordingState();
        }
    }

    private void WireRecordingEvents()
    {
        var video = Services.GetRequiredService<IVideoRecordingService>();
        var gif = Services.GetRequiredService<IGifRecordingService>();
        video.RecordingCompleted += OnRecordingCompleted;
        gif.RecordingCompleted += OnRecordingCompleted;
    }

    private void OnRecordingCompleted(object? sender, string? path)
    {
        _dispatcher?.TryEnqueue(async () =>
        {
            UpdateRecordingState();
            if (!string.IsNullOrEmpty(path))
            {
                var type = Path.GetExtension(path).Equals(".gif", StringComparison.OrdinalIgnoreCase)
                    ? CaptureType.Gif
                    : CaptureType.Video;
                await CopyToClipboardAsync(path, type);
                RevealInExplorer(path);
                ShowSaveToast(path);
            }
        });
    }

    private void UpdateRecordingState()
    {
        var video = Services.GetRequiredService<IVideoRecordingService>();
        var gif = Services.GetRequiredService<IGifRecordingService>();

        if (_videoItem is not null)
        {
            var recording = video.IsRecording;
            _videoItem.Text = recording ? "Stop Recording" : "Record Video";
            if (_videoItem.Icon is FontIcon icon)
            {
                icon.Glyph = recording ? GlyphStop : GlyphVideo;
            }

            _videoItem.IsEnabled = !gif.IsRecording;
        }

        if (_gifItem is not null)
        {
            var recording = gif.IsRecording;
            _gifItem.Text = recording ? "Stop Recording" : "Record GIF";
            if (_gifItem.Icon is FontIcon icon)
            {
                icon.Glyph = recording ? GlyphStop : GlyphGif;
            }

            _gifItem.IsEnabled = !video.IsRecording;
        }
    }

    private static void RegisterNotifications()
    {
        try
        {
            AppNotificationManager.Default.Register();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Notification registration failed: {ex}");
        }
    }

    private async Task CopyToClipboardAsync(string path, CaptureType type)
    {
        try
        {
            var settings = Services.GetRequiredService<ICaptureSettings>();
            if (!settings.ShouldCopyToClipboard(type))
            {
                return;
            }

            var file = await StorageFile.GetFileFromPathAsync(path);
            var package = new DataPackage { RequestedOperation = DataPackageOperation.Copy };
            package.SetStorageItems(new[] { file });

            // For still images, also place the bitmap so it can be pasted directly into editors.
            if (type == CaptureType.Screenshot)
            {
                package.SetBitmap(RandomAccessStreamReference.CreateFromFile(file));
            }

            Clipboard.SetContent(package);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Clipboard copy failed: {ex}");
        }
    }

    private void ShowSaveToast(string path)
    {
        try
        {
            var settings = Services.GetRequiredService<ICaptureSettings>();
            if (!settings.ShowSaveNotifications)
            {
                return;
            }

            var notification = new AppNotificationBuilder()
                .AddText("Saved to Tiny Clips")
                .AddText(Path.GetFileName(path))
                .BuildNotification();

            AppNotificationManager.Default.Show(notification);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to show save notification: {ex}");
        }
    }

    private void RegisterGlobalHotKeys()
    {
        if (_dispatcher is null)
        {
            return;
        }

        try
        {
            var hotKeys = Services.GetRequiredService<IHotKeyService>();
            _hotKeyManager = new GlobalHotKeyManager(_dispatcher);

            var screenshot = hotKeys.GetBinding(CaptureType.Screenshot);
            _hotKeyManager.Add(screenshot.ModifiersValue, screenshot.VirtualKey, () => _ = CaptureScreenshotAsync());

            var videoBinding = hotKeys.GetBinding(CaptureType.Video);
            _hotKeyManager.Add(videoBinding.ModifiersValue, videoBinding.VirtualKey, () => _ = ToggleVideoAsync());

            var gifBinding = hotKeys.GetBinding(CaptureType.Gif);
            _hotKeyManager.Add(gifBinding.ModifiersValue, gifBinding.VirtualKey, () => _ = ToggleGifAsync());

            _hotKeyManager.Start();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Global hotkey registration failed: {ex}");
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
        try
        {
            var video = Services.GetRequiredService<IVideoRecordingService>();
            if (video.IsRecording)
            {
                video.StopAsync().GetAwaiter().GetResult();
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to stop recording on exit: {ex}");
        }

        _hotKeyManager?.Dispose();
        _hotKeyManager = null;
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
