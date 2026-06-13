namespace TinyClips.Core.Services;

using TinyClips.Core.Models;

public interface IEntitlementService
{
    /// <summary>True when the user has unlocked Pro.</summary>
    bool IsProUnlocked { get; }

    /// <summary>True when the given Pro feature may be used (always true once Pro is unlocked).</summary>
    bool CanUse(ProFeature feature);
}
