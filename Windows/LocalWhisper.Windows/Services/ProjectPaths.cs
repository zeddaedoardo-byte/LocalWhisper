namespace LocalWhisper.Windows.Services;

public static class ProjectPaths
{
    public static string ApplicationSupportRoot
    {
        get
        {
            var baseDir = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var root = Path.Combine(baseDir, "LocalWhisper");
            Directory.CreateDirectory(root);
            return root;
        }
    }

    public static string ModelsDirectory
    {
        get
        {
            var path = Path.Combine(ApplicationSupportRoot, "Models");
            Directory.CreateDirectory(path);
            return path;
        }
    }

    public static string BinDirectory
    {
        get
        {
            var path = Path.Combine(ApplicationSupportRoot, "bin");
            Directory.CreateDirectory(path);
            return path;
        }
    }

    public static string DefaultModelPath =>
        Path.Combine(ModelsDirectory, "ggml-large-v3-turbo.bin");

    public static string DefaultWhisperCliPath
    {
        get
        {
            var bundled = Path.Combine(AppContext.BaseDirectory, "bin", "whisper-cli.exe");
            if (File.Exists(bundled))
            {
                return bundled;
            }

            var appSupport = Path.Combine(BinDirectory, "whisper-cli.exe");
            if (File.Exists(appSupport))
            {
                return appSupport;
            }

            return appSupport;
        }
    }

    public static string SettingsPath =>
        Path.Combine(ApplicationSupportRoot, "settings.json");
}
