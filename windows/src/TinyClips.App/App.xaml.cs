using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
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
    private GuideWindow? _guideWindow;
    private OnboardingWindow? _onboardingWindow;
    private ScreenshotEditorWindow? _editorWindow;
    private Window? _trimmerWindow;
    private string? _lastTrimmerSourcePath;
    private RecordingIndicatorWindow? _recordingIndicator;
    private RegionIndicatorWindow? _recordingRegionIndicator;
    private DispatcherTimer? _recordingTimer;
    private DateTime _recordingStartedUtc;
    private MenuFlyoutItem? _videoItem;
    private MenuFlyoutItem? _gifItem;
    private GlobalHotKeyManager? _hotKeyManager;
    private DispatcherQueue? _dispatcher;
    private bool _isExiting;

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
        ShowOnboardingIfNeeded();
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
            text: "Guide",
            glyph: "\uE897",
            acceleratorText: null,
            command: new RelayCommand(OpenGuideWindow)));

        menuFlyout.Items.Add(CreateMenuItem(
            text: "Exit",
            glyph: "\uE7E8",
            acceleratorText: null,
            command: new RelayCommand(() => _ = ExitApplicationAsync())));

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

    private Task CaptureScreenshotAsync() => BeginCaptureAsync(CaptureType.Screenshot);

    /// <summary>
    /// Shows the capture picker bar (Region / Screen / Window + countdown), resolves the
    /// chosen target, runs the countdown, then performs the capture or starts recording.
    /// </summary>
    private async Task BeginCaptureAsync(CaptureType type, bool abortIfRecording = false)
    {
        try
        {
            // Give the tray menu a moment to dismiss so it isn't part of the capture.
            await Task.Delay(150);

            // For an auto-reopened picker, bail out if a recording started during the delay.
            if (abortIfRecording && (_isExiting || IsAnyRecordingActive()))
            {
                return;
            }

            var settings = Services.GetRequiredService<ICaptureSettings>();
            var (cdEnabled, cdDuration) = GetCountdown(settings, type);

            var pick = await CapturePickerWindow.RunAsync(type, cdEnabled, cdDuration);
            if (pick is null)
            {
                return;
            }

            var resolved = await ResolveTargetAsync(pick.Mode);
            if (resolved is not { } selection)
            {
                return;
            }

            RegionIndicatorWindow? regionIndicator = null;
            if (pick.CountdownEnabled && pick.CountdownDuration > 0)
            {
                try
                {
                    if (selection.Region is { } region)
                    {
                        regionIndicator = new RegionIndicatorWindow();
                        regionIndicator.Show(ToVirtualDesktopRegion(selection.Target, region));
                    }

                    await CountdownWindow.RunAsync(pick.CountdownDuration);
                }
                finally
                {
                    regionIndicator?.ClosePanel();
                }
            }

            switch (type)
            {
                case CaptureType.Screenshot:
                    var screenshots = Services.GetRequiredService<IScreenshotService>();
                    var path = await screenshots.CaptureTargetAsync(selection.Target, selection.Region);
                    await CopyToClipboardAsync(path, CaptureType.Screenshot);
                    if (settings.ShowScreenshotEditor)
                    {
                        OpenScreenshotEditor(path);
                    }
                    else
                    {
                        RevealInExplorer(path);
                        ShowSaveToast(path);
                        ReopenPickerAfterCaptureIfNeeded(CaptureType.Screenshot);
                    }
                    break;

                case CaptureType.Video:
                    await Services.GetRequiredService<IVideoRecordingService>().StartAsync(selection.Target, selection.Region);
                    ShowRecordingRegionIndicator(selection);
                    UpdateRecordingState();
                    ShowRecordingIndicator(CaptureType.Video);
                    break;

                case CaptureType.Gif:
                    await Services.GetRequiredService<IGifRecordingService>().StartAsync(selection.Target, selection.Region);
                    ShowRecordingRegionIndicator(selection);
                    UpdateRecordingState();
                    ShowRecordingIndicator(CaptureType.Gif);
                    break;
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Capture failed: {ex}");
            UpdateRecordingState();
            CloseRecordingRegionIndicator();
            HideRecordingIndicatorIfNotRecording();
        }
    }

    private async Task<TargetSelection?> ResolveTargetAsync(CapturePickerMode mode)
    {
        var monitors = Services.GetRequiredService<IMonitorService>();

        switch (mode)
        {
            case CapturePickerMode.Region:
            {
                var monitor = monitors.GetPrimaryMonitor();
                if (monitor is null)
                {
                    return null;
                }

                var region = await RegionSelectWindow.RunAsync(monitor);
                return region is { } r
                    ? new TargetSelection(CaptureTarget.Monitor(monitor.HMonitor), r)
                    : null;
            }

            case CapturePickerMode.Screen:
            {
                var all = monitors.GetMonitors();
                var chosen = all.Count <= 1
                    ? all.FirstOrDefault() ?? monitors.GetPrimaryMonitor()
                    : await ScreenPickerWindow.RunAsync(all);
                return chosen is { } monitor
                    ? new TargetSelection(CaptureTarget.Monitor(monitor.HMonitor), null)
                    : null;
            }

            case CapturePickerMode.Window:
            {
                var hwnd = await WindowPickerWindow.RunAsync();
                return hwnd is { } h
                    ? new TargetSelection(CaptureTarget.Window(h), null)
                    : null;
            }

            default:
                return null;
        }
    }

    private static (bool Enabled, int Duration) GetCountdown(ICaptureSettings settings, CaptureType type) => type switch
    {
        CaptureType.Video => (settings.VideoCountdownEnabled, settings.VideoCountdownDuration),
        CaptureType.Gif => (settings.GifCountdownEnabled, settings.GifCountdownDuration),
        _ => (settings.ScreenshotCountdownEnabled, settings.ScreenshotCountdownDuration),
    };

    private static PixelRect ToVirtualDesktopRegion(CaptureTarget target, PixelRect region)
    {
        if (target.HMonitor == 0)
        {
            return region;
        }

        var monitors = Services.GetRequiredService<IMonitorService>().GetMonitors();
        var monitor = monitors.FirstOrDefault(m => m.HMonitor == target.HMonitor);
        return monitor is null
            ? region
            : region with { X = monitor.X + region.X, Y = monitor.Y + region.Y };
    }

    private readonly record struct TargetSelection(CaptureTarget Target, PixelRect? Region);

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
                await StopActiveRecordingAsync();
                return;
            }

            if (gif.IsRecording)
            {
                return;
            }

            await BeginCaptureAsync(CaptureType.Video);
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
                await StopActiveRecordingAsync();
                return;
            }

            if (video.IsRecording)
            {
                return;
            }

            await BeginCaptureAsync(CaptureType.Gif);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"GIF recording toggle failed: {ex}");
            UpdateRecordingState();
            HideRecordingIndicatorIfNotRecording();
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
            HideRecordingIndicator();
            CloseRecordingRegionIndicator();
            if (_isExiting)
            {
                return;
            }

            if (string.IsNullOrEmpty(path))
            {
                return;
            }

            var type = Path.GetExtension(path).Equals(".gif", StringComparison.OrdinalIgnoreCase)
                ? CaptureType.Gif
                : CaptureType.Video;

            var settings = Services.GetRequiredService<ICaptureSettings>();
            var showTrimmer = type == CaptureType.Gif ? settings.ShowGifTrimmer : settings.ShowTrimmer;
            if (showTrimmer)
            {
                OpenTrimmer(path, type);
            }
            else
            {
                await FinalizeClipAsync(path, type);
                ReopenPickerAfterCaptureIfNeeded(type);
            }
        });
    }

    private async Task StopActiveRecordingAsync()
    {
        try
        {
            var video = Services.GetRequiredService<IVideoRecordingService>();
            var gif = Services.GetRequiredService<IGifRecordingService>();

            if (video.IsRecording)
            {
                await video.StopAsync();
            }
            else if (gif.IsRecording)
            {
                await gif.StopAsync();
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to stop active recording: {ex}");
        }
        finally
        {
            UpdateRecordingState();
            CloseRecordingRegionIndicatorIfNotRecording();
            HideRecordingIndicatorIfNotRecording();
        }
    }

    private void ShowRecordingRegionIndicator(TargetSelection selection)
    {
        if (selection.Region is not { } region)
        {
            return;
        }

        CloseRecordingRegionIndicator();
        var indicator = new RegionIndicatorWindow();
        _recordingRegionIndicator = indicator;
        indicator.Closed += (_, _) =>
        {
            if (ReferenceEquals(_recordingRegionIndicator, indicator))
            {
                _recordingRegionIndicator = null;
            }
        };
        indicator.Show(ToVirtualDesktopRegion(selection.Target, region));
    }

    private void CloseRecordingRegionIndicatorIfNotRecording()
    {
        var video = Services.GetRequiredService<IVideoRecordingService>();
        var gif = Services.GetRequiredService<IGifRecordingService>();

        if (!video.IsRecording && !gif.IsRecording)
        {
            CloseRecordingRegionIndicator();
        }
    }

    private void CloseRecordingRegionIndicator()
    {
        var window = _recordingRegionIndicator;
        _recordingRegionIndicator = null;
        window?.ClosePanel();
    }

    private void ShowRecordingIndicator(CaptureType type)
    {
        HideRecordingIndicator();

        _recordingStartedUtc = DateTime.UtcNow;

        var hotKeys = Services.GetRequiredService<IHotKeyService>();
        var window = new RecordingIndicatorWindow(hotKeys.StopRecordingDisplayString);
        window.StopRequested = () => _ = StopActiveRecordingAsync();
        window.Closed += (_, _) =>
        {
            if (ReferenceEquals(_recordingIndicator, window))
            {
                StopRecordingTimer();
                _recordingIndicator = null;
            }
        };

        _recordingIndicator = window;
        window.UpdateElapsed(TimeSpan.Zero);
        window.ShowNear();

        _recordingTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _recordingTimer.Tick += OnRecordingTimerTick;
        _recordingTimer.Start();
    }

    private void OnRecordingTimerTick(object? sender, object e)
    {
        _recordingIndicator?.UpdateElapsed(DateTime.UtcNow - _recordingStartedUtc);
    }

    private void HideRecordingIndicatorIfNotRecording()
    {
        var video = Services.GetRequiredService<IVideoRecordingService>();
        var gif = Services.GetRequiredService<IGifRecordingService>();

        if (!video.IsRecording && !gif.IsRecording)
        {
            HideRecordingIndicator();
        }
    }

    private void HideRecordingIndicator()
    {
        StopRecordingTimer();

        var window = _recordingIndicator;
        _recordingIndicator = null;
        window?.ClosePanel();
    }

    private void StopRecordingTimer()
    {
        if (_recordingTimer is null)
        {
            return;
        }

        _recordingTimer.Stop();
        _recordingTimer.Tick -= OnRecordingTimerTick;
        _recordingTimer = null;
    }

    private async Task FinalizeClipAsync(string path, CaptureType type)
    {
        await CopyToClipboardAsync(path, type);
        RevealInExplorer(path);
        ShowSaveToast(path);
    }

    private void OpenTrimmer(string path, CaptureType type)
    {
        _trimmerWindow?.Close();
        _lastTrimmerSourcePath = path;

        if (type == CaptureType.Gif)
        {
            var gifTrimmer = new GifTrimmerWindow(path);
            gifTrimmer.Completed += OnTrimmerCompleted;
            _trimmerWindow = gifTrimmer;
        }
        else
        {
            var videoTrimmer = new VideoTrimmerWindow(path);
            videoTrimmer.Completed += OnTrimmerCompleted;
            _trimmerWindow = videoTrimmer;
        }

        _trimmerWindow.Closed += (_, _) => _trimmerWindow = null;
        ActivateWindowToForeground(_trimmerWindow);
    }

    private void OnTrimmerCompleted(object? sender, string? trimmedPath)
    {
        _dispatcher?.TryEnqueue(async () =>
        {
            if (_isExiting)
            {
                return;
            }

            var path = trimmedPath ?? _lastTrimmerSourcePath;
            if (string.IsNullOrEmpty(path))
            {
                return;
            }

            var type = Path.GetExtension(path).Equals(".gif", StringComparison.OrdinalIgnoreCase)
                ? CaptureType.Gif
                : CaptureType.Video;
            await FinalizeClipAsync(path, type);
            ReopenPickerAfterCaptureIfNeeded(type);
        });
    }

    private void UpdateRecordingState()
    {
        var video = Services.GetRequiredService<IVideoRecordingService>();
        var gif = Services.GetRequiredService<IGifRecordingService>();
        var hotKeys = Services.GetRequiredService<IHotKeyService>();

        if (_videoItem is not null)
        {
            var recording = video.IsRecording;
            _videoItem.Text = recording ? "Stop Recording" : "Record Video";
            _videoItem.KeyboardAcceleratorTextOverride = recording
                ? hotKeys.StopRecordingDisplayString
                : hotKeys.GetBinding(CaptureType.Video).DisplayString;
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
            _gifItem.KeyboardAcceleratorTextOverride = recording
                ? hotKeys.StopRecordingDisplayString
                : hotKeys.GetBinding(CaptureType.Gif).DisplayString;
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

            var stopBinding = hotKeys.GetStopBinding();
            _hotKeyManager.Add(stopBinding.ModifiersValue, stopBinding.VirtualKey, () => _ = StopActiveRecordingAsync());

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

        ActivateWindowToForeground(_settingsWindow);
    }

    private void OpenGuideWindow()
    {
        if (_guideWindow is null)
        {
            _guideWindow = new GuideWindow();
            _guideWindow.Closed += (_, _) => _guideWindow = null;
        }

        ActivateWindowToForeground(_guideWindow);
    }

    private void OpenScreenshotEditor(string path)
    {
        var oldWindow = _editorWindow;
        _editorWindow = null;
        oldWindow?.Close();

        var window = new ScreenshotEditorWindow(path);
        _editorWindow = window;
        window.Closed += (_, _) =>
        {
            if (ReferenceEquals(_editorWindow, window))
            {
                _editorWindow = null;
                ReopenPickerAfterCaptureIfNeeded(CaptureType.Screenshot);
            }
        };
        ActivateWindowToForeground(window);
    }

    private void ShowOnboardingIfNeeded()
    {
        var settings = Services.GetRequiredService<ICaptureSettings>();
        if (settings.HasCompletedOnboarding)
        {
            return;
        }

        _onboardingWindow = new OnboardingWindow();
        _onboardingWindow.Closed += (_, _) => _onboardingWindow = null;
        ActivateWindowToForeground(_onboardingWindow);
    }

    private async Task ExitApplicationAsync()
    {
        if (_isExiting)
        {
            return;
        }

        _isExiting = true;
        try
        {
            var video = Services.GetRequiredService<IVideoRecordingService>();
            var gif = Services.GetRequiredService<IGifRecordingService>();
            if (video.IsRecording)
            {
                await video.StopAsync();
            }

            if (gif.IsRecording)
            {
                await gif.StopAsync();
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to stop recording on exit: {ex}");
        }

        HideRecordingIndicator();
        CloseRecordingRegionIndicator();
        _hotKeyManager?.Dispose();
        _hotKeyManager = null;
        _taskbarIcon?.Dispose();
        _taskbarIcon = null;
        _settingsWindow?.Close();
        _guideWindow?.Close();
        _onboardingWindow?.Close();
        _editorWindow?.Close();
        _trimmerWindow?.Close();
        Application.Current.Exit();
        // No persistent host window keeps the process alive, so force termination
        // to guarantee the user can always quit from the tray menu.
        Environment.Exit(0);
    }

    private void ReopenPickerAfterCaptureIfNeeded(CaptureType type)
    {
        var settings = Services.GetRequiredService<ICaptureSettings>();
        if (!settings.ReopenPickerAfterCapture || _isExiting || IsAnyRecordingActive())
        {
            return;
        }

        _ = ReopenPickerAfterCaptureAsync(type);
    }

    private async Task ReopenPickerAfterCaptureAsync(CaptureType type)
    {
        await Task.Delay(150);
        if (_isExiting || IsAnyRecordingActive())
        {
            return;
        }

        await BeginCaptureAsync(type, abortIfRecording: true);
    }

    private static bool IsAnyRecordingActive()
    {
        var video = Services.GetRequiredService<IVideoRecordingService>();
         var gif = Services.GetRequiredService<IGifRecordingService>();
        return video.IsRecording || gif.IsRecording;
    }

    private void ActivateWindowToForeground(Window window)
    {
        try
        {
            window.Activate();
            BringWindowToForeground(window);
            _ = ActivateWindowToForegroundDelayedAsync(window);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to activate window: {ex}");
        }
    }

    private async Task ActivateWindowToForegroundDelayedAsync(Window window)
    {
        await Task.Delay(100);
        if (_isExiting)
        {
            return;
        }

        try
        {
            window.Activate();
            BringWindowToForeground(window);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to reactivate window: {ex}");
        }
    }

    private static void BringWindowToForeground(Window window)
    {
        try
        {
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
            if (hwnd != IntPtr.Zero)
            {
                SetForegroundWindow(hwnd);
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to foreground window: {ex}");
        }
    }

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

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
