using TinyClips.Core.Models;

namespace TinyClips.Core.Services;

/// <summary>
/// Default entitlement for the direct (unpackaged/winget) build, which matches the
/// macOS direct-distribution app by unlocking Pro without Store gating. The
/// Microsoft Store build will replace this with a StoreContext-backed implementation
/// that reflects real Store add-on ownership.
/// </summary>
public sealed class FreeEntitlementService : IEntitlementService
{
    private readonly ISettingsService _settings;

    public FreeEntitlementService(ISettingsService settings)
    {
        _settings = settings;
    }

    public bool IsProUnlocked => _settings.Get("proUnlocked", true);

    public bool CanUse(ProFeature feature) => IsProUnlocked;
}
