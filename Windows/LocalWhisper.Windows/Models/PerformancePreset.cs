namespace LocalWhisper.Windows.Models;

public sealed record PerformancePreset(
    string Id,
    string Label,
    string Description,
    int BeamSize,
    int BestOf,
    int AudioContext)
{
    public static readonly PerformancePreset Quality = new(
        "quality",
        "Quality (most accurate)",
        "Uses a wider decoder search. Slower, but best for noisy or accented speech.",
        beamSize: 5,
        bestOf: 5,
        audioContext: 0);

    public static readonly PerformancePreset Balanced = new(
        "balanced",
        "Balanced",
        "Good accuracy with lower latency for everyday dictation.",
        beamSize: 2,
        bestOf: 2,
        audioContext: 0);

    public static readonly PerformancePreset Speed = new(
        "speed",
        "Speed (fastest)",
        "Minimizes decoder work while keeping the full audio context.",
        beamSize: 1,
        bestOf: 1,
        audioContext: 0);

    public static IReadOnlyList<PerformancePreset> All { get; } = [Quality, Balanced, Speed];

    public static PerformancePreset? Find(string id) =>
        All.FirstOrDefault(p => string.Equals(p.Id, id, StringComparison.OrdinalIgnoreCase));
}
