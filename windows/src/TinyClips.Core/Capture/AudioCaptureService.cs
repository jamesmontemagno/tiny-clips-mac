using NAudio.CoreAudioApi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace TinyClips.Core.Capture;

/// <summary>
/// Captures microphone and/or desktop (system "loopback") audio with WASAPI, mixes the
/// enabled sources into a single 48 kHz / 16-bit / stereo PCM stream and exposes it as a
/// pull source. <see cref="ReadChunk"/> always returns a full, silence-padded buffer so the
/// muxing <see cref="Windows.Media.Core.MediaStreamSource"/> never starves while a recording
/// is in progress. Used to add an audio track to the video recorder's MP4 transcode.
/// </summary>
public sealed class AudioCaptureService : IDisposable
{
    public const int SampleRate = 48000;
    public const int Channels = 2;
    public const int BitsPerSample = 16;

    private readonly bool _captureSystem;
    private readonly bool _captureMic;
    private readonly string? _micDeviceId;
    private readonly object _gate = new();

    private WasapiLoopbackCapture? _loopback;
    private WasapiCapture? _mic;
    private MixingSampleProvider? _mixer;
    private IWaveProvider? _output;
    private bool _disposed;

    public AudioCaptureService(bool captureSystem, bool captureMic, string? micDeviceId)
    {
        _captureSystem = captureSystem;
        _captureMic = captureMic;
        _micDeviceId = micDeviceId;
    }

    /// <summary>True once at least one requested source started successfully.</summary>
    public bool IsActive { get; private set; }

    /// <summary>
    /// Starts the requested capture sources. Each source is best-effort: if the microphone
    /// is denied or a device is missing, the other source still records. Returns true if any
    /// source started.
    /// </summary>
    public bool TryStart()
    {
        _mixer = new MixingSampleProvider(WaveFormat.CreateIeeeFloatWaveFormat(SampleRate, Channels))
        {
            ReadFully = true,
        };

        if (_captureSystem)
        {
            TryStartSource(isLoopback: true);
        }

        if (_captureMic)
        {
            TryStartSource(isLoopback: false);
        }

        if (!IsActive)
        {
            return false;
        }

        _output = new SampleToWaveProvider16(_mixer);
        return true;
    }

    private void TryStartSource(bool isLoopback)
    {
        try
        {
            WasapiCapture capture = isLoopback
                ? new WasapiLoopbackCapture()
                : CreateMicCapture();

            var buffer = new BufferedWaveProvider(capture.WaveFormat)
            {
                ReadFully = true,
                DiscardOnBufferOverflow = true,
                BufferDuration = TimeSpan.FromSeconds(5),
            };

            capture.DataAvailable += (_, e) =>
            {
                if (e.BytesRecorded > 0)
                {
                    buffer.AddSamples(e.Buffer, 0, e.BytesRecorded);
                }
            };

            var provider = ToStereo48k(buffer.ToSampleProvider());
            _mixer!.AddMixerInput(provider);

            capture.StartRecording();

            if (isLoopback)
            {
                _loopback = (WasapiLoopbackCapture)capture;
            }
            else
            {
                _mic = capture;
            }

            IsActive = true;
        }
        catch
        {
            // Best-effort: a missing/denied device simply means that source is skipped.
        }
    }

    private WasapiCapture CreateMicCapture()
    {
        if (!string.IsNullOrEmpty(_micDeviceId))
        {
            using var enumerator = new MMDeviceEnumerator();
            var device = enumerator.GetDevice(_micDeviceId);
            return new WasapiCapture(device);
        }

        return new WasapiCapture();
    }

    /// <summary>
    /// Coerces an arbitrary capture source to 48 kHz stereo float so it can feed the mixer.
    /// </summary>
    private static ISampleProvider ToStereo48k(ISampleProvider source)
    {
        if (source.WaveFormat.SampleRate != SampleRate)
        {
            source = new WdlResamplingSampleProvider(source, SampleRate);
        }

        return source.WaveFormat.Channels switch
        {
            1 => new MonoToStereoSampleProvider(source),
            2 => source,
            _ => SelectFirstTwoChannels(source),
        };
    }

    private static ISampleProvider SelectFirstTwoChannels(ISampleProvider source)
    {
        var multiplexer = new MultiplexingSampleProvider(new[] { source }, Channels);
        multiplexer.ConnectInputToOutput(0, 0);
        multiplexer.ConnectInputToOutput(1, 1);
        return multiplexer;
    }

    /// <summary>
    /// Reads up to <paramref name="frameCount"/> frames (samples per channel) of mixed audio
    /// as interleaved 16-bit stereo PCM. Returns a silence-padded full buffer while active.
    /// </summary>
    public byte[]? ReadChunk(int frameCount)
    {
        lock (_gate)
        {
            if (_disposed || _output is null)
            {
                return null;
            }

            var bytesWanted = frameCount * Channels * (BitsPerSample / 8);
            var buffer = new byte[bytesWanted];
            var read = _output.Read(buffer, 0, bytesWanted);
            if (read <= 0)
            {
                return null;
            }

            if (read < bytesWanted)
            {
                Array.Resize(ref buffer, read);
            }

            return buffer;
        }
    }

    public void Stop()
    {
        try
        {
            _loopback?.StopRecording();
        }
        catch
        {
            // Ignore stop failures during teardown.
        }

        try
        {
            _mic?.StopRecording();
        }
        catch
        {
            // Ignore stop failures during teardown.
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        lock (_gate)
        {
            _disposed = true;
        }

        Stop();
        _loopback?.Dispose();
        _loopback = null;
        _mic?.Dispose();
        _mic = null;
        _output = null;
        _mixer = null;
    }
}
