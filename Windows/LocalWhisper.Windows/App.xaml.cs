using System.Windows;
using LocalWhisper.Windows.Services;
using LocalWhisper.Windows.Views;

namespace LocalWhisper.Windows;

public partial class App : Application
{
    private SettingsStore? _settingsStore;
    private AppState? _appState;
    private TrayIconService? _trayIcon;
    private HudWindow? _hudWindow;
    private SettingsWindow? _settingsWindow;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _settingsStore = new SettingsStore();
        _hudWindow = new HudWindow();
        _appState = new AppState(_settingsStore, _hudWindow);
        _trayIcon = new TrayIconService(_appState, ShowSettings, Shutdown);
        AppDomain.CurrentDomain.ProcessExit += (_, _) => WhisperServerWorker.TerminateAllRunningServers();

        _trayIcon.Start();
        await _appState.StartAsync();
    }

    private void ShowSettings()
    {
        if (_settingsStore is null || _appState is null)
        {
            return;
        }

        if (_settingsWindow is null || !_settingsWindow.IsLoaded)
        {
            _settingsWindow = new SettingsWindow(_settingsStore, _appState);
            _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        }

        _settingsWindow.Show();
        _settingsWindow.Activate();
    }

    protected override async void OnExit(ExitEventArgs e)
    {
        if (_appState is not null)
        {
            await _appState.ShutdownAsync();
        }

        _trayIcon?.Dispose();
        base.OnExit(e);
    }
}
