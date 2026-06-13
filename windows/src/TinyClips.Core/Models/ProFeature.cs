namespace TinyClips.Core.Models;

/// <summary>
/// Pro-only capabilities. In the direct (winget/MSIX) build these are gated off; the
/// Microsoft Store build will unlock them via Store add-ons. Mirrors the macOS Pro set.
/// </summary>
public enum ProFeature
{
    /// <summary>Mouse-click visual overlays during recording.</summary>
    MouseClickVisuals,

    /// <summary>"Captured on Tiny Clips" branding overlay control (removal/customization).</summary>
    BrandingOverlay,

    /// <summary>Clips Manager organization: favorites, rename, tags, notes, collections.</summary>
    ClipsOrganization,

    /// <summary>Upload / share-link integration.</summary>
    Upload,

    /// <summary>Advanced video options (e.g. higher frame rates / no time limit).</summary>
    AdvancedVideo,

    /// <summary>Advanced GIF options.</summary>
    AdvancedGif,
}
