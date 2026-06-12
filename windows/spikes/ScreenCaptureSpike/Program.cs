using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Vortice.Direct3D11;
using Vortice.DXGI;
using Windows.Foundation.Metadata;
using Windows.Graphics;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;
using WinRT;

namespace ScreenCaptureSpike;

class Program
{
    static async Task<int> Main(string[] args)
    {
        Console.WriteLine("=== Windows.Graphics.Capture Screen Capture Spike ===\n");

        try
        {
            // 1. Enumerate monitors
            Console.WriteLine("--- 1. MONITOR ENUMERATION ---");
            var monitors = EnumerateMonitors();
            if (monitors.Count == 0)
            {
                Console.WriteLine("ERROR: No monitors found!");
                return 1;
            }

            foreach (var mon in monitors)
            {
                Console.WriteLine($"Monitor: {mon.DeviceName}");
                Console.WriteLine($"  Bounds: X={mon.Bounds.Left}, Y={mon.Bounds.Top}, W={mon.Bounds.Width}, H={mon.Bounds.Height} (physical pixels)");
                Console.WriteLine($"  DPI: {mon.DpiX} x {mon.DpiY}, Scale: {mon.ScaleFactor:F2}x");
                Console.WriteLine($"  IsPrimary: {mon.IsPrimary}");
                Console.WriteLine($"  HMONITOR: 0x{mon.HMonitor:X}");
                Console.WriteLine();
            }

            // 2. Check API capabilities
            Console.WriteLine("--- 2. API CAPABILITY MATRIX ---");
            CheckCapabilities();
            Console.WriteLine();

            // 3. Test capture on primary monitor
            var primaryMonitor = monitors.FirstOrDefault(m => m.IsPrimary);
            if (primaryMonitor.DeviceName == null)
            {
                Console.WriteLine("ERROR: No primary monitor found!");
                return 1;
            }

            Console.WriteLine($"--- 3. CAPTURE TEST (Primary Monitor) ---");
            Console.WriteLine($"Target: {primaryMonitor.DeviceName} ({primaryMonitor.Bounds.Width}x{primaryMonitor.Bounds.Height})");

            // Create D3D11 device
            var d3dDevice = CreateD3D11Device();
            if (d3dDevice == null)
            {
                Console.WriteLine("ERROR: Failed to create D3D11 device!");
                return 1;
            }
            Console.WriteLine("✓ Created D3D11 device");

            // Create IDirect3DDevice for WGC
            var device = CreateDirect3DDevice(d3dDevice);
            if (device == null)
            {
                Console.WriteLine("ERROR: Failed to create IDirect3DDevice!");
                return 1;
            }
            Console.WriteLine("✓ Created IDirect3DDevice for WGC");

            // Create GraphicsCaptureItem for primary monitor
            var item = CreateCaptureItemForMonitor(primaryMonitor.HMonitor);
            if (item == null)
            {
                Console.WriteLine("ERROR: Failed to create GraphicsCaptureItem!");
                return 1;
            }
            Console.WriteLine($"✓ Created GraphicsCaptureItem (Size: {item.Size.Width}x{item.Size.Height})");

            // Capture frames
            var frameResults = await CaptureFramesAsync(device, item, d3dDevice, primaryMonitor);

            if (frameResults != null && frameResults.FrameCount > 0)
            {
                Console.WriteLine($"\n✓ Captured {frameResults.FrameCount} frames");
                Console.WriteLine($"  First frame time: {frameResults.FirstFrameTime}");
                Console.WriteLine($"  Last frame time: {frameResults.LastFrameTime}");
                Console.WriteLine($"  Average frame delta: {frameResults.AverageDelta.TotalMilliseconds:F2}ms");
                Console.WriteLine($"  Implied FPS: {frameResults.ImpliedFps:F1}");

                // 4. Region crop test
                if (frameResults.LastTexture != null)
                {
                    Console.WriteLine("\n--- 4. REGION CROP TEST ---");
                    await TestRegionCrop(d3dDevice, frameResults.LastTexture, primaryMonitor);
                }
            }
            else
            {
                Console.WriteLine("\n⚠ Frame capture did not complete (likely headless environment)");
                Console.WriteLine("  Monitor enumeration and API probing succeeded.");
                Console.WriteLine("  Live frame capture must be validated on an interactive desktop.");
            }

            Console.WriteLine("\n=== Spike Complete ===");
            return 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"\nFATAL ERROR: {ex.GetType().Name}: {ex.Message}");
            Console.WriteLine(ex.StackTrace);
            return 1;
        }
    }

    #region Monitor Enumeration

    struct MonitorInfo
    {
        public string DeviceName;
        public RECT Bounds;
        public int DpiX;
        public int DpiY;
        public double ScaleFactor;
        public bool IsPrimary;
        public IntPtr HMonitor;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
        public readonly int Width => Right - Left;
        public readonly int Height => Bottom - Top;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct MONITORINFOEX
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szDevice;
    }

    const int MONITOR_DEFAULTTOPRIMARY = 1;
    const int MDT_EFFECTIVE_DPI = 0;

    [DllImport("user32.dll")]
    static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);

    [DllImport("shcore.dll")]
    static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

    delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData);

    static List<MonitorInfo> EnumerateMonitors()
    {
        var monitors = new List<MonitorInfo>();

        MonitorEnumProc callback = (IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData) =>
        {
            var info = new MONITORINFOEX { cbSize = Marshal.SizeOf<MONITORINFOEX>() };
            if (GetMonitorInfo(hMonitor, ref info))
            {
                GetDpiForMonitor(hMonitor, MDT_EFFECTIVE_DPI, out var dpiX, out var dpiY);

                monitors.Add(new MonitorInfo
                {
                    DeviceName = info.szDevice,
                    Bounds = info.rcMonitor,
                    DpiX = (int)dpiX,
                    DpiY = (int)dpiY,
                    ScaleFactor = dpiX / 96.0,
                    IsPrimary = (info.dwFlags & 1) != 0,
                    HMonitor = hMonitor
                });
            }
            return true;
        };

        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero);

        return monitors;
    }

    #endregion

    #region API Capability Probing

    static void CheckCapabilities()
    {
        // Check if GraphicsCaptureSession APIs are present
        bool hasCursorToggle = ApiInformation.IsPropertyPresent("Windows.Graphics.Capture.GraphicsCaptureSession", "IsCursorCaptureEnabled");
        bool hasBorderToggle = ApiInformation.IsPropertyPresent("Windows.Graphics.Capture.GraphicsCaptureSession", "IsBorderRequired");
        
        // Check for dirty region support (Windows 11 22H2+)
        bool hasDirtyRegion = ApiInformation.IsEnumNamedValuePresent("Windows.Graphics.Capture.GraphicsCaptureSessionDirtyRegionMode", "Enabled");
        
        // Check for window exclusion (Windows 11 24H2+)
        bool hasWindowExclusion = ApiInformation.IsMethodPresent("Windows.Graphics.Capture.GraphicsCaptureSession", "TryExcludeWindowAsync");

        Console.WriteLine($"IsCursorCaptureEnabled: {(hasCursorToggle ? "✓ Available" : "✗ Not available")}");
        Console.WriteLine($"IsBorderRequired: {(hasBorderToggle ? "✓ Available" : "✗ Not available")}");
        Console.WriteLine($"DirtyRegionMode: {(hasDirtyRegion ? "✓ Available" : "✗ Not available")}");
        Console.WriteLine($"Window Exclusion (TryExcludeWindowAsync): {(hasWindowExclusion ? "✓ Available" : "✗ Not available")}");

        if (!hasWindowExclusion)
        {
            Console.WriteLine("\n⚠ Window exclusion not available on this Windows build.");
            Console.WriteLine("  Fallback: Hide UI windows + drop pre-roll frames.");
        }
    }

    #endregion

    #region D3D11 Device Creation

    static ID3D11Device? CreateD3D11Device()
    {
        var featureLevels = new[]
        {
            Vortice.Direct3D.FeatureLevel.Level_11_1,
            Vortice.Direct3D.FeatureLevel.Level_11_0
        };

        var result = D3D11.D3D11CreateDevice(
            null,
            Vortice.Direct3D.DriverType.Hardware,
            DeviceCreationFlags.BgraSupport,
            featureLevels,
            out var device);

        return result.Success ? device : null;
    }

    [DllImport("d3d11.dll", ExactSpelling = true)]
    static extern int CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgiDevice, out IntPtr graphicsDevice);

    static IDirect3DDevice? CreateDirect3DDevice(ID3D11Device d3dDevice)
    {
        var dxgiDevice = d3dDevice.QueryInterface<IDXGIDevice>();
        if (dxgiDevice == null) return null;

        var hr = CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice.NativePointer, out var pInspectable);
        dxgiDevice.Dispose();

        if (hr != 0) return null;

        var device = WinRT.MarshalInterface<IDirect3DDevice>.FromAbi(pInspectable);
        Marshal.Release(pInspectable);
        return device;
    }

    #endregion

    #region GraphicsCaptureItem Creation

    [ComImport]
    [System.Runtime.InteropServices.Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IGraphicsCaptureItemInterop
    {
        int CreateForWindow([In] IntPtr window, [In] ref System.Guid iid, out IntPtr result);
        int CreateForMonitor([In] IntPtr monitor, [In] ref System.Guid iid, out IntPtr result);
    }

    [DllImport("d3d11.dll", EntryPoint = "CreateDirect3D11DeviceFromDXGIDevice", ExactSpelling = true, PreserveSig = false)]
    static extern void CreateDirect3D11DeviceFromDXGIDeviceInternal(IntPtr dxgiDevice, out IntPtr graphicsDevice);

    [DllImport("api-ms-win-core-winrt-l1-1-0.dll", EntryPoint = "RoGetActivationFactory", CharSet = CharSet.Unicode, PreserveSig = false)]
    static extern void RoGetActivationFactory(IntPtr activatableClassId, [In] ref System.Guid iid, out IntPtr factory);

    static GraphicsCaptureItem? CreateCaptureItemForMonitor(IntPtr hMonitor)
    {
        try
        {
            var className = "Windows.Graphics.Capture.GraphicsCaptureItem";
            var interopGuid = new System.Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356");
            
            // Create HSTRING for class name
            IntPtr hClassName = IntPtr.Zero;
            WindowsCreateString(className, (uint)className.Length, out hClassName);

            try
            {
                RoGetActivationFactory(hClassName, ref interopGuid, out var pFactory);
                
                // Query for IGraphicsCaptureItemInterop interface
                var hr = Marshal.QueryInterface(pFactory, ref interopGuid, out var pInterop);
                Marshal.Release(pFactory);

                if (hr != 0)
                {
                    Console.WriteLine($"QueryInterface failed with HRESULT: 0x{hr:X8}");
                    return null;
                }

                var interop = (IGraphicsCaptureItemInterop)Marshal.GetTypedObjectForIUnknown(pInterop, typeof(IGraphicsCaptureItemInterop));
                
                var itemGuid = typeof(GraphicsCaptureItem).GUID;
                hr = interop.CreateForMonitor(hMonitor, ref itemGuid, out var pItem);

                Marshal.Release(pInterop);

                if (hr != 0)
                {
                    Console.WriteLine($"CreateForMonitor failed with HRESULT: 0x{hr:X8}");
                    return null;
                }

                var item = MarshalInterface<GraphicsCaptureItem>.FromAbi(pItem);
                Marshal.Release(pItem);
                return item;
            }
            finally
            {
                WindowsDeleteString(hClassName);
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"CreateCaptureItemForMonitor error: {ex.Message}");
            return null;
        }
    }

    [DllImport("api-ms-win-core-winrt-string-l1-1-0.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    static extern void WindowsCreateString([MarshalAs(UnmanagedType.LPWStr)] string sourceString, uint length, out IntPtr hstring);

    [DllImport("api-ms-win-core-winrt-string-l1-1-0.dll", PreserveSig = false)]
    static extern void WindowsDeleteString(IntPtr hstring);

    #endregion

    #region Frame Capture

    class FrameResults
    {
        public int FrameCount;
        public TimeSpan FirstFrameTime;
        public TimeSpan LastFrameTime;
        public TimeSpan AverageDelta;
        public double ImpliedFps;
        public ID3D11Texture2D? LastTexture;
    }

    static async Task<FrameResults?> CaptureFramesAsync(
        IDirect3DDevice device,
        GraphicsCaptureItem item,
        ID3D11Device d3dDevice,
        MonitorInfo monitor)
    {
        var framePool = Direct3D11CaptureFramePool.CreateFreeThreaded(
            device,
            DirectXPixelFormat.B8G8R8A8UIntNormalized,
            2,
            item.Size);

        var session = framePool.CreateCaptureSession(item);

        // Configure session if APIs available
        try
        {
            if (ApiInformation.IsPropertyPresent("Windows.Graphics.Capture.GraphicsCaptureSession", "IsCursorCaptureEnabled"))
            {
                session.IsCursorCaptureEnabled = false;
            }
            if (ApiInformation.IsPropertyPresent("Windows.Graphics.Capture.GraphicsCaptureSession", "IsBorderRequired"))
            {
                session.IsBorderRequired = false;
            }
        }
        catch { }

        var frameTimes = new List<TimeSpan>();
        ID3D11Texture2D? lastTexture = null;
        var tcs = new TaskCompletionSource<bool>();
        int targetFrames = 30;

        framePool.FrameArrived += (s, e) =>
        {
            try
            {
                using var frame = s.TryGetNextFrame();
                if (frame != null)
                {
                    frameTimes.Add(frame.SystemRelativeTime);

                    // Keep the last frame texture for cropping test
                    if (frameTimes.Count == targetFrames)
                    {
                        lastTexture = GetTextureFromFrame(frame, d3dDevice);
                    }

                    if (frameTimes.Count >= targetFrames)
                    {
                        tcs.TrySetResult(true);
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Frame error: {ex.Message}");
            }
        };

        session.StartCapture();
        Console.WriteLine($"Capturing {targetFrames} frames...");

        // Wait for frames or timeout
        var timeoutTask = Task.Delay(5000);
        var completedTask = await Task.WhenAny(tcs.Task, timeoutTask);

        session.Dispose();
        framePool.Dispose();

        if (completedTask == timeoutTask || frameTimes.Count == 0)
        {
            Console.WriteLine("⚠ No frames captured (timeout or no frames arrived)");
            return null;
        }

        // Calculate frame timing stats
        var deltas = new List<TimeSpan>();
        for (int i = 1; i < frameTimes.Count; i++)
        {
            deltas.Add(frameTimes[i] - frameTimes[i - 1]);
        }

        var avgDelta = TimeSpan.FromTicks((long)deltas.Average(d => d.Ticks));
        var impliedFps = avgDelta.TotalSeconds > 0 ? 1.0 / avgDelta.TotalSeconds : 0;

        return new FrameResults
        {
            FrameCount = frameTimes.Count,
            FirstFrameTime = frameTimes.First(),
            LastFrameTime = frameTimes.Last(),
            AverageDelta = avgDelta,
            ImpliedFps = impliedFps,
            LastTexture = lastTexture
        };
    }

    static ID3D11Texture2D? GetTextureFromFrame(Direct3D11CaptureFrame frame, ID3D11Device device)
    {
        try
        {
            var surface = frame.Surface;
            var access = surface.As<IDirect3DDxgiInterfaceAccess>();
            if (access == null) return null;

            var pResource = access.GetInterface(typeof(IDXGISurface).GUID);
            var dxgiSurface = MarshalInterface<IDXGISurface>.FromAbi(pResource);
            
            if (dxgiSurface != null)
            {
                var texture = dxgiSurface.QueryInterface<ID3D11Texture2D>();
                dxgiSurface.Dispose();
                return texture;
            }
        }
        catch { }
        return null;
    }

    [ComImport]
    [System.Runtime.InteropServices.Guid("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDirect3DDxgiInterfaceAccess
    {
        IntPtr GetInterface([In] ref System.Guid iid);
    }

    #endregion

    #region Region Crop Test

    static async Task TestRegionCrop(ID3D11Device device, ID3D11Texture2D sourceTexture, MonitorInfo monitor)
    {
        var desc = sourceTexture.Description;
        Console.WriteLine($"Source texture: {desc.Width}x{desc.Height}, Format: {desc.Format}");

        // Create staging texture to read pixels
        var stagingDesc = new Texture2DDescription
        {
            Width = desc.Width,
            Height = desc.Height,
            MipLevels = 1,
            ArraySize = 1,
            Format = desc.Format,
            SampleDescription = new SampleDescription(1, 0),
            Usage = ResourceUsage.Staging,
            BindFlags = BindFlags.None,
            CPUAccessFlags = CpuAccessFlags.Read,
            MiscFlags = ResourceOptionFlags.None
        };

        var stagingTexture = device.CreateTexture2D(stagingDesc);
        var context = device.ImmediateContext;
        context.CopyResource(stagingTexture, sourceTexture);

        // Save full frame
        var fullPath = Path.Combine(Directory.GetCurrentDirectory(), "fullframe.png");
        await SaveTextureToPng(stagingTexture, context, fullPath, 0, 0, (int)desc.Width, (int)desc.Height);
        Console.WriteLine($"✓ Saved full frame: {fullPath} ({desc.Width}x{desc.Height})");

        // Crop region (400x300 at offset 100,100)
        int cropX = 100, cropY = 100, cropW = 400, cropH = 300;
        
        // Ensure crop is within bounds
        if (cropX + cropW > (int)desc.Width) cropW = (int)desc.Width - cropX;
        if (cropY + cropH > (int)desc.Height) cropH = (int)desc.Height - cropY;

        var croppedPath = Path.Combine(Directory.GetCurrentDirectory(), "cropped.png");
        await SaveTextureToPng(stagingTexture, context, croppedPath, cropX, cropY, cropW, cropH);
        Console.WriteLine($"✓ Saved cropped region: {croppedPath} ({cropW}x{cropH} at {cropX},{cropY})");

        // Verify cropped file
        var croppedFile = await StorageFile.GetFileFromPathAsync(croppedPath);
        using var stream = await croppedFile.OpenReadAsync();
        var decoder = await BitmapDecoder.CreateAsync(stream);
        Console.WriteLine($"✓ Verified cropped PNG: {decoder.PixelWidth}x{decoder.PixelHeight}");

        if ((int)decoder.PixelWidth == cropW && (int)decoder.PixelHeight == cropH)
        {
            Console.WriteLine("✓ Crop dimensions match exactly!");
        }
        else
        {
            Console.WriteLine($"⚠ Crop dimension mismatch: expected {cropW}x{cropH}, got {decoder.PixelWidth}x{decoder.PixelHeight}");
        }

        stagingTexture.Dispose();
    }

    static async Task SaveTextureToPng(
        ID3D11Texture2D stagingTexture,
        ID3D11DeviceContext context,
        string filePath,
        int x, int y, int width, int height)
    {
        var mapped = context.Map(stagingTexture, 0, MapMode.Read, Vortice.Direct3D11.MapFlags.None);
        try
        {
            var fullDesc = stagingTexture.Description;
            
            // Create bitmap from mapped data
            var pixels = new byte[width * height * 4];
            unsafe
            {
                var src = (byte*)mapped.DataPointer;
                int srcPitch = (int)mapped.RowPitch;

                for (int row = 0; row < height; row++)
                {
                    int srcOffset = (y + row) * srcPitch + x * 4;
                    int dstOffset = row * width * 4;
                    Marshal.Copy(new IntPtr(src + srcOffset), pixels, dstOffset, width * 4);
                }
            }

            // Save using Windows.Graphics.Imaging
            var file = await StorageFile.GetFileFromPathAsync(filePath).AsTask().ContinueWith(async t =>
            {
                if (t.IsFaulted)
                {
                    var folder = await StorageFolder.GetFolderFromPathAsync(Path.GetDirectoryName(filePath)!);
                    return await folder.CreateFileAsync(Path.GetFileName(filePath), CreationCollisionOption.ReplaceExisting);
                }
                return await t;
            }).Unwrap();

            using var stream = await file.OpenAsync(FileAccessMode.ReadWrite);
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
            encoder.SetPixelData(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Premultiplied,
                (uint)width,
                (uint)height,
                96.0, 96.0,
                pixels);
            await encoder.FlushAsync();
        }
        finally
        {
            context.Unmap(stagingTexture, 0);
        }
    }

    #endregion
}
