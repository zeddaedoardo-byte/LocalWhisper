using System.Windows;
using LocalWhisper.Windows.Services;
using LocalWhisper.Windows.ViewModels;

namespace LocalWhisper.Windows.Views;

public partial class SettingsWindow : Window
{
    public SettingsWindow(SettingsStore settingsStore, AppState appState)
    {
        InitializeComponent();
        DataContext = new SettingsViewModel(settingsStore, appState);
    }
}
