using LocalWhisper.Windows.Models;
using NAudio.CoreAudioApi;

namespace LocalWhisper.Windows.Services;

public static class AudioDeviceCatalog
{
    public static IReadOnlyList<AudioDeviceInfo> ListInputDevices()
    {
        using var enumerator = new MMDeviceEnumerator();
        return enumerator
            .EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active)
            .Select(device => new AudioDeviceInfo(device.ID, device.FriendlyName))
            .ToList();
    }

    public static MMDevice? FindInputDevice(string? id)
    {
        using var enumerator = new MMDeviceEnumerator();
        if (!string.IsNullOrWhiteSpace(id))
        {
            foreach (var device in enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active))
            {
                if (string.Equals(device.ID, id, StringComparison.OrdinalIgnoreCase))
                {
                    return device;
                }

                device.Dispose();
            }
        }

        try
        {
            return enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Communications);
        }
        catch
        {
            return enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
        }
    }
}
