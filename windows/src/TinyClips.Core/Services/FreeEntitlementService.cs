using TinyClips.Core.Models;

namespace TinyClips.Core.Services;

/// <summary>
/// Default entitlement for the direct (winget/MSIX) build, which has no in-app purchase
/// channel. Pro stays locked unless the developer flips the <c>proUnlocked</c> setting
/// (used for parity testing). The Microsoft Store build will replace this with a
/// StoreContext-backed implementation that reflects real Store add-on ownership.
/// </summary>
public sealed class FreeEntitlementService : IEntitlementService
{
    private readonly ISettingsService _settings;

    public FreeEntitlementService(ISettingsService settings)
    {
        _settings = settings;
    }

    public bool IsProUnlocked => _settings.Get("proUnlocked", false);

    public bool CanUse(ProFeature feature) => IsProUnlocked;
}
