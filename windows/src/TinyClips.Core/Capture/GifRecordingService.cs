using System.Text;
using TinyClips.Core.Models;
using TinyClips.Core.Services;
using Windows.Foundation;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace TinyClips.Core.Capture;

/// <summary>
/// Records the primary monitor to an animated GIF. A continuous WGC capture session
/// accumulates throttled BGRA frames; on stop they are encoded with per-frame delays,
/// an infinite-loop application extension and optional max-width downscaling.
/// </summary>
public sealed class GifRecordingService : IGifRecordingService
{
    // Cap memory: ~30s at the default GIF frame rate.
    private const int MaxFrames = 900;

    private readonly IMonitorService _monitors;
    private readonly IClipStorageService _storage;
    private readonly ICaptureSettings _settings;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly object _frameLock = new();

    private ContinuousCaptureSession? _capture;
    private List<CapturedFrame>? _frames;
    private double _fps;
    private int _stopping;

    private MouseClickMonitor? _clickMonitor;
    private MouseClickOverlayStyle _clickStyle;
    private int _clickOriginX;
    private int _clickOriginY;

    public GifRecordingService(
        IMonitorService monitors,
        IClipStorageService storage,
        ICaptureSettings settings)
    {
        _monitors = monitors;
        _storage = storage;
        _settings = settings;
    }

    public bool IsRecording { get; private set; }

    public event EventHandler<string?>? RecordingCompleted;

    public async Task StartAsync(CaptureTarget? target = null, PixelRect? region = null, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (IsRecording)
            {
                throw new InvalidOperationException("A GIF recording is already in progress.");
            }

            var captureTarget = target ?? CaptureTarget.Monitor(
                (_monitors.GetPrimaryMonitor()
                    ?? throw new InvalidOperationException("No monitor was found to record.")).HMonitor);

            _fps = Math.Clamp(_settings.GifFrameRate, 1, 50);
            _frames = new List<CapturedFrame>();

            _capture = new ContinuousCaptureSession(captureTarget, region, (int)Math.Round(_fps), includeCursor: true);
            _capture.FrameReady += OnFrameReady;
            _capture.Start();

            StartMouseClickOverlay(captureTarget, region);

            IsRecording = true;
        }
        finally
        {
            _gate.Release();
        }
    }

    private void OnFrameReady(CapturedFrame frame, TimeSpan pts)
    {
        if (_clickMonitor is { } monitor)
        {
            MouseClickOverlayCompositor.Draw(
                frame.BgraPixels,
                frame.Width,
                frame.Height,
                pts.TotalSeconds,
                monitor.GetClicks(),
                _clickOriginX,
                _clickOriginY,
                _clickStyle);
        }

        lock (_frameLock)
        {
            if (_frames is { Count: < MaxFrames })
            {
                _frames.Add(frame);
            }
        }
    }

    private void StartMouseClickOverlay(CaptureTarget target, PixelRect? region)
    {
        if (target.IsWindow || !_settings.ShouldShowMouseClickVisuals(CaptureType.Gif))
        {
            return;
        }

        var monitor = _monitors.GetMonitors().FirstOrDefault(m => m.HMonitor == target.HMonitor)
            ?? _monitors.GetPrimaryMonitor();
        if (monitor == null)
        {
            return;
        }

        _clickOriginX = monitor.X + (region?.X ?? 0);
        _clickOriginY = monitor.Y + (region?.Y ?? 0);
        _clickStyle = _settings.MouseClickOverlayStyleFor(CaptureType.Gif);
        _clickMonitor = new MouseClickMonitor();
        _clickMonitor.Start();
    }

    public async Task<string?> StopAsync()
    {
        if (Interlocked.Exchange(ref _stopping, 1) == 1)
        {
            return null;
        }

        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (!IsRecording)
            {
                return null;
            }

            _capture?.Stop();
            _clickMonitor?.Dispose();
            _clickMonitor = null;

            List<CapturedFrame> frames;
            lock (_frameLock)
            {
                frames = _frames ?? new List<CapturedFrame>();
                _frames = null;
            }

            _capture?.Dispose();
            _capture = null;
            IsRecording = false;

            if (frames.Count == 0)
            {
                return null;
            }

            var path = _storage.GenerateFilePath(CaptureType.Gif);
            var directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var bytes = await EncodeGifAsync(frames).ConfigureAwait(false);
            await File.WriteAllBytesAsync(path, bytes).ConfigureAwait(false);

            RecordingCompleted?.Invoke(this, path);
            return path;
        }
        finally
        {
            Interlocked.Exchange(ref _stopping, 0);
            _gate.Release();
        }
    }

    private async Task<byte[]> EncodeGifAsync(List<CapturedFrame> frames)
    {
        var first = frames[0];
        var maxWidth = Math.Max(16, _settings.GifMaxWidth);

        uint scaledWidth = (uint)first.Width;
        uint scaledHeight = (uint)first.Height;
        if (first.Width > maxWidth)
        {
            var scale = (double)maxWidth / first.Width;
            scaledWidth = (uint)maxWidth;
            scaledHeight = (uint)Math.Max(1, Math.Round(first.Height * scale));
        }

        var delayHundredths = (ushort)Math.Clamp(Math.Round(100.0 / _fps), 2, 65535);

        using var stream = new InMemoryRandomAccessStream();
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.GifEncoderId, stream);

        // Infinite-loop application extension (NETSCAPE2.0).
        try
        {
            var loopProps = new BitmapPropertySet
            {
                { "/appext/application", new BitmapTypedValue(Encoding.ASCII.GetBytes("NETSCAPE2.0"), PropertyType.UInt8Array) },
                { "/appext/data", new BitmapTypedValue(new byte[] { 3, 1, 0, 0, 0 }, PropertyType.UInt8Array) },
            };
            await encoder.BitmapProperties.SetPropertiesAsync(loopProps);
        }
        catch
        {
            // Loop metadata is best-effort; a non-looping GIF is still valid.
        }

        for (int i = 0; i < frames.Count; i++)
        {
            if (i > 0)
            {
                await encoder.GoToNextFrameAsync();
            }

            var frame = frames[i];
            encoder.SetPixelData(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Ignore,
                (uint)frame.Width,
                (uint)frame.Height,
                96.0,
                96.0,
                frame.BgraPixels);

            if (scaledWidth != (uint)frame.Width || scaledHeight != (uint)frame.Height)
            {
                encoder.BitmapTransform.ScaledWidth = scaledWidth;
                encoder.BitmapTransform.ScaledHeight = scaledHeight;
                encoder.BitmapTransform.InterpolationMode = BitmapInterpolationMode.Fant;
            }

            var delayProps = new BitmapPropertySet
            {
                { "/grctlext/Delay", new BitmapTypedValue(delayHundredths, PropertyType.UInt16) },
            };
            await encoder.BitmapProperties.SetPropertiesAsync(delayProps);
        }

        await encoder.FlushAsync();

        stream.Seek(0);
        var size = (uint)stream.Size;
        using var reader = new DataReader(stream.GetInputStreamAt(0));
        await reader.LoadAsync(size);
        var result = new byte[size];
        reader.ReadBytes(result);
        return result;
    }
}
