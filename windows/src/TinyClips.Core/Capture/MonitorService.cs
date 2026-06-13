using System.Runtime.InteropServices;

namespace TinyClips.Core.Capture;

/// <summary>
/// Enumerates monitors via Win32 (<c>EnumDisplayMonitors</c> / <c>GetMonitorInfo</c> /
/// <c>GetDpiForMonitor</c>). Windows.Graphics.Display does not expose the HMONITOR
/// handles required by Windows.Graphics.Capture, so the Win32 path is used here.
/// </summary>
public sealed class MonitorService : IMonitorService
{
    private const int MdtEffectiveDpi = 0;
    private const uint MonitorinfofPrimary = 1;

    public IReadOnlyList<MonitorInfo> GetMonitors()
    {
        var monitors = new List<MonitorInfo>();

        bool Callback(nint hMonitor, nint hdc, ref Rect rect, nint data)
        {
            var info = new MonitorInfoEx { CbSize = Marshal.SizeOf<MonitorInfoEx>() };
            if (GetMonitorInfo(hMonitor, ref info))
            {
                if (GetDpiForMonitor(hMonitor, MdtEffectiveDpi, out var dpiX, out var dpiY) != 0)
                {
                    dpiX = 96;
                    dpiY = 96;
                }

                monitors.Add(new MonitorInfo
                {
                    DeviceName = info.SzDevice,
                    X = info.RcMonitor.Left,
                    Y = info.RcMonitor.Top,
                    Width = info.RcMonitor.Right - info.RcMonitor.Left,
                    Height = info.RcMonitor.Bottom - info.RcMonitor.Top,
                    DpiX = (int)dpiX,
                    DpiY = (int)dpiY,
                    IsPrimary = (info.DwFlags & MonitorinfofPrimary) != 0,
                    HMonitor = hMonitor,
                });
            }

            return true;
        }

        EnumDisplayMonitors(nint.Zero, nint.Zero, Callback, nint.Zero);
        return monitors;
    }

    public MonitorInfo? GetPrimaryMonitor()
    {
        var monitors = GetMonitors();
        return monitors.FirstOrDefault(m => m.IsPrimary) ?? monitors.FirstOrDefault();
    }

    private delegate bool MonitorEnumProc(nint hMonitor, nint hdc, ref Rect rect, nint data);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(nint hdc, nint clip, MonitorEnumProc callback, nint data);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool GetMonitorInfo(nint hMonitor, ref MonitorInfoEx info);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(nint hMonitor, int dpiType, out uint dpiX, out uint dpiY);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MonitorInfoEx
    {
        public int CbSize;
        public Rect RcMonitor;
        public Rect RcWork;
        public uint DwFlags;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string SzDevice;
    }
}
