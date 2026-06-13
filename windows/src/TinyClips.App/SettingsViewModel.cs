using CommunityToolkit.Mvvm.ComponentModel;
using TinyClips.Core.Models;
using TinyClips.Core.Services;

namespace TinyClips.App;

/// <summary>
/// View model for the Settings window. Each property mirrors a value on
/// <see cref="ICaptureSettings"/>; the generated change handlers persist edits
/// immediately so there is no explicit Save step.
/// </summary>
/// <remarks>
/// Field-based <c>[ObservableProperty]</c> is used intentionally. The MVVM Toolkit
/// source generator does not emit implementations for partial-property syntax in this
/// project configuration, and this view model is only consumed through compiled
/// <c>x:Bind</c> in C#; it never crosses the WinRT ABI, so the AOT-marshalling hint
/// (MVVMTK0045) does not apply.
/// </remarks>
public sealed partial class SettingsViewModel : ObservableObject
{
    private readonly ICaptureSettings _settings;
    private readonly IHotKeyService _hotKeys;
    private readonly IEntitlementService _entitlement;
    private bool _loading;

    /// <summary>Raised when the selected theme changes so the window can re-apply it live.</summary>
    public event Action? ThemeChanged;

    public SettingsViewModel(ICaptureSettings settings, IHotKeyService hotKeys, IEntitlementService entitlement)
    {
        _settings = settings;
        _hotKeys = hotKeys;
        _entitlement = entitlement;
        Load();
    }

    /// <summary>True when Pro features are unlocked. Pro-only controls bind their IsEnabled to this.</summary>
    public bool IsPro => _entitlement.IsProUnlocked;

    /// <summary>Inverse of <see cref="IsPro"/>, used to show the upsell note for locked features.</summary>
    public bool IsNotPro => !_entitlement.IsProUnlocked;

    public string ProStatusText => _entitlement.IsProUnlocked
        ? "Tiny Clips Pro is unlocked. Thank you for your support!"
        : "Mouse-click visuals and branding overlays are Pro features. Pro will be available as a purchase in the Microsoft Store build.";

    // General
    [ObservableProperty]
    private int _themeIndex;

    [ObservableProperty]
    private string _saveDirectory = string.Empty;

    [ObservableProperty]
    private string _fileNameTemplate = string.Empty;

    [ObservableProperty]
    private bool _showInExplorer;

    [ObservableProperty]
    private bool _showSaveNotifications;

    [ObservableProperty]
    private bool _copyScreenshotToClipboard;

    // Screenshot
    [ObservableProperty]
    private int _screenshotFormatIndex;

    [ObservableProperty]
    private double _screenshotScale;

    [ObservableProperty]
    private double _jpegQuality;

    [ObservableProperty]
    private bool _screenshotCountdownEnabled;

    [ObservableProperty]
    private double _screenshotCountdownDuration;

    // Video
    [ObservableProperty]
    private double _videoFrameRate;

    [ObservableProperty]
    private bool _recordAudio;

    [ObservableProperty]
    private bool _recordMicrophone;

    [ObservableProperty]
    private double _videoRecordingTimeLimitMinutes;

    [ObservableProperty]
    private bool _videoCountdownEnabled;

    [ObservableProperty]
    private double _videoCountdownDuration;

    // GIF
    [ObservableProperty]
    private double _gifFrameRate;

    [ObservableProperty]
    private double _gifMaxWidth;

    [ObservableProperty]
    private bool _gifCountdownEnabled;

    [ObservableProperty]
    private double _gifCountdownDuration;

    // Mouse clicks (Pro)
    [ObservableProperty]
    private bool _showMouseClicksInVideo;

    [ObservableProperty]
    private bool _showMouseClicksInGif;

    [ObservableProperty]
    private bool _gifMouseClicksUseVideoSettings;

    [ObservableProperty]
    private double _videoMouseClickSize;

    [ObservableProperty]
    private double _videoMouseClickOpacity;

    // Branding (Pro)
    [ObservableProperty]
    private bool _showBrandingOverlay;
    public string ScreenshotHotKeyDisplay => _hotKeys.GetBinding(CaptureType.Screenshot).DisplayString;

    public string VideoHotKeyDisplay => _hotKeys.GetBinding(CaptureType.Video).DisplayString;

    public string GifHotKeyDisplay => _hotKeys.GetBinding(CaptureType.Gif).DisplayString;

