using TinyClips.Core.Models;

namespace TinyClips.Core.Services;

public sealed class CaptureSettings : ICaptureSettings
{
    private readonly ISettingsService _settings;

    public CaptureSettings(ISettingsService settings)
    {
        _settings = settings;
    }

    public string SaveDirectory
    {
        get => _settings.SaveDirectory;
        set => _settings.SaveDirectory = value;
    }

    public AppTheme Theme
    {
        get => _settings.Theme;
        set => _settings.Theme = value;
    }

    public bool CopyScreenshotToClipboard
    {
        get => _settings.Get("copyScreenshotToClipboard", true);
        set => _settings.Set("copyScreenshotToClipboard", value);
    }

    public bool CopyVideoToClipboard
    {
        get => _settings.Get("copyVideoToClipboard", false);
        set => _settings.Set("copyVideoToClipboard", value);
    }

    public bool CopyGifToClipboard
    {
        get => _settings.Get("copyGifToClipboard", false);
        set => _settings.Set("copyGifToClipboard", value);
    }

    public bool ShowInExplorer
    {
        get => _settings.Get("showInExplorer", false);
        set => _settings.Set("showInExplorer", value);
    }

    public bool ShowSaveNotifications
    {
        get => _settings.Get("showSaveNotifications", false);
        set => _settings.Set("showSaveNotifications", value);
    }

    public string FileNameTemplate
    {
        get => _settings.Get("fileNameTemplate", "TinyClips {date} at {time}");
        set => _settings.Set("fileNameTemplate", value);
    }

    public bool UploadcareEnabled
    {
        get => _settings.Get("uploadcareEnabled", false);
        set => _settings.Set("uploadcareEnabled", value);
    }

    public bool ClipsManagerShowAutoTags
    {
        get => _settings.Get("clipsManagerShowAutoTags", true);
        set => _settings.Set("clipsManagerShowAutoTags", value);
    }

    public bool ClipsManagerShowNotesPreview
    {
        get => _settings.Get("clipsManagerShowNotesPreview", true);
        set => _settings.Set("clipsManagerShowNotesPreview", value);
    }

    public bool ClipsManagerShowQuickActions
    {
        get => _settings.Get("clipsManagerShowQuickActions", true);
        set => _settings.Set("clipsManagerShowQuickActions", value);
    }

    public bool ClipsManagerShowUploadStatus
    {
        get => _settings.Get("clipsManagerShowUploadStatus", true);
        set => _settings.Set("clipsManagerShowUploadStatus", value);
    }

    public bool ClipsManagerConfirmDelete
    {
        get => _settings.Get("clipsManagerConfirmDelete", true);
        set => _settings.Set("clipsManagerConfirmDelete", value);
    }

    public bool ClipsManagerCompactListDensity
    {
        get => _settings.Get("clipsManagerCompactListDensity", false);
        set => _settings.Set("clipsManagerCompactListDensity", value);
    }

    public bool ClipsManagerSelectionRowTapSelects
    {
        get => _settings.Get("clipsManagerSelectionRowTapSelects", true);
        set => _settings.Set("clipsManagerSelectionRowTapSelects", value);
    }

    public bool ClipsManagerIgnoreNonTinyClipsFiles
    {
        get => _settings.Get("clipsManagerIgnoreNonTinyClipsFiles", false);
        set => _settings.Set("clipsManagerIgnoreNonTinyClipsFiles", value);
    }

    public bool ClipsManagerRememberLastState
    {
        get => _settings.Get("clipsManagerRememberLastState", true);
        set => _settings.Set("clipsManagerRememberLastState", value);
    }

    public string ClipsManagerDefaultViewMode
    {
        get => _settings.Get("clipsManagerDefaultViewMode", "grid");
        set => _settings.Set("clipsManagerDefaultViewMode", value);
    }

    public string ClipsManagerDefaultSortOption
    {
        get => _settings.Get("clipsManagerDefaultSortOption", "Newest First");
        set => _settings.Set("clipsManagerDefaultSortOption", value);
    }

    public string ClipsManagerDefaultFilterType
    {
        get => _settings.Get("clipsManagerDefaultFilterType", "All");
        set => _settings.Set("clipsManagerDefaultFilterType", value);
    }

