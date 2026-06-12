using Microsoft.Extensions.DependencyInjection;

namespace TinyClips.Core.Services;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddTinyClipsCore(this IServiceCollection services)
    {
        services.AddSingleton<ISettingsService, SettingsService>();
        services.AddSingleton<IEntitlementService, FreeEntitlementService>();
        return services;
    }
}
