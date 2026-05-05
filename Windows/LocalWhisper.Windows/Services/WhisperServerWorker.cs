using System.Diagnostics;
using System.Net.Http;
using LocalWhisper.Windows.Models;

namespace LocalWhisper.Windows.Services;

public sealed class WhisperServerWorker
{
    private static readonly object RegistryLock = new();
    private static readonly HashSet<Process> RunningServers = [];

    private readonly object _stateLock = new();
    private readonly string _host = "127.0.0.1";
    private readonly int _port;
    private Process? _process;
    private string? _currentBinary;
    private string? _currentModel;
    private PerformancePreset? _currentPreset;
    private Task? _readyTask;
    private readonly List<string> _stderrBuffer = [];

    public WhisperServerWorker(int port = 18642)
    {
        _port = port;
    }

    public bool IsRunning => _process?.HasExited == false;

    public static void TerminateAllRunningServers()
    {
        lock (RegistryLock)
        {
            foreach (var process in RunningServers.ToList())
            {
                try
                {
                    if (!process.HasExited)
                    {
                        process.Kill(entireProcessTree: true);
                    }
                }
                catch
                {
                    // Best-effort cleanup during process exit.
                }
            }

            RunningServers.Clear();
        }
    }

    public async Task EnsureRunningAsync(string serverBinaryPath, string modelPath, PerformancePreset preset, CancellationToken cancellationToken)
    {
        if (IsRunning &&
            string.Equals(_currentBinary, serverBinaryPath, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(_currentModel, modelPath, StringComparison.OrdinalIgnoreCase) &&
            Equals(_currentPreset, preset))
        {
            if (_readyTask is not null)
            {
                await _readyTask.WaitAsync(cancellationToken);
            }

            return;
        }

        await StopAsync();
        Start(serverBinaryPath, modelPath, preset);
        if (_readyTask is not null)
        {
            await _readyTask.WaitAsync(cancellationToken);
        }
    }

    public async Task<string> TranscribeAsync(string audioPath, string language, CancellationToken cancellationToken)
    {
        using var client = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
        using var form = new MultipartFormDataContent();
        await using var stream = File.OpenRead(audioPath);
        using var fileContent = new StreamContent(stream);

        form.Add(new StringContent(string.IsNullOrWhiteSpace(language) ? "auto" : language), "language");
        form.Add(new StringContent("text"), "response_format");
        form.Add(new StringContent("0.0"), "temperature");
        form.Add(new StringContent("0.2"), "temperature_inc");
        form.Add(fileContent, "file", Path.GetFileName(audioPath));

        var endpoint = $"http://{_host}:{_port}/inference";
        using var response = await client.PostAsync(endpoint, form, cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"Whisper server HTTP {(int)response.StatusCode}: {body}");
        }

        var text = body.Trim();
        if (text.Length == 0)
        {
            throw new InvalidOperationException("Transcription completed but produced empty text.");
        }

        return text;
    }

    public async Task StopAsync()
    {
        Process? process;
        lock (_stateLock)
        {
            process = _process;
            _process = null;
            _currentBinary = null;
            _currentModel = null;
            _currentPreset = null;
            _readyTask = null;
            _stderrBuffer.Clear();
        }

        if (process is null)
        {
            return;
        }

        await TerminateAsync(process);
        lock (RegistryLock)
        {
            RunningServers.Remove(process);
        }

        process.Dispose();
    }

    private void Start(string serverBinaryPath, string modelPath, PerformancePreset preset)
    {
        if (!File.Exists(serverBinaryPath))
        {
            throw new FileNotFoundException("whisper-server.exe was not found.", serverBinaryPath);
        }

        if (!File.Exists(modelPath))
        {
            throw new FileNotFoundException("Whisper model was not found.", modelPath);
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = serverBinaryPath,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        startInfo.ArgumentList.Add("-m");
        startInfo.ArgumentList.Add(modelPath);
        startInfo.ArgumentList.Add("--host");
        startInfo.ArgumentList.Add(_host);
        startInfo.ArgumentList.Add("--port");
        startInfo.ArgumentList.Add(_port.ToString());
        startInfo.ArgumentList.Add("-nt");
        startInfo.ArgumentList.Add("-fa");
        startInfo.ArgumentList.Add("-bs");
        startInfo.ArgumentList.Add(preset.BeamSize.ToString());
        startInfo.ArgumentList.Add("-bo");
        startInfo.ArgumentList.Add(preset.BestOf.ToString());
        startInfo.ArgumentList.Add("-ac");
        startInfo.ArgumentList.Add(preset.AudioContext.ToString());

        var vadPath = Path.Combine(Path.GetDirectoryName(modelPath) ?? "", "ggml-silero-v5.1.2.bin");
        if (File.Exists(vadPath))
        {
            startInfo.ArgumentList.Add("--vad");
            startInfo.ArgumentList.Add("--vad-model");
            startInfo.ArgumentList.Add(vadPath);
        }

        var process = new Process
        {
            StartInfo = startInfo,
            EnableRaisingEvents = true
        };

        process.OutputDataReceived += (_, e) =>
        {
            _ = e.Data;
        };
        process.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is null)
            {
                return;
            }

            lock (_stateLock)
            {
                _stderrBuffer.Add(e.Data);
                if (_stderrBuffer.Count > 200)
                {
                    _stderrBuffer.RemoveAt(0);
                }
            }
        };

        if (!process.Start())
        {
            throw new InvalidOperationException("Could not start whisper-server.exe.");
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        lock (RegistryLock)
        {
            RunningServers.Add(process);
        }

        lock (_stateLock)
        {
            _process = process;
            _currentBinary = serverBinaryPath;
            _currentModel = modelPath;
            _currentPreset = preset;
            _readyTask = PollReadyAsync(process, TimeSpan.FromMinutes(10));
        }
    }

    private async Task PollReadyAsync(Process process, TimeSpan timeout)
    {
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(2) };
        var deadline = DateTimeOffset.UtcNow.Add(timeout);
        var endpoint = $"http://{_host}:{_port}/";

        while (DateTimeOffset.UtcNow < deadline)
        {
            if (process.HasExited)
            {
                throw new InvalidOperationException($"Whisper server exited before ready: {StderrSnapshot()}");
            }

            try
            {
                using var response = await client.GetAsync(endpoint);
                if ((int)response.StatusCode < 500)
                {
                    return;
                }
            }
            catch
            {
                // Server is not listening yet.
            }

            await Task.Delay(TimeSpan.FromSeconds(1));
        }

        throw new TimeoutException("Whisper server failed to start within 10 minutes.");
    }

    private string StderrSnapshot()
    {
        lock (_stateLock)
        {
            return string.Join(Environment.NewLine, _stderrBuffer);
        }
    }

    private static async Task TerminateAsync(Process process)
    {
        if (process.HasExited)
        {
            return;
        }

        try
        {
            process.CloseMainWindow();
            await WaitForExitAsync(process, TimeSpan.FromSeconds(2));
            if (process.HasExited)
            {
                return;
            }

            process.Kill(entireProcessTree: true);
            await WaitForExitAsync(process, TimeSpan.FromSeconds(5));
        }
        catch
        {
            // Nothing useful to do during shutdown; the next start will replace the worker.
        }
    }

    private static async Task WaitForExitAsync(Process process, TimeSpan timeout)
    {
        using var cts = new CancellationTokenSource(timeout);
        try
        {
            await process.WaitForExitAsync(cts.Token);
        }
        catch (OperationCanceledException)
        {
        }
    }
}
