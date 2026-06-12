namespace TinyClips.Core.Services;

public interface IEntitlementService
{
    bool IsProUnlocked { get; }
    bool IsFeatureEnabled(string featureId);
}
