namespace TinyClips.Core.Capture;

/// <summary>
/// Describes a physical display, in physical pixels, as reported by the Win32
/// monitor enumeration APIs. <see cref="HMonitor"/> is the handle required by
/// Windows.Graphics.Capture to target the monitor.
/// </summary>
public sealed record MonitorInfo
{
    public required string DeviceName { get; init; }

    /// <summary>Left edge in virtual-desktop physical pixels (can be negative).</summary>
    public required int X { get; init; }

    /// <summary>Top edge in virtual-desktop physical pixels (can be negative).</summary>
    public required int Y { get; init; }

    /// <summary>Width in physical pixels.</summary>
    public required int Width { get; init; }

    /// <summary>Height in physical pixels.</summary>
    public required int Height { get; init; }

    /// <summary>Work-area left edge in virtual-desktop physical pixels.</summary>
    public required int WorkAreaX { get; init; }

    /// <summary>Work-area top edge in virtual-desktop physical pixels.</summary>
    public required int WorkAreaY { get; init; }

    /// <summary>Work-area width in physical pixels.</summary>
    public required int WorkAreaWidth { get; init; }

    /// <summary>Work-area height in physical pixels.</summary>
    public required int WorkAreaHeight { get; init; }

    public required int DpiX { get; init; }

    public required int DpiY { get; init; }

    public required bool IsPrimary { get; init; }

    public required nint HMonitor { get; init; }

    /// <summary>Effective scale factor (1.0 == 96 DPI).</summary>
    public double ScaleFactor => DpiX / 96.0;
}