    public string ClipsManagerDefaultDateFilter
    {
        get => _settings.Get("clipsManagerDefaultDateFilter", "Any Date");
        set => _settings.Set("clipsManagerDefaultDateFilter", value);
    }

    public int ClipsManagerAutoRefreshSeconds
    {
        get => _settings.Get("clipsManagerAutoRefreshSeconds", 0);
        set => _settings.Set("clipsManagerAutoRefreshSeconds", value);
    }

    public bool ClipsManagerArchiveOldClips
    {
        get => _settings.Get("clipsManagerArchiveOldClips", false);
        set => _settings.Set("clipsManagerArchiveOldClips", value);
    }

    public int ClipsManagerArchiveAfterDays
    {
        get => _settings.Get("clipsManagerArchiveAfterDays", 30);
        set => _settings.Set("clipsManagerArchiveAfterDays", value);
    }

    public bool ClipsManagerAutoUploadAfterSave
    {
        get => _settings.Get("clipsManagerAutoUploadAfterSave", false);
        set => _settings.Set("clipsManagerAutoUploadAfterSave", value);
    }

    public bool ClipsManagerAutoCopyUploadLink
    {
        get => _settings.Get("clipsManagerAutoCopyUploadLink", false);
        set => _settings.Set("clipsManagerAutoCopyUploadLink", value);
    }

    public double GifFrameRate
    {
        get => _settings.Get("gifFrameRate", 10.0);
        set => _settings.Set("gifFrameRate", value);
    }

    public int GifMaxWidth
    {
        get => _settings.Get("gifMaxWidth", 640);
        set => _settings.Set("gifMaxWidth", value);
    }

    public int VideoFrameRate
    {
        get => _settings.Get("videoFrameRate", 30);
        set => _settings.Set("videoFrameRate", value);
    }

    public bool ShowMouseClickVisualsInVideo
    {
        get => _settings.Get("showMouseClickVisualsInVideo", false);
        set => _settings.Set("showMouseClickVisualsInVideo", value);
    }

    public bool ShowMouseClickVisualsInGif
    {
        get => _settings.Get("showMouseClickVisualsInGif", false);
        set => _settings.Set("showMouseClickVisualsInGif", value);
    }

    public bool GifMouseClicksUseVideoSettings
    {
        get => _settings.Get("gifMouseClicksUseVideoSettings", false);
        set => _settings.Set("gifMouseClicksUseVideoSettings", value);
    }

    public string VideoMouseClickColorHex
    {
        get => _settings.Get("videoMouseClickColorHex", "#0A84FF");
        set => _settings.Set("videoMouseClickColorHex", value);
    }

    public double VideoMouseClickSize
    {
        get => _settings.Get("videoMouseClickSize", 40.0);
        set => _settings.Set("videoMouseClickSize", value);
    }

    public double VideoMouseClickStrokeWidth
    {
        get => _settings.Get("videoMouseClickStrokeWidth", 3.0);
        set => _settings.Set("videoMouseClickStrokeWidth", value);
    }

    public double VideoMouseClickOpacity
    {
        get => _settings.Get("videoMouseClickOpacity", 0.85);
        set => _settings.Set("videoMouseClickOpacity", value);
    }

    public double VideoMouseClickDuration
    {
        get => _settings.Get("videoMouseClickDuration", 0.45);
        set => _settings.Set("videoMouseClickDuration", value);
    }

    public string GifMouseClickColorHex
    {
        get => _settings.Get("gifMouseClickColorHex", "#0A84FF");
        set => _settings.Set("gifMouseClickColorHex", value);
    }

    public double GifMouseClickSize
    {
        get => _settings.Get("gifMouseClickSize", 40.0);
        set => _settings.Set("gifMouseClickSize", value);
    }

    public double GifMouseClickStrokeWidth
    {
        get => _settings.Get("gifMouseClickStrokeWidth", 3.0);
        set => _settings.Set("gifMouseClickStrokeWidth", value);
    }

    public double GifMouseClickOpacity
    {
        get => _settings.Get("gifMouseClickOpacity", 0.85);
        set => _settings.Set("gifMouseClickOpacity", value);
    }

    public double GifMouseClickDuration
    {
        get => _settings.Get("gifMouseClickDuration", 0.45);
        set => _settings.Set("gifMouseClickDuration", value);
    }

