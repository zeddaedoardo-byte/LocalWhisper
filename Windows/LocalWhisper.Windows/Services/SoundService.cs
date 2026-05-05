using System.Media;

namespace LocalWhisper.Windows.Services;

public sealed class SoundService
{
    public static SoundService Shared { get; } = new();

    private SoundService()
    {
    }

    public bool IsEnabled { get; set; } = true;

    public void PlayStartListening()
    {
        if (IsEnabled)
        {
            SystemSounds.Asterisk.Play();
        }
    }

    public void PlayStopListening()
    {
        if (IsEnabled)
        {
            SystemSounds.Beep.Play();
        }
    }
}
