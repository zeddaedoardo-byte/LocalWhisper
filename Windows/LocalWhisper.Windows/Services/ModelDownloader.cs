using System.ComponentModel;
using System.Runtime.CompilerServices;
using LocalWhisper.Windows.Models;

namespace LocalWhisper.Windows.Services;

public sealed class ModelDownloader : INotifyPropertyChanged
{
    private double _progress;
    private long _bytesWritten;
    private long _totalBytes;
    private bool _isDownloading;
    private string? _lastError;

    public event PropertyChangedEventHandler? PropertyChanged;

    public double Progress
    {
        get => _progress;
        private set => SetField(ref _progress, value);
    }

    public long BytesWritten
    {
        get => _bytesWritten;
        private set => SetField(ref _bytesWritten, value);
    }

    public long TotalBytes
    {
        get => _totalBytes;
        private set => SetField(ref _totalBytes, value);
    }

    public bool IsDownloading
    {
        get => _isDownloading;
        private set => SetField(ref _isDownloading, value);
    }

    public string? LastError
    {
        get => _lastError;
        private set => SetField(ref _lastError, value);
    }

    public async Task<string> DownloadLargeV3TurboAsync(CancellationToken cancellationToken)
    {
        var model = WhisperModelInfo.LargeV3Turbo;
        Directory.CreateDirectory(ProjectPaths.ModelsDirectory);
        var destination = Path.Combine(ProjectPaths.ModelsDirectory, model.FileName);
        if (File.Exists(destination))
        {
            return destination;
        }

        var temp = destination + ".download";
        if (File.Exists(temp))
        {
            File.Delete(temp);
        }

        IsDownloading = true;
        LastError = null;
        BytesWritten = 0;
        TotalBytes = (long)model.ApproxMb * 1024 * 1024;
        Progress = 0;

        try
        {
            using var client = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
            using var response = await client.GetAsync(model.DownloadUrl, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            response.EnsureSuccessStatusCode();

            TotalBytes = response.Content.Headers.ContentLength ?? TotalBytes;
            await using var input = await response.Content.ReadAsStreamAsync(cancellationToken);
            await using var output = File.Create(temp);
            var buffer = new byte[1024 * 1024];
            int read;
            while ((read = await input.ReadAsync(buffer, cancellationToken)) > 0)
            {
                await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
                BytesWritten += read;
                if (TotalBytes > 0)
                {
                    Progress = Math.Clamp((double)BytesWritten / TotalBytes, 0, 1);
                }
            }

            output.Close();
            File.Move(temp, destination, overwrite: true);
            Progress = 1;
            return destination;
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
            if (File.Exists(temp))
            {
                File.Delete(temp);
            }

            throw;
        }
        finally
        {
            IsDownloading = false;
        }
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
