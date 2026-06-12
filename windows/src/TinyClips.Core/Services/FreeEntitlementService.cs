namespace TinyClips.Core.Services;

public sealed class FreeEntitlementService : IEntitlementService
{
    public bool IsProUnlocked => false;

    public bool IsFeatureEnabled(string featureId) => true;
}
