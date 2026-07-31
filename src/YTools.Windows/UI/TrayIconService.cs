using System.Drawing;
using System.Windows;
using System.Windows.Threading;
using YTools.Models;

namespace YTools.UI;

/// <summary>
/// System tray (notification area) icon with the same commands as the macOS
/// menu-bar status item.
/// </summary>
public sealed class TrayIconService : IDisposable
{
    private readonly System.Windows.Forms.NotifyIcon _notifyIcon = new();
    private readonly AppPreferences _preferences;
    private System.Windows.Forms.ToolStripMenuItem? _pauseItem;
    private System.Windows.Forms.ToolStripMenuItem? _launcherItem;
    private System.Windows.Forms.ToolStripMenuItem? _clipboardItem;

    public TrayIconService(AppPreferences preferences)
    {
        _preferences = preferences;
        var stream = Application.GetResourceStream(
            new Uri("pack://application:,,,/Resources/AppIcon.ico"))?.Stream;
        if (stream is not null)
        {
            _notifyIcon.Icon = new Icon(stream);
        }

        _notifyIcon.Text = "YTools";
        _notifyIcon.DoubleClick += (_, _) => ShowLauncherRequested?.Invoke();

        var menu = new System.Windows.Forms.ContextMenuStrip();
        _launcherItem = new System.Windows.Forms.ToolStripMenuItem("显示启动器");
        _launcherItem.Click += (_, _) => ShowLauncherRequested?.Invoke();
        _clipboardItem = new System.Windows.Forms.ToolStripMenuItem("剪贴板历史");
        _clipboardItem.Click += (_, _) => ShowClipboardRequested?.Invoke();
        _pauseItem = new System.Windows.Forms.ToolStripMenuItem(
            _preferences.ClipboardPaused ? "继续剪贴板记录" : "暂停剪贴板记录");
        _pauseItem.Click += (_, _) => TogglePauseRequested?.Invoke();
        var separator = new System.Windows.Forms.ToolStripSeparator();
        var privacy = new System.Windows.Forms.ToolStripMenuItem("本机模式 · 无网络模块")
        {
            Enabled = false
        };
        var separator2 = new System.Windows.Forms.ToolStripSeparator();
        var settings = new System.Windows.Forms.ToolStripMenuItem("设置…");
        settings.Click += (_, _) => ShowSettingsRequested?.Invoke();
        var separator3 = new System.Windows.Forms.ToolStripSeparator();
        var quit = new System.Windows.Forms.ToolStripMenuItem("退出 YTools");
        quit.Click += (_, _) => QuitRequested?.Invoke();

        menu.Items.AddRange(
        [
            _launcherItem,
            _clipboardItem,
            _pauseItem,
            separator,
            privacy,
            separator2,
            settings,
            separator3,
            quit
        ]);
        _notifyIcon.ContextMenuStrip = menu;
        UpdateVisibility();
        _preferences.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(AppPreferences.ShowTrayIcon))
            {
                Application.Current.Dispatcher.Invoke(UpdateVisibility);
            }
        };
    }

    public event Action? ShowLauncherRequested;

    public event Action? ShowClipboardRequested;

    public event Action? TogglePauseRequested;

    public event Action? ShowSettingsRequested;

    public event Action? QuitRequested;

    public void UpdatePauseMenu(bool paused)
    {
        _pauseItem!.Text = paused ? "继续剪贴板记录" : "暂停剪贴板记录";
    }

    public void UpdateHotKeyTitles(string launcher, string clipboard)
    {
        _launcherItem!.Text = $"显示启动器（{launcher}）";
        _clipboardItem!.Text = $"剪贴板历史（{clipboard}）";
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
    }

    private void UpdateVisibility()
    {
        _notifyIcon.Visible = _preferences.ShowTrayIcon;
    }
}
