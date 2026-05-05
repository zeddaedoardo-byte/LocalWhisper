namespace LocalWhisper.Windows.Models;

public sealed record WhisperModelInfo(
    string Id,
    string FileName,
    string Label,
    int ApproxMb,
    Uri DownloadUrl)
{
    public static readonly WhisperModelInfo LargeV3Turbo = new(
        "large-v3-turbo",
        "ggml-large-v3-turbo.bin",
        "Large V3 Turbo (~1.5 GB, efficient default)",
        1574,
        new Uri("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"));
}