    private void Load()
    {
        _loading = true;
        try
        {
            ThemeIndex = _settings.Theme switch
            {
                AppTheme.Light => 1,
                AppTheme.Dark => 2,
                _ => 0,
            };
            SaveDirectory = _settings.SaveDirectory;
            FileNameTemplate = _settings.FileNameTemplate;
            ShowInExplorer = _settings.ShowInExplorer;
            ShowSaveNotifications = _settings.ShowSaveNotifications;
            CopyScreenshotToClipboard = _settings.CopyScreenshotToClipboard;

            ScreenshotFormatIndex = _settings.ImageFormat == ImageFormat.Png ? 0 : 1;
            ScreenshotScale = _settings.ScreenshotScale;
            JpegQuality = _settings.JpegQuality;
            ScreenshotCountdownEnabled = _settings.ScreenshotCountdownEnabled;
            ScreenshotCountdownDuration = _settings.ScreenshotCountdownDuration;

            VideoFrameRate = _settings.VideoFrameRate;
            RecordAudio = _settings.RecordAudio;
            RecordMicrophone = _settings.RecordMicrophone;
            VideoRecordingTimeLimitMinutes = _settings.VideoRecordingTimeLimitMinutes;
            VideoCountdownEnabled = _settings.VideoCountdownEnabled;
            VideoCountdownDuration = _settings.VideoCountdownDuration;

            GifFrameRate = _settings.GifFrameRate;
            GifMaxWidth = _settings.GifMaxWidth;
            GifCountdownEnabled = _settings.GifCountdownEnabled;
            GifCountdownDuration = _settings.GifCountdownDuration;

            ShowMouseClicksInVideo = _settings.ShowMouseClickVisualsInVideo;
            ShowMouseClicksInGif = _settings.ShowMouseClickVisualsInGif;
            GifMouseClicksUseVideoSettings = _settings.GifMouseClicksUseVideoSettings;
            VideoMouseClickSize = _settings.VideoMouseClickSize;
            VideoMouseClickOpacity = _settings.VideoMouseClickOpacity;
            ShowBrandingOverlay = _settings.ShowBrandingOverlay;
        }
        finally
        {
            _loading = false;
        }
    }

    partial void OnThemeIndexChanged(int value)
    {
        if (_loading)
        {
            return;
        }

        _settings.Theme = value switch
        {
            1 => AppTheme.Light,
            2 => AppTheme.Dark,
            _ => AppTheme.Default,
        };
        ThemeChanged?.Invoke();
    }

    partial void OnSaveDirectoryChanged(string value) => Persist(() => _settings.SaveDirectory = value);

    partial void OnFileNameTemplateChanged(string value) => Persist(() => _settings.FileNameTemplate = value);

    partial void OnShowInExplorerChanged(bool value) => Persist(() => _settings.ShowInExplorer = value);

    partial void OnShowSaveNotificationsChanged(bool value) => Persist(() => _settings.ShowSaveNotifications = value);

    partial void OnCopyScreenshotToClipboardChanged(bool value) => Persist(() => _settings.CopyScreenshotToClipboard = value);

    partial void OnScreenshotFormatIndexChanged(int value) =>
        Persist(() => _settings.ImageFormat = value == 0 ? ImageFormat.Png : ImageFormat.Jpeg);

    partial void OnScreenshotScaleChanged(double value) => Persist(() => _settings.ScreenshotScale = (int)Math.Round(value));

    partial void OnJpegQualityChanged(double value) => Persist(() => _settings.JpegQuality = value);

    partial void OnScreenshotCountdownEnabledChanged(bool value) => Persist(() => _settings.ScreenshotCountdownEnabled = value);

    partial void OnScreenshotCountdownDurationChanged(double value) =>
        Persist(() => _settings.ScreenshotCountdownDuration = (int)Math.Round(value));

    partial void OnVideoFrameRateChanged(double value) => Persist(() => _settings.VideoFrameRate = (int)Math.Round(value));

    partial void OnRecordAudioChanged(bool value) => Persist(() => _settings.RecordAudio = value);

    partial void OnRecordMicrophoneChanged(bool value) => Persist(() => _settings.RecordMicrophone = value);

    partial void OnVideoRecordingTimeLimitMinutesChanged(double value) =>
        Persist(() => _settings.VideoRecordingTimeLimitMinutes = (int)Math.Round(value));

    partial void OnVideoCountdownEnabledChanged(bool value) => Persist(() => _settings.VideoCountdownEnabled = value);

    partial void OnVideoCountdownDurationChanged(double value) =>
        Persist(() => _settings.VideoCountdownDuration = (int)Math.Round(value));

    partial void OnGifFrameRateChanged(double value) => Persist(() => _settings.GifFrameRate = value);

    partial void OnGifMaxWidthChanged(double value) => Persist(() => _settings.GifMaxWidth = (int)Math.Round(value));

    partial void OnGifCountdownEnabledChanged(bool value) => Persist(() => _settings.GifCountdownEnabled = value);

    partial void OnGifCountdownDurationChanged(double value) =>
        Persist(() => _settings.GifCountdownDuration = (int)Math.Round(value));

    partial void OnShowMouseClicksInVideoChanged(bool value) => Persist(() => _settings.ShowMouseClickVisualsInVideo = value);

    partial void OnShowMouseClicksInGifChanged(bool value) => Persist(() => _settings.ShowMouseClickVisualsInGif = value);

    partial void OnGifMouseClicksUseVideoSettingsChanged(bool value) => Persist(() => _settings.GifMouseClicksUseVideoSettings = value);

    partial void OnVideoMouseClickSizeChanged(double value) => Persist(() => _settings.VideoMouseClickSize = value);

    partial void OnVideoMouseClickOpacityChanged(double value) => Persist(() => _settings.VideoMouseClickOpacity = value);

    partial void OnShowBrandingOverlayChanged(bool value) => Persist(() => _settings.ShowBrandingOverlay = value);

    private void Persist(Action apply)
    {
        if (_loading)
        {
            return;
        }

        apply();
    }
}
