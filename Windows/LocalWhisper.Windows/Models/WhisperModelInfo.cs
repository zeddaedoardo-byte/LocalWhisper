namespace LocalWhisper.Windows.Models;

public sealed record WhisperModelInfo(
    string Id,
    string FileName,
    string Label,
    int ApproxMb,
    Uri DownloadUrl)
{
    public static readonly WhisperModelInfo LargeV3 = new(
        "large-v3",
        "ggml-large-v3.bin",
        "Large V3 (3 GB, max accuracy)",
        3094,
        new Uri("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"));
}
