using TinyClips.Core.Models;
using TinyClips.Core.Services;

namespace TinyClips.Core.Tests;

public sealed class CaptureSettingsTests
{
    [Fact]
    public void Defaults_ReturnDocumentedValues()
    {
        var settings = CreateSettings();

        Assert.True(settings.CopyScreenshotToClipboard);
        Assert.Equal(10.0, settings.GifFrameRate);
        Assert.Equal(30, settings.VideoFrameRate);
        Assert.Equal(100, settings.ScreenshotScale);
        Assert.Equal("TinyClips {date} at {time}", settings.FileNameTemplate);
        Assert.True(settings.ShowTrimmer);
    }

    [Fact]
    public void RoundTrip_StoresExpectedValues()
    {
        var settings = CreateSettings();

        settings.CopyScreenshotToClipboard = false;
        settings.GifFrameRate = 24.5;
        settings.VideoFrameRate = 60;
        settings.FileNameTemplate = "Custom {date}";

        Assert.False(settings.CopyScreenshotToClipboard);
        Assert.Equal(24.5, settings.GifFrameRate);
        Assert.Equal(60, settings.VideoFrameRate);
        Assert.Equal("Custom {date}", settings.FileNameTemplate);
    }

    [Fact]
    public void ImageFormat_RoundTripsThroughScreenshotFormat()
    {
        var settings = CreateSettings();

        settings.ImageFormat = ImageFormat.Png;

        Assert.Equal("png", settings.ScreenshotFormat);
        Assert.Equal(ImageFormat.Png, settings.ImageFormat);

        settings.ImageFormat = ImageFormat.Jpeg;

        Assert.Equal("jpg", settings.ScreenshotFormat);
        Assert.Equal(ImageFormat.Jpeg, settings.ImageFormat);
    }

    [Fact]
    public void ShouldCopyToClipboard_And_ShouldShowCapturePicker_ReturnPerTypeValues()
    {
        var settings = CreateSettings();

        settings.CopyScreenshotToClipboard = true;
        settings.CopyVideoToClipboard = false;
        settings.CopyGifToClipboard = true;
        settings.ShowScreenshotCapturePicker = true;
        settings.ShowVideoCapturePicker = false;
        settings.ShowGifCapturePicker = true;

        Assert.True(settings.ShouldCopyToClipboard(CaptureType.Screenshot));
        Assert.False(settings.ShouldCopyToClipboard(CaptureType.Video));
        Assert.True(settings.ShouldCopyToClipboard(CaptureType.Gif));

        Assert.True(settings.ShouldShowCapturePicker(CaptureType.Screenshot));
        Assert.False(settings.ShouldShowCapturePicker(CaptureType.Video));
        Assert.True(settings.ShouldShowCapturePicker(CaptureType.Gif));
    }

    [Fact]
    public void MouseClickStyleFor_GifAndScreenshot_UsesExpectedValues()
    {
        var settings = CreateSettings();

        settings.GifMouseClicksUseVideoSettings = true;
        settings.VideoMouseClickColorHex = "#112233";
        settings.VideoMouseClickSize = 12.5;
        settings.VideoMouseClickStrokeWidth = 4.5;
        settings.VideoMouseClickOpacity = 0.2;
        settings.VideoMouseClickDuration = 1.25;

        var gifStyle = settings.MouseClickOverlayStyleFor(CaptureType.Gif);

        Assert.Equal("#112233", gifStyle.ColorHex);
        Assert.Equal(12.5, gifStyle.Size);
        Assert.Equal(4.5, gifStyle.StrokeWidth);
        Assert.Equal(0.2, gifStyle.Opacity);
        Assert.Equal(1.25, gifStyle.DurationSeconds);

        var screenshotStyle = settings.MouseClickOverlayStyleFor(CaptureType.Screenshot);

        Assert.Equal("#FFFFFF", screenshotStyle.ColorHex);
        Assert.Equal(32.0, screenshotStyle.Size);
        Assert.Equal(3.0, screenshotStyle.StrokeWidth);
        Assert.Equal(0.85, screenshotStyle.Opacity);
        Assert.Equal(0.45, screenshotStyle.DurationSeconds);
    }

    [Fact]
    public void ShouldShowMouseClickVisuals_And_SetShowMouseClickVisuals_HonorsGifMode()
    {
        var settings = CreateSettings();

        settings.GifMouseClicksUseVideoSettings = true;
        settings.ShowMouseClickVisualsInVideo = true;
        settings.ShowMouseClickVisualsInGif = false;

        Assert.True(settings.ShouldShowMouseClickVisuals(CaptureType.Gif));

        settings.SetShowMouseClickVisuals(false, CaptureType.Gif);

        Assert.False(settings.ShowMouseClickVisualsInVideo);

        settings.GifMouseClicksUseVideoSettings = false;
        settings.ShowMouseClickVisualsInGif = true;

        Assert.True(settings.ShouldShowMouseClickVisuals(CaptureType.Gif));

        settings.SetShowMouseClickVisuals(false, CaptureType.Gif);

        Assert.False(settings.ShowMouseClickVisualsInGif);
    }

    [Fact]
    public void ResetToDefaults_RevertsChangedValues()
    {
        var settings = CreateSettings();

        settings.FileNameTemplate = "Changed";
        settings.CopyScreenshotToClipboard = false;
        settings.GifFrameRate = 99;

        settings.ResetToDefaults();

        Assert.Equal("TinyClips {date} at {time}", settings.FileNameTemplate);
        Assert.True(settings.CopyScreenshotToClipboard);
        Assert.Equal(10.0, settings.GifFrameRate);
    }

    private static ICaptureSettings CreateSettings() => new CaptureSettings(new TestSettingsService());

    private sealed class TestSettingsService : ISettingsService
    {
        private readonly Dictionary<string, object> _values = new(StringComparer.OrdinalIgnoreCase);

        public AppTheme Theme { get; set; }

        public string SaveDirectory { get; set; } = string.Empty;

        public T Get<T>(string key, T defaultValue)
        {
            if (_values.TryGetValue(key, out var value))
            {
                if (value is T typedValue)
                {
                    return typedValue;
                }

                if (value is string stringValue && typeof(T).IsEnum)
                {
                    return (T)Enum.Parse(typeof(T), stringValue, true);
                }
            }

            return defaultValue;
        }

        public void Set<T>(string key, T value)
        {
            _values[key] = value is null ? string.Empty : value;
        }
    }
}
