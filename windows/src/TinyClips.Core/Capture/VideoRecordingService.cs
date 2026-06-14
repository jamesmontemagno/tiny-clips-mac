using System.Runtime.InteropServices.WindowsRuntime;
using System.Threading.Channels;
using TinyClips.Core.Models;
using TinyClips.Core.Services;
using Windows.Media.Core;
using Windows.Media.MediaProperties;
using Windows.Media.Transcoding;

namespace TinyClips.Core.Capture;

/// <summary>
/// Productionized video recorder: a continuous WGC capture session pumps BGRA frames
/// into a bounded channel; a <see cref="MediaStreamSource"/> drains that channel on
/// demand and a hardware-accelerated <see cref="MediaTranscoder"/> writes H.264 MP4.
/// </summary>
public sealed class VideoRecordingService : IVideoRecordingService
{
    private readonly IMonitorService _monitors;
    private readonly IClipStorageService _storage;
    private readonly ICaptureSettings _settings;
    private readonly SemaphoreSlim _gate = new(1, 1);

    private ContinuousCaptureSession? _capture;
    private Channel<TimestampedFrame>? _channel;
    private Task? _transcodeTask;
    private FileStream? _fileStream;
    private string? _outputPath;
    private TimeSpan _frameDuration;
    private Timer? _limitTimer;
    private int _stopping;

    private MouseClickMonitor? _clickMonitor;
    private MouseClickOverlayStyle _clickStyle;
    private int _clickOriginX;
    private int _clickOriginY;
    private BrandingOverlayCompositor? _branding;

    private AudioCaptureService? _audio;
    private AudioStreamDescriptor? _audioDescriptor;
    private long _audioFramesRead;
    private volatile bool _audioEnding;

    public VideoRecordingService(
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

    public async Task StartAsync(CaptureTarget? target = null, PixelRect? region = null, double? timeLimitMinutesOverride = null, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (IsRecording)
            {
                throw new InvalidOperationException("A recording is already in progress.");
            }

            var captureTarget = target ?? CaptureTarget.Monitor(
                (_monitors.GetPrimaryMonitor()
                    ?? throw new InvalidOperationException("No monitor was found to record.")).HMonitor);

            var fps = Math.Clamp(_settings.VideoFrameRate, 1, 60);
            _frameDuration = TimeSpan.FromSeconds(1.0 / fps);

            try
            {
                _channel = Channel.CreateBounded<TimestampedFrame>(new BoundedChannelOptions(fps * 4)
                {
                    FullMode = BoundedChannelFullMode.DropWrite,
                    SingleReader = true,
                    SingleWriter = true,
                });

                _capture = new ContinuousCaptureSession(captureTarget, region, fps, includeCursor: true);
                _capture.FrameReady += OnFrameReady;
                _capture.Start();

                StartMouseClickOverlay(captureTarget, region);
                _branding = _settings.ShowBrandingOverlay ? new BrandingOverlayCompositor() : null;

                var width = _capture.OutputWidth;
                var height = _capture.OutputHeight;

                _outputPath = _storage.GenerateFilePath(CaptureType.Video);
                var directory = Path.GetDirectoryName(_outputPath);
                if (!string.IsNullOrEmpty(directory))
                {
                    Directory.CreateDirectory(directory);
                }

                _fileStream = new FileStream(_outputPath, FileMode.Create, FileAccess.ReadWrite, FileShare.Read);
                var randomAccessStream = _fileStream.AsRandomAccessStream();

                var profile = MediaEncodingProfile.CreateMp4(VideoEncodingQuality.HD1080p);
                profile.Audio = null;
                profile.Video.Width = (uint)width;
                profile.Video.Height = (uint)height;
                profile.Video.FrameRate.Numerator = (uint)fps;
                profile.Video.FrameRate.Denominator = 1;
                profile.Video.PixelAspectRatio.Numerator = 1;
                profile.Video.PixelAspectRatio.Denominator = 1;
                profile.Video.Bitrate = (uint)Math.Clamp((long)width * height * fps / 10, 2_000_000, 24_000_000);

                var videoProps = VideoEncodingProperties.CreateUncompressed(MediaEncodingSubtypes.Bgra8, (uint)width, (uint)height);
                videoProps.FrameRate.Numerator = (uint)fps;
                videoProps.FrameRate.Denominator = 1;

                var videoDescriptor = new VideoStreamDescriptor(videoProps);

                _audioEnding = false;
                _audioFramesRead = 0;
                StartAudioCapture();

                MediaStreamSource mediaStreamSource;
                if (_audioDescriptor is not null)
                {
                    profile.Audio = AudioEncodingProperties.CreateAac(AudioCaptureService.SampleRate, AudioCaptureService.Channels, 192_000);
                    mediaStreamSource = new MediaStreamSource(videoDescriptor, _audioDescriptor) { BufferTime = TimeSpan.Zero };
                }
                else
                {
                    mediaStreamSource = new MediaStreamSource(videoDescriptor) { BufferTime = TimeSpan.Zero };
                }

                mediaStreamSource.Starting += (_, args) => args.Request.SetActualStartPosition(TimeSpan.Zero);
                mediaStreamSource.SampleRequested += OnSampleRequested;

                var transcoder = new MediaTranscoder { HardwareAccelerationEnabled = true };
                var prepare = await transcoder
                    .PrepareMediaStreamSourceTranscodeAsync(mediaStreamSource, randomAccessStream, profile)
                    .AsTask(cancellationToken)
                    .ConfigureAwait(false);

                if (!prepare.CanTranscode)
                {
                    throw new InvalidOperationException($"Cannot encode video: {prepare.FailureReason}.");
                }

                _transcodeTask = prepare.TranscodeAsync().AsTask();
                IsRecording = true;

                var limitMinutes = timeLimitMinutesOverride ?? _settings.VideoRecordingTimeLimitMinutes;
                if (limitMinutes > 0)
                {
                    _limitTimer = new Timer(
                        _ => _ = StopAsync(),
                        null,
                        TimeSpan.FromMinutes(limitMinutes),
                        Timeout.InfiniteTimeSpan);
                }
            }
            catch
            {
                CleanupFailedStart();
                throw;
            }
        }
        finally
        {
            _gate.Release();
        }
    }

