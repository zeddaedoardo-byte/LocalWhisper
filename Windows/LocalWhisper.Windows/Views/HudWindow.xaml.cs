using System.Windows;
using System.Windows.Threading;

namespace LocalWhisper.Windows.Views;

public partial class HudWindow : Window
{
    private readonly DispatcherTimer _hideTimer;

    public HudWindow()
    {
        InitializeComponent();
        _hideTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2.2) };
        _hideTimer.Tick += (_, _) =>
        {
            _hideTimer.Stop();
            Hide();
        };
    }

    public void ShowRecording()
    {
        Dispatcher.Invoke(() =>
        {
            _hideTimer.Stop();
            TitleText.Text = "Listening";
            DetailText.Text = "Hold the hotkey and speak";
            LevelBar.Visibility = Visibility.Visible;
            PlaceNearBottom();
            Show();
        });
    }

    public void ShowTranscribing()
    {
        Dispatcher.Invoke(() =>
        {
            _hideTimer.Stop();
            TitleText.Text = "Transcribing";
            DetailText.Text = "Whisper Large V3 is working locally";
            LevelBar.Visibility = Visibility.Collapsed;
            PlaceNearBottom();
            Show();
        });
    }

    public void ShowCompleted(string preview)
    {
        Dispatcher.Invoke(() =>
        {
            TitleText.Text = "Done";
            DetailText.Text = preview;
            LevelBar.Visibility = Visibility.Collapsed;
            PlaceNearBottom();
            Show();
            _hideTimer.Stop();
            _hideTimer.Start();
        });
    }

    public void ShowError(string message)
    {
        Dispatcher.Invoke(() =>
        {
            TitleText.Text = "LocalWhisper needs attention";
            DetailText.Text = message;
            LevelBar.Visibility = Visibility.Collapsed;
            PlaceNearBottom();
            Show();
            _hideTimer.Stop();
            _hideTimer.Start();
        });
    }

    public void HideHud()
    {
        Dispatcher.Invoke(() =>
        {
            _hideTimer.Stop();
            Hide();
        });
    }

    public void UpdateLevel(float db)
    {
        Dispatcher.Invoke(() =>
        {
            var normalized = Math.Clamp((db + 60) / 60 * 100, 0, 100);
            LevelBar.Value = normalized;
        });
    }

    private void PlaceNearBottom()
    {
        var area = SystemParameters.WorkArea;
        Left = area.Left + (area.Width - Width) / 2;
        Top = area.Bottom - Height - 64;
    }
}
