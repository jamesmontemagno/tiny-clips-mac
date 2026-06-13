using TinyClips.Core.Models;

namespace TinyClips.Core.Capture;

public interface IScreenshotService
{
    /// <summary>
    /// Captures the full primary monitor, encodes it per the user's screenshot
    /// settings (PNG/JPEG, scale, quality) and saves it. Returns the saved file path.
    /// </summary>
    Task<string> CaptureFullScreenAsync(CancellationToken cancellationToken = default);
}
