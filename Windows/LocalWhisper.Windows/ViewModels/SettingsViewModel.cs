using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using LocalWhisper.Windows.Models;
using LocalWhisper.Windows.Services;
using Microsoft.Win32;

namespace LocalWhisper.Windows.ViewModels;

public sealed class SettingsViewModel : INotifyPropertyChanged
{
    private readonly SettingsStore _settingsStore;
    private readonly AppState _appState;
    private string _micTestResult = "";

    public SettingsViewModel(SettingsStore settingsStore, AppState appState)
    {
        _settingsStore = settingsStore;
        _appState = appState;
        Settings = settingsStore.Settings;
        Settings.PropertyChanged += (_, e) =>
        {
            PropertyChanged?.Invoke(this, e);
            if (e.PropertyName == nameof(AppSettings.TotalTimeSavedSeconds))
            {
                OnPropertyChanged(nameof(TotalTimeSavedLabel));
            }
        };
        _appState.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppState.StatusMessage) or nameof(AppState.LastError) or nameof(AppState.LastTranscript) or nameof(AppState.IsServerReady) or nameof(AppState.IsWarmingUp))
            {
                OnPropertyChanged(e.PropertyName);
            }
        };
        _appState.ModelDownloader.PropertyChanged += (_, e) =>
        {
            OnPropertyChanged(nameof(ModelDownloadProgress));
            OnPropertyChanged(nameof(ModelDownloadLabel));
            OnPropertyChanged(e.PropertyName);
        };

        Presets = new ObservableCollection<PerformancePreset>(PerformancePreset.All);
        Triggers = new ObservableCollection<PushToTalkTrigger>(PushToTalkTrigger.All);
        Devices = new ObservableCollection<AudioDeviceInfo>();
        RefreshDevices();

        BrowseBinaryCommand = new RelayCommand(BrowseBinary);
        BrowseModelCommand = new RelayCommand(BrowseModel);
        ResetPathsCommand = new RelayCommand(_settingsStore.ResetDefaultPaths);
        RefreshDevicesCommand = new RelayCommand(RefreshDevices);
        RestartPipelineCommand = new AsyncRelayCommand(_appState.RestartPipelineAsync);
        TestMicrophoneCommand = new AsyncRelayCommand(TestMicrophoneAsync);
        DownloadModelCommand = new AsyncRelayCommand(_appState.DownloadDefaultModelAsync);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public AppSettings Settings { get; }

    public ObservableCollection<PerformancePreset> Presets { get; }

    public ObservableCollection<PushToTalkTrigger> Triggers { get; }

    public ObservableCollection<AudioDeviceInfo> Devices { get; }

    public ICommand BrowseBinaryCommand { get; }

    public ICommand BrowseModelCommand { get; }

    public ICommand ResetPathsCommand { get; }

    public ICommand RefreshDevicesCommand { get; }

    public ICommand RestartPipelineCommand { get; }

    public ICommand TestMicrophoneCommand { get; }

    public ICommand DownloadModelCommand { get; }

    public string StatusMessage => _appState.StatusMessage;

    public string? LastError => _appState.LastError;

    public string LastTranscript => _appState.LastTranscript;

    public bool IsServerReady => _appState.IsServerReady;

    public bool IsWarmingUp => _appState.IsWarmingUp;

    public double ModelDownloadProgress => _appState.ModelDownloader.Progress * 100;

    public string ModelDownloadLabel
    {
        get
        {
            var downloader = _appState.ModelDownloader;
            if (!downloader.IsDownloading)
            {
                return "";
            }

            var total = downloader.TotalBytes <= 0 ? "unknown" : $"{downloader.TotalBytes / 1024 / 1024:n0} MB";
            return $"{downloader.BytesWritten / 1024 / 1024:n0} MB / {total}";
        }
    }

    public string TotalTimeSavedLabel => TimeSpan.FromSeconds(Settings.TotalTimeSavedSeconds).ToString(@"hh\:mm\:ss");

    public string MicTestResult
    {
        get => _micTestResult;
        private set => SetField(ref _micTestResult, value);
    }

    private void BrowseBinary()
    {
        var dialog = new OpenFileDialog
        {
            Title = "Select whisper-cli.exe",
            Filter = "whisper-cli.exe|whisper-cli.exe|Executable files (*.exe)|*.exe|All files (*.*)|*.*",
            CheckFileExists = true
        };

        if (dialog.ShowDialog() == true)
        {
            Settings.WhisperBinaryPath = dialog.FileName;
        }
    }

    private void BrowseModel()
    {
        var dialog = new OpenFileDialog
        {
            Title = "Select ggml-large-v3.bin",
            Filter = "Whisper model (*.bin)|*.bin|All files (*.*)|*.*",
            CheckFileExists = true
        };

        if (dialog.ShowDialog() == true)
        {
            Settings.ModelPath = dialog.FileName;
        }
    }

    private void RefreshDevices()
    {
        Devices.Clear();
        Devices.Add(new AudioDeviceInfo("", "System default microphone"));
        foreach (var device in AudioDeviceCatalog.ListInputDevices())
        {
            Devices.Add(device);
        }
    }

    private async Task TestMicrophoneAsync()
    {
        MicTestResult = "Listening...";
        var peak = await _appState.RunMicLevelTestAsync(TimeSpan.FromSeconds(1.5));
        MicTestResult = peak <= -90 ? "No clear signal detected" : $"Peak {peak:n1} dB";
    }

    private void SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return;
        }

        field = value;
        OnPropertyChanged(propertyName);
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
