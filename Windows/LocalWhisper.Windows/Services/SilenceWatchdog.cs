using System.Windows.Threading;

namespace LocalWhisper.Windows.Services;

/// <summary>
/// Auto-stops continuous (hands-free) recording when the user has been
/// silent for <see cref="SilenceDuration"/> after at least
/// <see cref="ArmingDuration"/> of detected speech. Subscribes to
/// <see cref="AudioRecorderService.LevelChanged"/>; the level callback
/// fires on the WASAPI capture thread, so we keep the latest sample in
/// a field and evaluate on the WPF dispatcher timer to stay thread-safe
/// with the rest of AppState.
/// </summary>
public sealed class SilenceWatchdog
{
    public const float ThresholdDb = -45f;
    public static readonly TimeSpan SilenceDuration = TimeSpan.FromSeconds(2.0);
    public static readonly TimeSpan ArmingDuration = TimeSpan.FromMilliseconds(500);
    private static readonly TimeSpan TickInterval = TimeSpan.FromMilliseconds(100);

    private readonly object _stateLock = new();
    private DispatcherTimer? _timer;
    private AudioRecorderService? _recorder;
    private EventHandler<float>? _levelHandler;
    private Action? _onSilence;
    private float _lastLevel = -160f;
    private TimeSpan _speechStreak = TimeSpan.Zero;
    private TimeSpan _silenceStreak = TimeSpan.Zero;
    private bool _armed;

    public void Start(AudioRecorderService recorder, Action onSilence)
    {
        Stop();

        _recorder = recorder;
        _onSilence = onSilence;
        _levelHandler = (_, db) =>
        {
            lock (_stateLock)
            {
                _lastLevel = db;
            }
        };
        recorder.LevelChanged += _levelHandler;

        _timer = new DispatcherTimer { Interval = TickInterval };
        _timer.Tick += OnTick;
        _timer.Start();
    }

    public void Stop()
    {
        if (_timer is not null)
        {
            _timer.Stop();
            _timer.Tick -= OnTick;
            _timer = null;
        }

        if (_recorder is not null && _levelHandler is not null)
        {
            _recorder.LevelChanged -= _levelHandler;
        }

        _recorder = null;
        _levelHandler = null;
        _onSilence = null;

        lock (_stateLock)
        {
            _lastLevel = -160f;
            _speechStreak = TimeSpan.Zero;
            _silenceStreak = TimeSpan.Zero;
            _armed = false;
        }
    }

    private void OnTick(object? sender, EventArgs e)
    {
        float level;
        lock (_stateLock)
        {
            level = _lastLevel;
        }

        if (level >= ThresholdDb)
        {
            _speechStreak += TickInterval;
            _silenceStreak = TimeSpan.Zero;
            if (!_armed && _speechStreak >= ArmingDuration)
            {
                _armed = true;
            }
        }
        else if (_armed)
        {
            _silenceStreak += TickInterval;
            if (_silenceStreak >= SilenceDuration)
            {
                var callback = _onSilence;
                Stop();
                callback?.Invoke();
            }
        }
    }
}
