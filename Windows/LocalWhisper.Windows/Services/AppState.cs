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
    private readonly SilenceWatchdog _silenceWatchdog = new();
    private readonly ModelDownloader _modelDownloader = new();
    private readonly SemaphoreSlim _recordingLock = new(1, 1);
    private CancellationTokenSource? _warmupCts;
    private CancellationTokenSource? _transcribeCts;
    private bool _isPushToTalkHeld;
    private bool _isStartingPushToTalkRecording;
    private bool _didAbort;
    private enum PttMode { Idle, Hold, Continuous }
    private PttMode _pttMode = PttMode.Idle;
    /// <summary>
    /// True while a continuous-mode start is awaiting the audio engine.
    /// A second lock press during this window flips
    /// <see cref="_continuousStartCancelled"/> so the post-start code
    /// discards the recording instead of entering continuous mode.
    /// </summary>
    private bool _continuousStartInFlight;
    private bool _continuousStartCancelled;
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
        ApplyLockTrigger();
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
                onEscape: AbortInProgress,
                onLockToggle: () => _ = ToggleContinuousLockAsync());
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
        _silenceWatchdog.Stop();
        _pttMode = PttMode.Idle;
        ApplyPushToTalkTrigger();
        ApplyLockTrigger();
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
        _silenceWatchdog.Stop();
        _pttMode = PttMode.Idle;
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
        _silenceWatchdog.Stop();
        _pushToTalkService.Stop();
        await _whisperService.ShutdownAsync();
        WhisperServerWorker.TerminateAllRunningServers();
    }

    private async Task BeginPushToTalkRecordingAsync()
    {
        // While continuous mode is active, the primary trigger acts as an
        // explicit stop. This is the user's escape hatch when the silence
        // watchdog doesn't trigger (noisy environment) or when they got
        // into continuous unintentionally via the lock combo.
        if (_pttMode == PttMode.Continuous)
        {
            await StopContinuousAndTranscribeAsync();
            return;
        }

        if (Status is TranscriptionStatus.Recording or TranscriptionStatus.Transcribing || _isStartingPushToTalkRecording)
        {
            return;
        }

        _isPushToTalkHeld = true;
        _isStartingPushToTalkRecording = true;
        _pttMode = PttMode.Hold;

        try
        {
            await StartRecordingAsync();
            if (!_isPushToTalkHeld && Status == TranscriptionStatus.Recording && _pttMode == PttMode.Hold)
            {
                _pttMode = PttMode.Idle;
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
        // In continuous mode the physical release of the primary trigger
        // is irrelevant — the session ends on silence or on another
        // primary press / lock toggle.
        if (_pttMode == PttMode.Continuous)
        {
            return;
        }

        if (!_isPushToTalkHeld)
        {
            return;
        }

        _isPushToTalkHeld = false;
        if (Status == TranscriptionStatus.Recording)
        {
            _pttMode = PttMode.Idle;
            await StopAndTranscribeAsync();
        }
    }

    /// <summary>
    /// Toggle entry point for the secondary "lock-in" hotkey. Starts a
    /// continuous (hands-free) recording, or stops one in progress.
    /// Promotes an active hold session in-place without restarting audio.
    /// </summary>
    private async Task ToggleContinuousLockAsync()
    {
        if (_pttMode == PttMode.Continuous)
        {
            await StopContinuousAndTranscribeAsync();
            return;
        }

        // Second tap arriving while we are still spinning up the audio
        // engine for a previous lock press. Flag the in-flight start as
        // cancelled — the async tail will discard the recording instead
        // of entering continuous mode.
        if (_continuousStartInFlight)
        {
            _continuousStartCancelled = true;
            return;
        }

        // Promote an active hold session into continuous without restarting
        // the audio stream — user pressed-and-held the primary trigger,
        // then tapped the lock combo to "lock in" before releasing.
        if (Status == TranscriptionStatus.Recording)
        {
            _isPushToTalkHeld = false;
            EnterContinuousMode();
            return;
        }

        if (Status is TranscriptionStatus.Transcribing || _isStartingPushToTalkRecording)
        {
            return;
        }

        _isStartingPushToTalkRecording = true;
        _continuousStartInFlight = true;
        _continuousStartCancelled = false;

        try
        {
            await StartRecordingAsync();

            if (_continuousStartCancelled)
            {
                _continuousStartCancelled = false;
                DiscardActiveRecording();
                return;
            }

            if (Status == TranscriptionStatus.Recording)
            {
                EnterContinuousMode();
            }
        }
        finally
        {
            _isStartingPushToTalkRecording = false;
            _continuousStartInFlight = false;
        }
    }

    private void EnterContinuousMode()
    {
        _pttMode = PttMode.Continuous;
        StatusMessage = "Recording (continuous)";
        _hudWindow.ShowContinuous();
        _silenceWatchdog.Start(_audioRecorder, () => _ = StopContinuousAndTranscribeAsync());
    }

    private async Task StopContinuousAndTranscribeAsync()
    {
        _silenceWatchdog.Stop();
        if (_pttMode != PttMode.Continuous)
        {
            return;
        }

        _pttMode = PttMode.Idle;
        if (Status == TranscriptionStatus.Recording)
        {
            await StopAndTranscribeAsync();
        }
    }

    /// <summary>
    /// Stops and discards an in-progress recording without going through
    /// the transcribe pipeline. Used when the user cancels a continuous
    /// start mid-spinup with a second lock press.
    /// </summary>
    private void DiscardActiveRecording()
    {
        if (Status != TranscriptionStatus.Recording)
        {
            return;
        }

        try
        {
            var path = _audioRecorder.StopRecording();
            TryDelete(path);
        }
        catch
        {
        }

        _pttMode = PttMode.Idle;
        Status = TranscriptionStatus.Idle;
        StatusMessage = "Idle";
        LastError = null;
        _hudWindow.HideHud();
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
            case nameof(AppSettings.LockTriggerId):
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

    private void ApplyLockTrigger()
    {
        _pushToTalkService.SetLockTrigger(PushToTalkTrigger.FindOrNull(_settings.LockTriggerId));
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
