using System.ComponentModel;
using System.Text.Json;
using LocalWhisper.Windows.Models;

namespace LocalWhisper.Windows.Services;

public sealed class SettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true
    };

    private readonly object _saveLock = new();

    public SettingsStore()
    {
        Settings = Load();
        ApplyDefaults(Settings);
        Settings.PropertyChanged += SaveOnChange;
        Save();
    }

    public AppSettings Settings { get; }

    public void ResetDefaultPaths()
    {
        Settings.WhisperBinaryPath = ProjectPaths.DefaultWhisperCliPath;
        Settings.ModelPath = ProjectPaths.DefaultModelPath;
    }

    private static AppSettings Load()
    {
        try
        {
            if (!File.Exists(ProjectPaths.SettingsPath))
            {
                return new AppSettings();
            }

            var json = File.ReadAllText(ProjectPaths.SettingsPath);
            return JsonSerializer.Deserialize<AppSettings>(json, JsonOptions) ?? new AppSettings();
        }
        catch
        {
            return new AppSettings();
        }
    }

    private static void ApplyDefaults(AppSettings settings)
    {
        if (string.IsNullOrWhiteSpace(settings.WhisperBinaryPath))
        {
            settings.WhisperBinaryPath = ProjectPaths.DefaultWhisperCliPath;
        }

        if (string.IsNullOrWhiteSpace(settings.ModelPath)
            || string.Equals(settings.ModelPath, LegacyLargeV3ModelPath(), StringComparison.OrdinalIgnoreCase))
        {
            settings.ModelPath = ProjectPaths.DefaultModelPath;
        }

        if (PerformancePreset.Find(settings.PerformancePresetId) is null)
        {
            settings.PerformancePresetId = PerformancePreset.Balanced.Id;
        }

        if (!PushToTalkTrigger.All.Any(t => t.Id == settings.PushToTalkTriggerId))
        {
            settings.PushToTalkTriggerId = PushToTalkTrigger.LeftControl.Id;
        }
    }

    private void SaveOnChange(object? sender, PropertyChangedEventArgs e)
    {
        Save();
    }

    private void Save()
    {
        lock (_saveLock)
        {
            Directory.CreateDirectory(ProjectPaths.ApplicationSupportRoot);
            var json = JsonSerializer.Serialize(Settings, JsonOptions);
            File.WriteAllText(ProjectPaths.SettingsPath, json);
        }
    }

    private static string LegacyLargeV3ModelPath() =>
        Path.Combine(ProjectPaths.ModelsDirectory, "ggml-large-v3.bin");
}
