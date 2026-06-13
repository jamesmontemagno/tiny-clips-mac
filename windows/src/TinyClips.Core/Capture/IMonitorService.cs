namespace TinyClips.Core.Capture;

public interface IMonitorService
{
    /// <summary>Enumerates all connected monitors in physical pixels.</summary>
    IReadOnlyList<MonitorInfo> GetMonitors();

    /// <summary>Returns the primary monitor, or the first monitor if none is flagged primary.</summary>
    MonitorInfo? GetPrimaryMonitor();
}
