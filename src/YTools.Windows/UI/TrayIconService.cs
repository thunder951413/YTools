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
    private readonly System.Windows.Forms.ContextMenuStrip _menu;
    private readonly System.ComponentModel.PropertyChangedEventHandler _preferenceChanged;
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

        _menu = new System.Windows.Forms.ContextMenuStrip
        {
            ShowImageMargin = false,
            ShowCheckMargin = false,
            Padding = new System.Windows.Forms.Padding(4)
        };
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

        _menu.Items.AddRange(
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
        _notifyIcon.ContextMenuStrip = _menu;
        ThemeService.ThemeApplied += ApplyTheme;
        ApplyTheme();
        UpdateVisibility();
        _preferenceChanged = (_, args) =>
        {
            if (args.PropertyName == nameof(AppPreferences.ShowTrayIcon))
            {
                Application.Current.Dispatcher.Invoke(UpdateVisibility);
            }
        };
        _preferences.PropertyChanged += _preferenceChanged;
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
        _preferences.PropertyChanged -= _preferenceChanged;
        ThemeService.ThemeApplied -= ApplyTheme;
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _menu.Dispose();
    }

    private void UpdateVisibility()
    {
        _notifyIcon.Visible = _preferences.ShowTrayIcon;
    }

    private void ApplyTheme()
    {
        var dark = ThemeService.IsDarkEffective(_preferences);
        var background = dark
            ? Color.FromArgb(43, 43, 49)
            : Color.FromArgb(254, 254, 255);
        var foreground = dark
            ? Color.FromArgb(241, 241, 244)
            : Color.FromArgb(26, 26, 30);
        var disabled = dark
            ? Color.FromArgb(140, 140, 152)
            : Color.FromArgb(122, 122, 133);
        var border = dark
            ? Color.FromArgb(82, 82, 90)
            : Color.FromArgb(205, 205, 211);
        var selection = dark
            ? Color.FromArgb(62, 62, 70)
            : Color.FromArgb(232, 232, 237);

        _menu.BackColor = background;
        _menu.ForeColor = foreground;
        _menu.Renderer = new System.Windows.Forms.ToolStripProfessionalRenderer(
            new TrayColorTable(background, selection, border));
        foreach (System.Windows.Forms.ToolStripItem item in _menu.Items)
        {
            item.BackColor = background;
            item.ForeColor = item.Enabled ? foreground : disabled;
        }
    }

    private sealed class TrayColorTable : System.Windows.Forms.ProfessionalColorTable
    {
        private readonly Color _background;
        private readonly Color _selection;
        private readonly Color _border;

        public TrayColorTable(Color background, Color selection, Color border)
        {
            _background = background;
            _selection = selection;
            _border = border;
            UseSystemColors = false;
        }

        public override Color ToolStripDropDownBackground => _background;

        public override Color ImageMarginGradientBegin => _background;

        public override Color ImageMarginGradientMiddle => _background;

        public override Color ImageMarginGradientEnd => _background;

        public override Color MenuItemSelected => _selection;

        public override Color MenuItemBorder => _border;

        public override Color MenuBorder => _border;

        public override Color SeparatorDark => _border;

        public override Color SeparatorLight => _background;
    }
}
