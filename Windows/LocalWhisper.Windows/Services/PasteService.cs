using LocalWhisper.Windows.Interop;

namespace LocalWhisper.Windows.Services;

public sealed class PasteService
{
    public void Paste()
    {
        var inputs = NativeMethods.BuildCtrlVInputs();
        var sent = NativeMethods.SendInput((uint)inputs.Length, inputs, NativeMethods.InputSize);
        if (sent != inputs.Length)
        {
            throw new InvalidOperationException("Could not send Ctrl+V to the active window.");
        }
    }
}
