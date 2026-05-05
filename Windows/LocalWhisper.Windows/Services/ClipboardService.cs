using System.Windows;

namespace LocalWhisper.Windows.Services;

public sealed class ClipboardService
{
    public void Copy(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return;
        }

        Clipboard.SetText(text, TextDataFormat.UnicodeText);
    }
}
