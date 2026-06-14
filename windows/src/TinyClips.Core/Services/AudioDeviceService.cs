using NAudio.CoreAudioApi;

namespace TinyClips.Core.Services;

/// <summary>A capturable audio input device (microphone).</summary>
public readonly record struct AudioInputDevice(string Id, string Name);

/// <summary>Enumerates microphone (capture) devices for the settings UI.</summary>
public interface IAudioDeviceService
{
    /// <summary>
    /// Returns the active capture devices. The first entry is always the "system default"
    /// sentinel (empty id) so the user can defer to whatever Windows picks.
    /// </summary>
    IReadOnlyList<AudioInputDevice> GetMicrophones();
}

/// <inheritdoc />
public sealed class AudioDeviceService : IAudioDeviceService
{
    public IReadOnlyList<AudioInputDevice> GetMicrophones()
    {
        var devices = new List<AudioInputDevice> { new(string.Empty, "System default") };

        try
        {
            using var enumerator = new MMDeviceEnumerator();
            foreach (var device in enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active))
            {
                try
                {
                    devices.Add(new AudioInputDevice(device.ID, device.FriendlyName));
                }
                finally
                {
                    device.Dispose();
                }
            }
        }
        catch
        {
            // Enumeration can fail on machines without audio hardware; the default entry is enough.
        }

        return devices;
    }
}
