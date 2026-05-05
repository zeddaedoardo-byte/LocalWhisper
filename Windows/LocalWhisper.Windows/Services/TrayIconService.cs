using System.Drawing;
using Forms = System.Windows.Forms;

namespace LocalWhisper.Windows.Services;

public sealed class TrayIconService : IDisposable
{
    private readonly AppState _appState;
    private readonly Action _showSettings;
    private readonly Action _shutdown;
    private Forms.NotifyIcon? _notifyIcon;
    private Forms.ToolStripMenuItem? _statusItem;

    public TrayIconService(AppState appState, Action showSettings, Action shutdown)
    {
        _appState = appState;
        _showSettings = showSettings;
        _shutdown = shutdown;
        _appState.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(AppState.StatusMessage))
            {
                UpdateStatus();
            }
        };
    }

    public void Start()
    {
        _statusItem = new Forms.ToolStripMenuItem("Idle") { Enabled = false };
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add(_statusItem);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Settings", null, (_, _) => _showSettings());
        menu.Items.Add("Restart pipeline", null, async (_, _) => await _appState.RestartPipelineAsync());
        menu.Items.Add("Copy last transcript", null, (_, _) => _appState.CopyLastTranscript());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => _shutdown());

        _notifyIcon = new Forms.NotifyIcon
        {
            Text = "LocalWhisper",
            Icon = SystemIcons.Application,
            ContextMenuStrip = menu,
            Visible = true
        };
        _notifyIcon.DoubleClick += (_, _) => _showSettings();
        UpdateStatus();
    }

    public void Dispose()
    {
        if (_notifyIcon is not null)
        {
            _notifyIcon.Visible = false;
            _notifyIcon.Dispose();
            _notifyIcon = null;
        }
    }

    private void UpdateStatus()
    {
        if (_statusItem is not null)
        {
            _statusItem.Text = _appState.StatusMessage;
        }

        if (_notifyIcon is not null)
        {
            _notifyIcon.Text = _appState.StatusMessage.Length > 63
                ? _appState.StatusMessage[..63]
                : _appState.StatusMessage;
        }
    }
}
