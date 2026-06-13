using System.Runtime.InteropServices;
using Vortice.Direct3D11;
using Vortice.DXGI;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;

namespace TinyClips.Core.Capture;

/// <summary>
/// A continuous Windows.Graphics.Capture session that pumps settled BGRA8 frames
/// to a callback at (at most) a target frame rate. Frames are delivered tightly
/// packed and cropped to the optional region. Presentation timestamps are relative
/// to the first delivered frame. Used by the video and GIF recorders.
/// </summary>
internal sealed class ContinuousCaptureSession : IDisposable
{
    private readonly nint _hMonitor;
    private readonly PixelRect? _region;
    private readonly bool _includeCursor;
    private readonly TimeSpan _minFrameInterval;
    private readonly object _sync = new();

    private ID3D11Device? _d3dDevice;
    private IDirect3DDevice? _device;
    private Direct3D11CaptureFramePool? _framePool;
    private GraphicsCaptureSession? _session;
    private ID3D11Texture2D? _stagingTexture;
    private ID3D11DeviceContext? _context;

    private TimeSpan? _baseTime;
    private TimeSpan _lastEmit = TimeSpan.MinValue;
    private int _fullWidth;
    private int _fullHeight;
    private volatile bool _running;

    /// <summary>Raised for each throttled frame: tightly-packed BGRA8 + relative PTS.</summary>
    public event Action<CapturedFrame, TimeSpan>? FrameReady;

    /// <summary>Output width in pixels (region width, or full monitor width), rounded down to even.</summary>
    public int OutputWidth { get; private set; }

    /// <summary>Output height in pixels (region height, or full monitor height), rounded down to even.</summary>
    public int OutputHeight { get; private set; }

    public ContinuousCaptureSession(nint hMonitor, PixelRect? region, int targetFps, bool includeCursor)
    {
        _hMonitor = hMonitor;
        _region = region;
        _includeCursor = includeCursor;
        var fps = Math.Clamp(targetFps, 1, 120);
        // Throttle slightly below the nominal interval so we don't systematically
        // drop every other frame due to timing jitter.
        _minFrameInterval = TimeSpan.FromSeconds(0.95 / fps);
    }

    public void Start()
    {
        if (!GraphicsCaptureSession.IsSupported())
        {
            throw new NotSupportedException("Windows.Graphics.Capture is not supported on this device.");
        }

        _d3dDevice = WgcInterop.CreateD3D11Device()
            ?? throw new InvalidOperationException("Failed to create a Direct3D 11 device.");
        _device = WgcInterop.CreateDirect3DDevice(_d3dDevice)
            ?? throw new InvalidOperationException("Failed to create the WinRT IDirect3DDevice.");
        _context = _d3dDevice.ImmediateContext;

        var item = WgcInterop.CreateCaptureItemForMonitor(_hMonitor)
            ?? throw new InvalidOperationException("Failed to create a GraphicsCaptureItem for the monitor.");

        var size = item.Size;
        _fullWidth = size.Width;
        _fullHeight = size.Height;

        var outW = _region?.Width ?? size.Width;
        var outH = _region?.Height ?? size.Height;
        // H.264 requires even dimensions; GIF tolerates any but even keeps both happy.
        OutputWidth = Math.Max(2, outW - (outW % 2));
        OutputHeight = Math.Max(2, outH - (outH % 2));

        _framePool = Direct3D11CaptureFramePool.CreateFreeThreaded(
            _device,
            DirectXPixelFormat.B8G8R8A8UIntNormalized,
            2,
            size);

        _session = _framePool.CreateCaptureSession(item);
        WgcInterop.TryConfigureSession(_session, _includeCursor);

        _running = true;
        _framePool.FrameArrived += OnFrameArrived;
        _session.StartCapture();
    }

    private void OnFrameArrived(Direct3D11CaptureFramePool pool, object? args)
    {
        if (!_running)
        {
            return;
        }

        try
        {
            using var frame = pool.TryGetNextFrame();
            if (frame is null)
            {
                return;
            }

            lock (_sync)
            {
                if (!_running || _context is null || _d3dDevice is null)
                {
                    return;
                }

                var relative = _baseTime is { } baseTime
                    ? frame.SystemRelativeTime - baseTime
                    : TimeSpan.Zero;

                if (_baseTime is null)
                {
                    _baseTime = frame.SystemRelativeTime;
                    relative = TimeSpan.Zero;
                }

                // Throttle to the target frame rate (but always allow the first frame).
                if (_lastEmit != TimeSpan.MinValue && relative - _lastEmit < _minFrameInterval)
                {
                    return;
                }

                using var frameTexture = WgcInterop.GetTextureFromFrame(frame);
                var desc = frameTexture.Description;

                if (_stagingTexture is null)
                {
                    _stagingTexture = _d3dDevice.CreateTexture2D(new Texture2DDescription
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
                        MiscFlags = ResourceOptionFlags.None,
                    });
                }

                _context.CopyResource(_stagingTexture, frameTexture);

                var captured = ReadStaging((int)desc.Width, (int)desc.Height);
                _lastEmit = relative;

                FrameReady?.Invoke(captured, relative);
            }
        }
        catch
        {
            // A single dropped/failed frame must not tear down the recording.
        }
    }

    private unsafe CapturedFrame ReadStaging(int frameWidth, int frameHeight)
    {
        int x = 0, y = 0;
        int width = OutputWidth, height = OutputHeight;

        if (_region is { } r)
        {
            x = Math.Clamp(r.X, 0, frameWidth);
            y = Math.Clamp(r.Y, 0, frameHeight);
        }

        width = Math.Clamp(width, 1, frameWidth - x);
        height = Math.Clamp(height, 1, frameHeight - y);

        var mapped = _context!.Map(_stagingTexture!, 0, MapMode.Read, Vortice.Direct3D11.MapFlags.None);
        try
        {
            var pixels = new byte[width * height * 4];
            var src = (byte*)mapped.DataPointer;
            int srcPitch = (int)mapped.RowPitch;

            for (int row = 0; row < height; row++)
            {
                int srcOffset = ((y + row) * srcPitch) + (x * 4);
                int dstOffset = row * width * 4;
                Marshal.Copy(new nint(src + srcOffset), pixels, dstOffset, width * 4);
            }

            return new CapturedFrame(pixels, width, height);
        }
        finally
        {
            _context!.Unmap(_stagingTexture!, 0);
        }
    }

    public void Stop()
    {
        _running = false;
        lock (_sync)
        {
            if (_framePool is not null)
            {
                _framePool.FrameArrived -= OnFrameArrived;
            }

            _session?.Dispose();
            _session = null;
        }
    }

    public void Dispose()
    {
        Stop();
        lock (_sync)
        {
            _framePool?.Dispose();
            _framePool = null;
            _stagingTexture?.Dispose();
            _stagingTexture = null;
            _device?.Dispose();
            _device = null;
            _d3dDevice?.Dispose();
            _d3dDevice = null;
            _context = null;
        }
    }
}
