using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;

namespace LocalWhisper.Windows.Models;

public sealed class AppSettings : INotifyPropertyChanged
{
    private string _whisperBinaryPath = "";
    private string _modelPath = "";
    private string _language = "auto";
    private bool _autoPaste = true;
    private string _preferredMicId = "";
    private string _pushToTalkTriggerId = PushToTalkTrigger.LeftControl.Id;
    private string _performancePresetId = PerformancePreset.Balanced.Id;
    private bool _launchAtLogin;
    private bool _playSounds = true;
    private bool _hasCompletedOnboarding;
    private double _totalTimeSavedSeconds;

    public event PropertyChangedEventHandler? PropertyChanged;

    public string WhisperBinaryPath
    {
        get => _whisperBinaryPath;
        set => SetField(ref _whisperBinaryPath, value);
    }

    public string ModelPath
    {
        get => _modelPath;
        set => SetField(ref _modelPath, value);
    }

    public string Language
    {
        get => _language;
        set => SetField(ref _language, string.IsNullOrWhiteSpace(value) ? "auto" : value.Trim());
    }

    public bool AutoPaste
    {
        get => _autoPaste;
        set => SetField(ref _autoPaste, value);
    }

    public string PreferredMicId
    {
        get => _preferredMicId;
        set => SetField(ref _preferredMicId, value);
    }

    public string PushToTalkTriggerId
    {
        get => _pushToTalkTriggerId;
        set => SetField(ref _pushToTalkTriggerId, value);
    }

    public string PerformancePresetId
    {
        get => _performancePresetId;
        set => SetField(ref _performancePresetId, value);
    }

    public bool LaunchAtLogin
    {
        get => _launchAtLogin;
        set => SetField(ref _launchAtLogin, value);
    }

    public bool PlaySounds
    {
        get => _playSounds;
        set => SetField(ref _playSounds, value);
    }

    public bool HasCompletedOnboarding
    {
        get => _hasCompletedOnboarding;
        set => SetField(ref _hasCompletedOnboarding, value);
    }

    public double TotalTimeSavedSeconds
    {
        get => _totalTimeSavedSeconds;
        set => SetField(ref _totalTimeSavedSeconds, value);
    }

    [JsonIgnore]
    public PerformancePreset PerformancePreset =>
        PerformancePreset.Find(PerformancePresetId) ?? PerformancePreset.Balanced;

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
