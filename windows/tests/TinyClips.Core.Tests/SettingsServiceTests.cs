using TinyClips.Core.Models;
using TinyClips.Core.Services;

namespace TinyClips.Core.Tests;

public sealed class SettingsServiceTests
{
    [Fact]
    public void SetAndGet_RoundTripsValue()
    {
        var settings = new SettingsService();

        settings.Set("SampleValue", 42);

        Assert.Equal(42, settings.Get("SampleValue", 0));
    }

    [Fact]
    public void Theme_PersistsThroughService()
    {
        var settings = new SettingsService();

        settings.Theme = AppTheme.Dark;

        Assert.Equal(AppTheme.Dark, settings.Theme);
    }
}
