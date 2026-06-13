namespace TinyClips.Core.Capture;

/// <summary>
/// Records the primary monitor to an animated GIF. Frames are accumulated during
/// recording and encoded (with frame delays, infinite loop and max-width scaling)
/// when recording stops.
/// </summary>
public interface IGifRecordingService
{
    bool IsRecording { get; }

    /// <summary>Raised when a recording finishes (manual stop or time-limit), with the saved file path.</summary>
    event EventHandler<string?>? RecordingCompleted;

    /// <summary>Begins recording the primary monitor. Throws if already recording.</summary>
    Task StartAsync(CancellationToken cancellationToken = default);

    /// <summary>Stops recording, encodes the GIF and returns the saved path (or null if nothing recorded).</summary>
    Task<string?> StopAsync();
}
