namespace TinyClips.Core.Capture;

/// <summary>
/// Records the primary monitor to an H.264 MP4 file using a continuous WGC capture
/// pipeline fed into a Media Foundation transcoder. Video-only for now (audio is a
/// later phase). Start/Stop are single-recording; <see cref="IsRecording"/> guards reentry.
/// </summary>
public interface IVideoRecordingService
{
    bool IsRecording { get; }

    /// <summary>Raised when a recording finishes (manual stop or time-limit), with the saved file path.</summary>
    event EventHandler<string?>? RecordingCompleted;

    /// <summary>
    /// Begins recording. When <paramref name="target"/> is null the primary monitor is
    /// recorded; pass a monitor or window target (and optional monitor-relative region)
    /// to record a specific screen, window, or region. Throws if already recording.
    /// </summary>
    Task StartAsync(CaptureTarget? target = null, PixelRect? region = null, double? timeLimitMinutesOverride = null, CancellationToken cancellationToken = default);

    /// <summary>Stops recording, finalizes the MP4 and returns the saved path (or null if nothing recorded).</summary>
    Task<string?> StopAsync();
}
