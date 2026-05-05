namespace LocalWhisper.Windows.Models;

public sealed record AudioDeviceInfo(string Id, string Label)
{
    public override string ToString() => Label;
}