    private void OnFrameReady(CapturedFrame frame, TimeSpan pts)
    {
        DrawClickOverlay(frame, pts);
        _branding?.Draw(frame.BgraPixels, frame.Width, frame.Height);
        _channel?.Writer.TryWrite(new TimestampedFrame(CreateBottomUpVideoBuffer(frame), pts));
    }

    private void StartMouseClickOverlay(CaptureTarget target, PixelRect? region)
    {
        // Mouse-click visuals only map reliably onto a (possibly cropped) monitor;
        // window targets move/resize, so skip them — matching the mac restriction.
        if (target.IsWindow || !_settings.ShouldShowMouseClickVisuals(CaptureType.Video))
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
        _clickStyle = _settings.MouseClickOverlayStyleFor(CaptureType.Video);
        _clickMonitor = new MouseClickMonitor();
        _clickMonitor.Start();
    }

    private void DrawClickOverlay(CapturedFrame frame, TimeSpan pts)
    {
        var monitor = _clickMonitor;
        if (monitor == null)
        {
            return;
        }

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

    private static byte[] CreateBottomUpVideoBuffer(CapturedFrame frame)
    {
        var rowStride = frame.Width * 4;
        var pixels = new byte[frame.BgraPixels.Length];

        // Media Foundation BGRA samples are bottom-up; WGC frames arrive top-down.
        for (var y = 0; y < frame.Height; y++)
        {
            Buffer.BlockCopy(
                frame.BgraPixels,
                (frame.Height - 1 - y) * rowStride,
                pixels,
                y * rowStride,
                rowStride);
        }

        return pixels;
    }

    private void CleanupFailedStart()
    {
        _limitTimer?.Dispose();
        _limitTimer = null;
        _clickMonitor?.Dispose();
        _clickMonitor = null;
        _branding = null;
        _capture?.Dispose();
        _capture = null;
        DisposeAudio();
        _channel?.Writer.TryComplete();
        _channel = null;
        _transcodeTask = null;
        _fileStream?.Dispose();
        _fileStream = null;

        if (!string.IsNullOrEmpty(_outputPath))
        {
            try
            {
                File.Delete(_outputPath);
            }
            catch
            {
                // Best-effort cleanup of the partial file.
            }
        }

        _outputPath = null;
        IsRecording = false;
    }

    private async void OnSampleRequested(MediaStreamSource sender, MediaStreamSourceSampleRequestedEventArgs args)
    {
        if (_audioDescriptor is not null && ReferenceEquals(args.Request.StreamDescriptor, _audioDescriptor))
        {
            HandleAudioRequest(args);
            return;
        }

        var channel = _channel;
        if (channel is null)
        {
            return;
        }

        var deferral = args.Request.GetDeferral();
        try
        {
            while (await channel.Reader.WaitToReadAsync().ConfigureAwait(false))
            {
                if (channel.Reader.TryRead(out var frame))
                {
                    var sample = MediaStreamSample.CreateFromBuffer(frame.Pixels.AsBuffer(), frame.Pts);
                    sample.Duration = _frameDuration;
                    args.Request.Sample = sample;
                    return;
                }
            }

            // Channel completed and drained -> signal end of stream.
            args.Request.Sample = null;
        }
        catch
        {
            args.Request.Sample = null;
        }
        finally
        {
            deferral.Complete();
        }
    }

    private void HandleAudioRequest(MediaStreamSourceSampleRequestedEventArgs args)
    {
        var audio = _audio;
        if (audio is null || _audioEnding)
        {
            // End the audio stream so the transcode can terminate.
            args.Request.Sample = null;
            return;
        }

        // ~20 ms of audio per chunk.
        const int frameCount = AudioCaptureService.SampleRate / 50;
        var data = audio.ReadChunk(frameCount);
        if (data is null || data.Length == 0)
        {
            args.Request.Sample = null;
            return;
        }

        var producedFrames = data.Length / (AudioCaptureService.Channels * (AudioCaptureService.BitsPerSample / 8));
        var pts = TimeSpan.FromTicks((long)(_audioFramesRead * TimeSpan.TicksPerSecond / AudioCaptureService.SampleRate));
        var duration = TimeSpan.FromTicks((long)(producedFrames * TimeSpan.TicksPerSecond / AudioCaptureService.SampleRate));
        _audioFramesRead += producedFrames;

        var sample = MediaStreamSample.CreateFromBuffer(data.AsBuffer(), pts);
        sample.Duration = duration;
        args.Request.Sample = sample;
    }

    private void StartAudioCapture()
    {
        var wantSystem = _settings.RecordAudio;
        var wantMic = _settings.RecordMicrophone;
        if (!wantSystem && !wantMic)
        {
            return;
        }

        try
        {
            var audio = new AudioCaptureService(wantSystem, wantMic, _settings.SelectedMicrophoneId);
            if (audio.TryStart())
            {
                _audio = audio;
                _audioDescriptor = new AudioStreamDescriptor(
                    AudioEncodingProperties.CreatePcm(AudioCaptureService.SampleRate, AudioCaptureService.Channels, AudioCaptureService.BitsPerSample));
            }
            else
            {
                audio.Dispose();
            }
        }
        catch
        {
            _audio = null;
            _audioDescriptor = null;
        }
    }

    private void DisposeAudio()
    {
        _audioEnding = true;
        _audio?.Dispose();
        _audio = null;
        _audioDescriptor = null;
    }


    public async Task<string?> StopAsync()
    {
        if (Interlocked.Exchange(ref _stopping, 1) == 1)
        {
            return _outputPath;
        }

        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (!IsRecording)
            {
                return null;
            }

            _limitTimer?.Dispose();
            _limitTimer = null;

            _clickMonitor?.Dispose();
            _clickMonitor = null;

            // Signal audio end-of-stream and stop the device before draining the encoder,
            // otherwise the continuous silence source would prevent EOS.
            _audioEnding = true;
            _audio?.Stop();

            // Stop new frames, then let the encoder drain what's buffered.
            _capture?.Stop();
            _channel?.Writer.TryComplete();

            if (_transcodeTask is not null)
            {
                try
                {
                    await _transcodeTask.ConfigureAwait(false);
                }
                catch
                {
                    // Surface nothing here; the file may still be partially valid.
                }
            }

            _capture?.Dispose();
            _capture = null;
            DisposeAudio();
            _fileStream?.Dispose();
            _fileStream = null;
            _channel = null;
            _transcodeTask = null;

            IsRecording = false;
            var path = _outputPath;
            RecordingCompleted?.Invoke(this, path);
            return path;
        }
        finally
        {
            Interlocked.Exchange(ref _stopping, 0);
            _gate.Release();
        }
    }

    private readonly record struct TimestampedFrame(byte[] Pixels, TimeSpan Pts);
}