    public bool ShowTrimmer
    {
        get => _settings.Get("showTrimmer", true);
        set => _settings.Set("showTrimmer", value);
    }

    public bool RecordAudio
    {
        get => _settings.Get("recordAudio", false);
        set => _settings.Set("recordAudio", value);
    }

    public bool RecordMicrophone
    {
        get => _settings.Get("recordMicrophone", false);
        set => _settings.Set("recordMicrophone", value);
    }

    public string SelectedMicrophoneId
    {
        get => _settings.Get("selectedMicrophoneID", string.Empty);
        set => _settings.Set("selectedMicrophoneID", value);
    }

    public bool ShowScreenshotEditor
    {
        get => _settings.Get("showScreenshotEditor", true);
        set => _settings.Set("showScreenshotEditor", value);
    }

    public bool ShowGifTrimmer
    {
        get => _settings.Get("showGifTrimmer", true);
        set => _settings.Set("showGifTrimmer", value);
    }

    public bool SaveImmediatelyScreenshot
    {
        get => _settings.Get("saveImmediatelyScreenshot", true);
        set => _settings.Set("saveImmediatelyScreenshot", value);
    }

    public bool SaveImmediatelyVideo
    {
        get => _settings.Get("saveImmediatelyVideo", true);
        set => _settings.Set("saveImmediatelyVideo", value);
    }

    public bool SaveImmediatelyGif
    {
        get => _settings.Get("saveImmediatelyGif", true);
        set => _settings.Set("saveImmediatelyGif", value);
    }

    public bool ShowScreenshotCapturePicker
    {
        get => _settings.Get("showScreenshotCapturePicker", true);
        set => _settings.Set("showScreenshotCapturePicker", value);
    }

    public bool ShowScreenshotCapturePickerAfterCapture
    {
        get => _settings.Get("showScreenshotCapturePickerAfterCapture", true);
        set => _settings.Set("showScreenshotCapturePickerAfterCapture", value);
    }

    public bool ShowVideoCapturePicker
    {
        get => _settings.Get("showVideoCapturePicker", true);
        set => _settings.Set("showVideoCapturePicker", value);
    }

    public bool ShowGifCapturePicker
    {
        get => _settings.Get("showGifCapturePicker", true);
        set => _settings.Set("showGifCapturePicker", value);
    }

    public string ScreenshotFormat
    {
        get => _settings.Get("screenshotFormat", "jpg");
        set => _settings.Set("screenshotFormat", value);
    }

    public int ScreenshotScale
    {
        get => _settings.Get("screenshotScale", 100);
        set => _settings.Set("screenshotScale", value);
    }

    public double JpegQuality
    {
        get => _settings.Get("jpegQuality", 0.85);
        set => _settings.Set("jpegQuality", value);
    }

    public bool VideoCountdownEnabled
    {
        get => _settings.Get("videoCountdownEnabled", true);
        set => _settings.Set("videoCountdownEnabled", value);
    }

    public int VideoCountdownDuration
    {
        get => _settings.Get("videoCountdownDuration", 3);
        set => _settings.Set("videoCountdownDuration", value);
    }

    public int VideoRecordingTimeLimitMinutes
    {
        get => _settings.Get("videoRecordingTimeLimitMinutes", 0);
        set => _settings.Set("videoRecordingTimeLimitMinutes", value);
    }

    public bool GifCountdownEnabled
    {
        get => _settings.Get("gifCountdownEnabled", true);
        set => _settings.Set("gifCountdownEnabled", value);
    }

    public int GifCountdownDuration
    {
        get => _settings.Get("gifCountdownDuration", 3);
        set => _settings.Set("gifCountdownDuration", value);
    }

    public bool ScreenshotCountdownEnabled
    {
        get => _settings.Get("screenshotCountdownEnabled", false);
        set => _settings.Set("screenshotCountdownEnabled", value);
    }

    public int ScreenshotCountdownDuration
    {
        get => _settings.Get("screenshotCountdownDuration", 3);
        set => _settings.Set("screenshotCountdownDuration", value);
    }

    public bool HasCompletedOnboarding
    {
        get => _settings.Get("hasCompletedOnboarding", false);
        set => _settings.Set("hasCompletedOnboarding", value);
    }

