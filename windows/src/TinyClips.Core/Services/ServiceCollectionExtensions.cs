using Microsoft.Extensions.DependencyInjection;
using TinyClips.Core.Capture;

namespace TinyClips.Core.Services;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddTinyClipsCore(this IServiceCollection services)
    {
        services.AddSingleton<ISettingsService, SettingsService>();
        services.AddSingleton<ICaptureSettings, CaptureSettings>();
        services.AddSingleton<IFileSystem, FileSystem>();
        services.AddSingleton<IFileNameService, FileNameService>();
        services.AddSingleton<IClipStorageService, ClipStorageService>();
        services.AddSingleton<IClipsLibraryService, ClipsLibraryService>();
        services.AddSingleton<IHotKeyService, HotKeyService>();
        services.AddSingleton<ILaunchAtLoginService, LaunchAtLoginService>();
        services.AddSingleton<IAudioDeviceService, AudioDeviceService>();
        services.AddSingleton<IMonitorService, MonitorService>();
        services.AddSingleton<IScreenCaptureService, ScreenCaptureService>();
        services.AddSingleton<IScreenshotService, ScreenshotService>();
        services.AddSingleton<IVideoRecordingService, VideoRecordingService>();
        services.AddSingleton<IGifRecordingService, GifRecordingService>();
        return services;
    }
}
