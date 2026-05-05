using LocalWhisper.Windows.Models;

namespace LocalWhisper.Windows.Services;

public sealed class WhisperService
{
    private readonly WhisperServerWorker _worker;

    public WhisperService(WhisperServerWorker? worker = null)
    {
        _worker = worker ?? new WhisperServerWorker();
    }

    public async Task WarmupAsync(string cliBinaryPath, string modelPath, PerformancePreset preset, CancellationToken cancellationToken)
    {
        var serverPath = ServerBinaryForCliPath(cliBinaryPath);
        await _worker.EnsureRunningAsync(serverPath, modelPath, preset, cancellationToken);
    }

    public async Task<string> TranscribeAsync(
        string audioPath,
        string cliBinaryPath,
        string modelPath,
        string language,
        PerformancePreset preset,
        CancellationToken cancellationToken)
    {
        var serverPath = ServerBinaryForCliPath(cliBinaryPath);
        await _worker.EnsureRunningAsync(serverPath, modelPath, preset, cancellationToken);
        return await _worker.TranscribeAsync(audioPath, language, cancellationToken);
    }

    public Task ShutdownAsync() => _worker.StopAsync();

    public static string ServerBinaryForCliPath(string cliBinaryPath)
    {
        var directory = Path.GetDirectoryName(cliBinaryPath);
        if (string.IsNullOrWhiteSpace(directory))
        {
            return "whisper-server.exe";
        }

        return Path.Combine(directory, "whisper-server.exe");
    }
}