    public bool AlwaysCaptureMainDisplay
    {
        get => _settings.Get("alwaysCaptureMainDisplay", false);
        set => _settings.Set("alwaysCaptureMainDisplay", value);
    }

    public bool ShowRegionIndicator
    {
        get => _settings.Get("showRegionIndicator", true);
        set => _settings.Set("showRegionIndicator", value);
    }

    public bool IncludeTinyClipsInCapture
    {
        get => _settings.Get("includeTinyClipsInCapture", false);
        set => _settings.Set("includeTinyClipsInCapture", value);
    }

    public bool ShowBrandingOverlay
    {
        get => _settings.Get("showBrandingOverlay", false);
        set => _settings.Set("showBrandingOverlay", value);
    }

    public int ScreenshotHotKeyCode
    {
        get => _settings.Get("screenshotHotKeyCode", 53);
        set => _settings.Set("screenshotHotKeyCode", value);
    }

    public int ScreenshotHotKeyModifiers
    {
        get => _settings.Get("screenshotHotKeyModifiers", 6);
        set => _settings.Set("screenshotHotKeyModifiers", value);
    }

    public int VideoHotKeyCode
    {
        get => _settings.Get("videoHotKeyCode", 54);
        set => _settings.Set("videoHotKeyCode", value);
    }

    public int VideoHotKeyModifiers
    {
        get => _settings.Get("videoHotKeyModifiers", 6);
        set => _settings.Set("videoHotKeyModifiers", value);
    }

    public int GifHotKeyCode
    {
        get => _settings.Get("gifHotKeyCode", 55);
        set => _settings.Set("gifHotKeyCode", value);
    }

    public int GifHotKeyModifiers
    {
        get => _settings.Get("gifHotKeyModifiers", 6);
        set => _settings.Set("gifHotKeyModifiers", value);
    }

    public ImageFormat ImageFormat
    {
        get => string.Equals(ScreenshotFormat, "png", StringComparison.OrdinalIgnoreCase) ? Models.ImageFormat.Png : Models.ImageFormat.Jpeg;
        set => ScreenshotFormat = value == Models.ImageFormat.Png ? "png" : "jpg";
    }

    public bool ShouldCopyToClipboard(CaptureType type) => type switch
    {
        CaptureType.Screenshot => CopyScreenshotToClipboard,
        CaptureType.Video => CopyVideoToClipboard,
        CaptureType.Gif => CopyGifToClipboard,
        _ => false,
    };

    public bool ShouldShowCapturePicker(CaptureType type) => type switch
    {
        CaptureType.Screenshot => ShowScreenshotCapturePicker,
        CaptureType.Video => ShowVideoCapturePicker,
        CaptureType.Gif => ShowGifCapturePicker,
        _ => false,
    };

    public bool ShouldShowScreenshotCapturePickerAfterCapture => ShowScreenshotCapturePicker && ShowScreenshotCapturePickerAfterCapture;

    public MouseClickOverlayStyle MouseClickOverlayStyleFor(CaptureType type) => type switch
    {
        CaptureType.Video => new MouseClickOverlayStyle(VideoMouseClickColorHex, VideoMouseClickSize, VideoMouseClickStrokeWidth, VideoMouseClickOpacity, VideoMouseClickDuration),
        CaptureType.Gif when GifMouseClicksUseVideoSettings => new MouseClickOverlayStyle(VideoMouseClickColorHex, VideoMouseClickSize, VideoMouseClickStrokeWidth, VideoMouseClickOpacity, VideoMouseClickDuration),
        CaptureType.Gif => new MouseClickOverlayStyle(GifMouseClickColorHex, GifMouseClickSize, GifMouseClickStrokeWidth, GifMouseClickOpacity, GifMouseClickDuration),
        CaptureType.Screenshot => new MouseClickOverlayStyle("#FFFFFF", 32, 3, 0.85, 0.45),
        _ => new MouseClickOverlayStyle("#FFFFFF", 32, 3, 0.85, 0.45),
    };

    public bool ShouldShowMouseClickVisuals(CaptureType type) => type switch
    {
        CaptureType.Video => ShowMouseClickVisualsInVideo,
        CaptureType.Gif when GifMouseClicksUseVideoSettings => ShowMouseClickVisualsInVideo,
        CaptureType.Gif => ShowMouseClickVisualsInGif,
        _ => false,
    };

