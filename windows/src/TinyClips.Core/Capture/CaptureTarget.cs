using Windows.Graphics.Capture;

namespace TinyClips.Core.Capture;

/// <summary>
/// Identifies what to capture: an entire monitor (by HMONITOR) or a specific
/// top-level window (by HWND). Mirrors the macOS picker's screen/window modes.
/// Region cropping is layered on top of a monitor target by the capture engines.
/// </summary>
public sealed class CaptureTarget
{
    private CaptureTarget(nint hMonitor, nint hwnd)
    {
        HMonitor = hMonitor;
        Hwnd = hwnd;
    }

    public nint HMonitor { get; }

    public nint Hwnd { get; }

    public bool IsWindow => Hwnd != 0;

    public static CaptureTarget Monitor(nint hMonitor) => new(hMonitor, 0);

    public static CaptureTarget Window(nint hwnd) => new(0, hwnd);

    internal GraphicsCaptureItem CreateItem() => IsWindow
        ? WgcInterop.CreateCaptureItemForWindow(Hwnd)
        : WgcInterop.CreateCaptureItemForMonitor(HMonitor);
}
