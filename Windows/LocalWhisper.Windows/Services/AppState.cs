using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using LocalWhisper.Windows.Models;
using LocalWhisper.Windows.Views;

namespace LocalWhisper.Windows.Services;

public sealed class AppState : INotifyPropertyChanged
{
    private readonly AppSettings _settings;
    private readonly HudWindow _hudWindow;
    private readonly AudioRecorderService _audioRecorder = new();
    private readonly WhisperService _whisperService = new();
    private readonly ClipboardService _clipboardService = new();
    private readonly PasteService _pasteService = new();
    private readonly PushToTalkService _pushToTalkService = new();
    private readonly ModelDownloader _modelDownloader = new();
    private readonly SemaphoreSlim _recordingLock = new(1, 1);
    private CancellationTokenSource? _warmupCts;
    private CancellationTokenSource? _transcribeCts;
    private bool _isPushToTalkHeld;
    private bool _isStartingPushToTalkRecording;
    private bool _didAbort;
    private TranscriptionStatus _status = TranscriptionStatus.Idle;
    private string _lastTranscript = "";
    private string? _lastError;
    private string _statusMessage = "Idle";
    private bool _isWarmingUp;
    private bool _isServerReady;
    private string? _lastFailedAudioPath;

    public AppState(SettingsStore settingsStore, HudWindow hudWindow)
    {
        _settings = settingsStore.Settings;
        _hudWindow = hudWindow;
        _audioRecorder.PreferredDeviceId = _settings.PreferredMicId;
        _audioRecorder.LevelChanged += (_, level) => _hudWindow.UpdateLevel(level);
        _settings.PropertyChanged += SettingsOnPropertyChanged;
        SoundService.Shared.IsEnabled = _settings.PlaySounds;
        _ = StartupService.SetEnabled(_settings.LaunchAtLogin);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public AppSettings Settings => _settings;

    public ModelDownloader ModelDownloader => _modelDownloader;

    public TranscriptionStatus Status
    {
        get => _status;
        private set => SetField(ref _status, value);
    }

    public string LastTranscript
    {
        get => _lastTranscript;
        private set => SetField(ref _lastTranscript, value);
    }

    public string? LastError
    {
        get => _lastError;
        private set => SetField(ref _lastError, value);
    }

    public string StatusMessage
    {
        get => _statusMessage;
        private set => SetField(ref _statusMessage, value);
    }

    public bool IsWarmingUp
    {
        get => _isWarmingUp;
        private set => SetField(ref _isWarmingUp, value);
    }

    public bool IsServerReady
    {
        get => _isServerReady;
        private set => SetField(ref _isServerReady, value);
    }

    public async Task StartAsync()
    {
        ApplyPushToTalkTrigger();
        StartPushToTalk();
        await _audioRecorder.PrewarmAsync();
        ScheduleWarmup();
    }

    public void StartPushToTalk()
    {
        try
        {
            _pushToTalkService.Start(
                onPress: () => _ = BeginPushToTalkRecordingAsync(),
                onRelease: () => _ = EndPushToTalkRecordingAsync(),
                onEscape: AbortInProgress);
            LastError = null;
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
            StatusMessage = "Global hotkey unavailable";
        }
    }

    public void ResetPushToTalk()
    {
        _pushToTalkService.Stop();
        ApplyPushToTalkTrigger();
        StartPushToTalk();
    }

    public void ScheduleWarmup()
    {
        _warmupCts?.Cancel();
        _warmupCts = new CancellationTokenSource();
        var token = _warmupCts.Token;
        IsWarmingUp = true;
        IsServerReady = false;
        StatusMessage = "Loading Whisper model";

        _ = Task.Run(async () =>
        {
            try
            {
                await _whisperService.WarmupAsync(
                    _settings.WhisperBinaryPath,
                    _settings.ModelPath,
                    _settings.PerformancePreset,
                    token);

                await DispatchAsync(() =>
                {
                    IsWarmingUp = false;
                    IsServerReady = true;
                    StatusMessage = "Ready";
                    LastError = null;
                });
            }
            catch (OperationCanceledException)
            {
            }
            catch (Exception ex)
            {
                await DispatchAsync(() =>
                {
                    IsWarmingUp = false;
                    IsServerReady = false;
                    LastError = $"Warmup failed: {ex.Message}";
                    StatusMessage = "Warmup failed";
                });
            }
        }, token);
    }

    public async Task RestartPipelineAsync()
    {
        if (Status is TranscriptionStatus.Recording or TranscriptionStatus.Transcribing)
        {
            return;
        }

        await _audioRecorder.RestartAsync();
        await _whisperService.ShutdownAsync();
        ScheduleWarmup();
    }

    public async Task<float> RunMicLevelTestAsync(TimeSpan duration)
    {
        try
        {
            return await _audioRecorder.QuickLevelTestAsync(duration);
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
            return -160;
        }
    }

    public async Task DownloadDefaultModelAsync()
    {
        try
        {
            var path = await _modelDownloader.DownloadLargeV3TurboAsync(CancellationToken.None);
            _settings.ModelPath = path;
            _settings.HasCompletedOnboarding = true;
            ScheduleWarmup();
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
        }
    }

    public void CopyLastTranscript()
    {
        if (!string.IsNullOrWhiteSpace(LastTranscript))
        {
            _clipboardService.Copy(LastTranscript);
        }
    }

    public void AbortInProgress()
    {
        if (Status is not (TranscriptionStatus.Recording or TranscriptionStatus.Transcribing))
        {
            return;
        }

        _isPushToTalkHeld = false;
        _isStartingPushToTalkRecording = false;
        SoundService.Shared.PlayStopListening();

        if (Status == TranscriptionStatus.Recording)
        {
            try
            {
                var audioPath = _audioRecorder.StopRecording();
                TryDelete(audioPath);
            }
            catch
            {
            }

            Status = TranscriptionStatus.Idle;
            StatusMessage = "Idle";
            LastError = null;
            _hudWindow.HideHud();
            return;
        }

        _didAbort = true;
        _transcribeCts?.Cancel();
        Status = TranscriptionStatus.Idle;
        StatusMessage = "Idle";
        LastError = null;
        _hudWindow.HideHud();
        _ = Task.Run(async () =>
        {
            await _whisperService.ShutdownAsync();
            await DispatchAsync(ScheduleWarmup);
        });
    }

    public async Task ShutdownAsync()
    {
        _warmupCts?.Cancel();
        _transcribeCts?.Cancel();
        _pushToTalkService.Stop();
        await _whisperService.ShutdownAsync();
        WhisperServerWorker.TerminateAllRunningServers();
    }

    private async Task BeginPushToTalkRecordingAsync()
    {
        if (Status is TranscriptionStatus.Recording or TranscriptionStatus.Transcribing || _isStartingPushToTalkRecording)
        {
            return;
        }

        _isPushToTalkHeld = true;
        _isStartingPushToTalkRecording = true;

        try
        {
            await StartRecordingAsync();
            if (!_isPushToTalkHeld && Status == TranscriptionStatus.Recording)
            {
                await StopAndTranscribeAsync();
            }
        }
        finally
        {
            _isStartingPushToTalkRecording = false;
        }
    }

    private async Task EndPushToTalkRecordingAsync()
    {
        if (!_isPushToTalkHeld)
        {
            return;
        }

        _isPushToTalkHeld = false;
        if (Status == TranscriptionStatus.Recording)
        {
            await StopAndTranscribeAsync();
        }
    }

    private async Task StartRecordingAsync()
    {
        await _recordingLock.WaitAsync();
        try
        {
            LastError = null;
            LastTranscript = "";
            _didAbort = false;
            _ = await _audioRecorder.StartRecordingAsync();
            SoundService.Shared.PlayStartListening();
            Status = TranscriptionStatus.Recording;
            StatusMessage = "Recording";
            _hudWindow.ShowRecording();
        }
        catch (Exception ex)
        {
            Fail(ex);
        }
        finally
        {
            _recordingLock.Release();
        }
    }

    private async Task StopAndTranscribeAsync()
    {
        await _recordingLock.WaitAsync();
        string? audioPath = null;
        var transcribeSucceeded = false;

        try
        {
            audioPath = _audioRecorder.StopRecording();
            SoundService.Shared.PlayStopListening();
            Status = TranscriptionStatus.Transcribing;
            StatusMessage = "Transcribing";
            _hudWindow.ShowTranscribing();

            _transcribeCts?.Cancel();
            _transcribeCts = new CancellationTokenSource();
            var transcript = await _whisperService.TranscribeAsync(
                audioPath,
                _settings.WhisperBinaryPath,
                _settings.ModelPath,
                _settings.Language,
                _settings.PerformancePreset,
                _transcribeCts.Token);

            transcribeSucceeded = true;
            LastTranscript = transcript;
            _clipboardService.Copy(transcript);
            AccumulateTimeSaved(transcript, audioPath);

            string? pasteWarning = null;
            if (_settings.AutoPaste)
            {
                try
                {
                    await Task.Delay(150);
                    _pasteService.Paste();
                }
                catch (Exception ex)
                {
                    pasteWarning = $"Copied to clipboard. Paste failed: {ex.Message}";
                    LastError = pasteWarning;
                }
            }

            IsServerReady = true;
            Status = TranscriptionStatus.Completed;
            StatusMessage = pasteWarning ?? "Completed";
            _hudWindow.ShowCompleted(pasteWarning ?? Preview(transcript));
        }
        catch (OperationCanceledException) when (_didAbort)
        {
            Status = TranscriptionStatus.Idle;
            StatusMessage = "Idle";
            LastError = null;
            _hudWindow.HideHud();
        }
        catch (Exception ex)
        {
            if (_didAbort)
            {
                Status = TranscriptionStatus.Idle;
                StatusMessage = "Idle";
                LastError = null;
                _hudWindow.HideHud();
            }
            else
            {
                Fail(ex);
            }
        }
        finally
        {
            if (audioPath is not null)
            {
                if (transcribeSucceeded || _didAbort)
                {
                    TryDelete(audioPath);
                }
                else
                {
                    KeepAsLastFailedAudio(audioPath);
                }
            }

            _didAbort = false;
            _recordingLock.Release();
        }
    }

    private void Fail(Exception error)
    {
        var message = error.Message;
        LastError = message;
        Status = TranscriptionStatus.Failed;
        StatusMessage = "Failed";
        _hudWindow.ShowError(message);
    }

    private void SettingsOnPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(AppSettings.PreferredMicId):
                _audioRecorder.PreferredDeviceId = _settings.PreferredMicId;
                break;
            case nameof(AppSettings.PushToTalkTriggerId):
                ResetPushToTalk();
                break;
            case nameof(AppSettings.PerformancePresetId):
            case nameof(AppSettings.ModelPath):
                ScheduleWarmup();
                break;
            case nameof(AppSettings.PlaySounds):
                SoundService.Shared.IsEnabled = _settings.PlaySounds;
                break;
            case nameof(AppSettings.LaunchAtLogin):
                if (!StartupService.SetEnabled(_settings.LaunchAtLogin) && _settings.LaunchAtLogin)
                {
                    _settings.LaunchAtLogin = false;
                }
                break;
        }
    }

    private void ApplyPushToTalkTrigger()
    {
        _pushToTalkService.SetTrigger(PushToTalkTrigger.Find(_settings.PushToTalkTriggerId));
    }

    private void AccumulateTimeSaved(string transcript, string audioPath)
    {
        var words = transcript.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;
        if (words == 0)
        {
            return;
        }

        var audioDurationSeconds = 0.0;
        try
        {
            using var reader = new NAudio.Wave.AudioFileReader(audioPath);
            audioDurationSeconds = reader.TotalTime.TotalSeconds;
        }
        catch
        {
            // Stats are non-critical.
        }

        const double typingBaselineWordsPerMinute = 40;
        var savedSeconds = Math.Max(0, words / typingBaselineWordsPerMinute * 60 - audioDurationSeconds);
        _settings.TotalTimeSavedSeconds += savedSeconds;
    }

    private void KeepAsLastFailedAudio(string sourcePath)
    {
        TryDelete(_lastFailedAudioPath);
        var destination = Path.Combine(ProjectPaths.ApplicationSupportRoot, "last-failed.wav");
        try
        {
            File.Move(sourcePath, destination, overwrite: true);
            _lastFailedAudioPath = destination;
        }
        catch
        {
            TryDelete(sourcePath);
        }
    }

    private static void TryDelete(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
        }
    }

    private static string Preview(string transcript) =>
        transcript.Length <= 72 ? transcript : transcript[..72] + "...";

    private static Task DispatchAsync(Action action)
    {
        var dispatcher = Application.Current.Dispatcher;
        return dispatcher.InvokeAsync(action).Task;
    }

    private void SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return;
        }

        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
