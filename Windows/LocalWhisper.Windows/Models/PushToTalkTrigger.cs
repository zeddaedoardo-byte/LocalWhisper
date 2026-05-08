namespace LocalWhisper.Windows.Models;

public sealed record PushToTalkTrigger(string Id, string Label, IReadOnlySet<int> RequiredVirtualKeys)
{
    public static readonly PushToTalkTrigger LeftControl = new("left_control", "Left Ctrl", new HashSet<int> { 0xA2 });
    public static readonly PushToTalkTrigger RightControl = new("right_control", "Right Ctrl", new HashSet<int> { 0xA3 });
    public static readonly PushToTalkTrigger LeftAlt = new("left_alt", "Left Alt", new HashSet<int> { 0xA4 });
    public static readonly PushToTalkTrigger RightAlt = new("right_alt", "Right Alt", new HashSet<int> { 0xA5 });
    public static readonly PushToTalkTrigger LeftShift = new("left_shift", "Left Shift", new HashSet<int> { 0xA0 });
    public static readonly PushToTalkTrigger RightShift = new("right_shift", "Right Shift", new HashSet<int> { 0xA1 });
    public static readonly PushToTalkTrigger CtrlAlt = new("ctrl_alt", "Ctrl + Alt", new HashSet<int> { 0x11, 0x12 });
    public static readonly PushToTalkTrigger CtrlShift = new("ctrl_shift", "Ctrl + Shift", new HashSet<int> { 0x11, 0x10 });

    public static IReadOnlyList<PushToTalkTrigger> All { get; } =
    [
        LeftControl,
        RightControl,
        LeftAlt,
        RightAlt,
        LeftShift,
        RightShift,
        CtrlAlt,
        CtrlShift
    ];

    public static PushToTalkTrigger Find(string id) =>
        All.FirstOrDefault(t => string.Equals(t.Id, id, StringComparison.OrdinalIgnoreCase)) ?? LeftControl;

    /// <summary>
    /// Like <see cref="Find"/> but returns null for empty / unknown ids
    /// instead of falling back to <see cref="LeftControl"/>. Used by the
    /// optional lock-in trigger so a malformed setting silently disables
    /// the feature rather than enabling a hidden global hotkey.
    /// </summary>
    public static PushToTalkTrigger? FindOrNull(string? id)
    {
        if (string.IsNullOrWhiteSpace(id))
        {
            return null;
        }
        return All.FirstOrDefault(t => string.Equals(t.Id, id, StringComparison.OrdinalIgnoreCase));
    }
}
