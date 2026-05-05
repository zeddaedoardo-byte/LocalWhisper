using NAudio.MediaFoundation;
using NAudio.Wave;

namespace LocalWhisper.Windows.Services;

public sealed class AudioRecorderService : IDisposable
{
    private readonly object _lock = new();
    private WasapiCapture? _capture;
    private MemoryStream? _rawAudio;
    private WaveFormat? _captureFormat;
    private ManualResetEventSlim? _recordingStopped;
    private string? _currentFilePath;
    private bool _isRecording;

    static AudioRecorderService()
    {
        MediaFoundationApi.Startup();
    }

    public event EventHandler<float>? LevelChanged;

    public string? PreferredDeviceId { get; set; }

    public Task PrewarmAsync()
    {
        _ = AudioDeviceCatalog.ListInputDevices();
        return Task.CompletedTask;
    }

    public Task RestartAsync()
    {
        if (_isRecording)
        {
            return Task.CompletedTask;
        }

        DisposeCapture();
        return PrewarmAsync();
    }

    public Task<string> StartRecordingAsync()
    {
        lock (_lock)
        {
            if (_isRecording)
            {
                throw new InvalidOperationException("A recording is already active.");
            }

            var device = AudioDeviceCatalog.FindInputDevice(PreferredDeviceId)
                ?? throw new InvalidOperationException("No active microphone input device was found.");

            var capture = new WasapiCapture(device);
            _rawAudio = new MemoryStream();
            _captureFormat = capture.WaveFormat;
            _recordingStopped = new ManualResetEventSlim(false);
            _currentFilePath = Path.Combine(Path.GetTempPath(), $"local-whisper-{Guid.NewGuid():N}.wav");
            _isRecording = true;

            capture.DataAvailable += CaptureOnDataAvailable;
            capture.RecordingStopped += CaptureOnRecordingStopped;
            _capture = capture;
            capture.StartRecording();
            return Task.FromResult(_currentFilePath);
        }
    }

    public string StopRecording()
    {
        WasapiCapture? capture;
        ManualResetEventSlim? stopped;
        MemoryStream? rawAudio;
        WaveFormat? captureFormat;
        string? filePath;

        lock (_lock)
        {
            if (!_isRecording || _capture is null || _rawAudio is null || _captureFormat is null || _currentFilePath is null)
            {
                throw new InvalidOperationException("There is no active recording to stop.");
            }

            _isRecording = false;
            capture = _capture;
            stopped = _recordingStopped;
            rawAudio = _rawAudio;
            captureFormat = _captureFormat;
            filePath = _currentFilePath;
        }

        capture.StopRecording();
        stopped?.Wait(TimeSpan.FromSeconds(3));

        lock (_lock)
        {
            rawAudio.Position = 0;
            WriteWavFile(rawAudio, captureFormat, filePath);
            LevelChanged?.Invoke(this, -160);
            DisposeCapture();
        }

        return filePath;
    }

    public async Task<float> QuickLevelTestAsync(TimeSpan duration)
    {
        await StartRecordingAsync();
        var peak = -160f;
        void Handler(object? _, float level) => peak = Math.Max(peak, level);
        LevelChanged += Handler;
        try
        {
            await Task.Delay(duration);
            _ = StopRecording();
            return peak;
        }
        finally
        {
            LevelChanged -= Handler;
        }
    }

    public void Dispose()
    {
        DisposeCapture();
    }

    private void CaptureOnDataAvailable(object? sender, WaveInEventArgs e)
    {
        lock (_lock)
        {
            if (!_isRecording || _rawAudio is null || _captureFormat is null)
            {
                return;
            }

            _rawAudio.Write(e.Buffer, 0, e.BytesRecorded);
            LevelChanged?.Invoke(this, PeakDb(e.Buffer, e.BytesRecorded, _captureFormat));
        }
    }

    private void CaptureOnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        _recordingStopped?.Set();
    }

    private static void WriteWavFile(Stream rawAudio, WaveFormat sourceFormat, string filePath)
    {
        using var source = new RawSourceWaveStream(rawAudio, sourceFormat);
        using var resampler = new MediaFoundationResampler(source, new WaveFormat(16_000, 16, 1))
        {
            ResamplerQuality = 60
        };
        WaveFileWriter.CreateWaveFile(filePath, resampler);
    }

    private static float PeakDb(byte[] buffer, int bytesRecorded, WaveFormat format)
    {
        var maxAbs = 0f;

        if (format.Encoding == WaveFormatEncoding.IeeeFloat && format.BitsPerSample == 32)
        {
            for (var offset = 0; offset + 4 <= bytesRecorded; offset += 4)
            {
                var sample = BitConverter.ToSingle(buffer, offset);
                maxAbs = Math.Max(maxAbs, Math.Abs(sample));
            }
        }
        else if (format.Encoding == WaveFormatEncoding.Pcm && format.BitsPerSample == 16)
        {
            for (var offset = 0; offset + 2 <= bytesRecorded; offset += 2)
            {
                var sample = BitConverter.ToInt16(buffer, offset) / 32768f;
                maxAbs = Math.Max(maxAbs, Math.Abs(sample));
            }
        }
        else
        {
            for (var offset = 0; offset < bytesRecorded; offset++)
            {
                var sample = Math.Abs((buffer[offset] - 128) / 128f);
                maxAbs = Math.Max(maxAbs, sample);
            }
        }

        return maxAbs <= 0 ? -160 : 20f * MathF.Log10(maxAbs);
    }

    private void DisposeCapture()
    {
        if (_capture is not null)
        {
            _capture.DataAvailable -= CaptureOnDataAvailable;
            _capture.RecordingStopped -= CaptureOnRecordingStopped;
            _capture.Dispose();
        }

        _capture = null;
        _rawAudio?.Dispose();
        _rawAudio = null;
        _captureFormat = null;
        _recordingStopped?.Dispose();
        _recordingStopped = null;
        _currentFilePath = null;
        _isRecording = false;
    }
}