    public void SetShowMouseClickVisuals(bool enabled, CaptureType type)
    {
        switch (type)
        {
            case CaptureType.Video:
                ShowMouseClickVisualsInVideo = enabled;
                break;
            case CaptureType.Gif:
                if (GifMouseClicksUseVideoSettings)
                {
                    ShowMouseClickVisualsInVideo = enabled;
                }
                else
                {
                    ShowMouseClickVisualsInGif = enabled;
                }

                break;
            case CaptureType.Screenshot:
                break;
        }
    }

    public void ResetToDefaults()
    {
        SaveDirectory = string.Empty;
        Theme = AppTheme.Default;
        CopyScreenshotToClipboard = true;
        CopyVideoToClipboard = false;
        CopyGifToClipboard = false;
        ShowInExplorer = false;
        ShowSaveNotifications = false;
        FileNameTemplate = "TinyClips {date} at {time}";
        UploadcareEnabled = false;
        ClipsManagerShowAutoTags = true;
        ClipsManagerShowNotesPreview = true;
        ClipsManagerShowQuickActions = true;
        ClipsManagerShowUploadStatus = true;
        ClipsManagerConfirmDelete = true;
        ClipsManagerCompactListDensity = false;
        ClipsManagerSelectionRowTapSelects = true;
        ClipsManagerIgnoreNonTinyClipsFiles = false;
        ClipsManagerRememberLastState = true;
        ClipsManagerDefaultViewMode = "grid";
        ClipsManagerDefaultSortOption = "Newest First";
        ClipsManagerDefaultFilterType = "All";
        ClipsManagerDefaultDateFilter = "Any Date";
        ClipsManagerAutoRefreshSeconds = 0;
        ClipsManagerArchiveOldClips = false;
        ClipsManagerArchiveAfterDays = 30;
        ClipsManagerAutoUploadAfterSave = false;
        ClipsManagerAutoCopyUploadLink = false;
        GifFrameRate = 10.0;
        GifMaxWidth = 640;
        VideoFrameRate = 30;
        ShowMouseClickVisualsInVideo = false;
        ShowMouseClickVisualsInGif = false;
        GifMouseClicksUseVideoSettings = false;
        VideoMouseClickColorHex = "#0A84FF";
        VideoMouseClickSize = 40.0;
        VideoMouseClickStrokeWidth = 3.0;
        VideoMouseClickOpacity = 0.85;
        VideoMouseClickDuration = 0.45;
        GifMouseClickColorHex = "#0A84FF";
        GifMouseClickSize = 40.0;
        GifMouseClickStrokeWidth = 3.0;
        GifMouseClickOpacity = 0.85;
        GifMouseClickDuration = 0.45;
        ShowTrimmer = true;
        RecordAudio = false;
        RecordMicrophone = false;
        SelectedMicrophoneId = string.Empty;
        ShowScreenshotEditor = true;
        ShowGifTrimmer = true;
        SaveImmediatelyScreenshot = true;
        SaveImmediatelyVideo = true;
        SaveImmediatelyGif = true;
        ShowScreenshotCapturePicker = true;
        ShowScreenshotCapturePickerAfterCapture = true;
        ShowVideoCapturePicker = true;
        ShowGifCapturePicker = true;
        ScreenshotFormat = "jpg";
        ScreenshotScale = 100;
        JpegQuality = 0.85;
        VideoCountdownEnabled = true;
        VideoCountdownDuration = 3;
        VideoRecordingTimeLimitMinutes = 0;
        GifCountdownEnabled = true;
        GifCountdownDuration = 3;
        ScreenshotCountdownEnabled = false;
        ScreenshotCountdownDuration = 3;
        HasCompletedOnboarding = false;
        AlwaysCaptureMainDisplay = false;
        ShowRegionIndicator = true;
        IncludeTinyClipsInCapture = false;
        ShowBrandingOverlay = false;
        ScreenshotHotKeyCode = 53;
        ScreenshotHotKeyModifiers = 6;
        VideoHotKeyCode = 54;
        VideoHotKeyModifiers = 6;
        GifHotKeyCode = 55;
        GifHotKeyModifiers = 6;
    }
}
