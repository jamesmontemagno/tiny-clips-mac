using Microsoft.Extensions.DependencyInjection;

namespace TinyClips.Core.Services;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddTinyClipsCore(this IServiceCollection services)
    {
        services.AddSingleton<ISettingsService, SettingsService>();
        services.AddSingleton<ICaptureSettings, CaptureSettings>();
        services.AddSingleton<IEntitlementService, FreeEntitlementService>();
        services.AddSingleton<IFileSystem, FileSystem>();
        services.AddSingleton<IFileNameService, FileNameService>();
        services.AddSingleton<IClipStorageService, ClipStorageService>();
        return services;
    }
}
