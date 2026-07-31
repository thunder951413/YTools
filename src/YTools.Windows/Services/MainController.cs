using System.Windows;
using YTools.Infrastructure;
using YTools.Models;
using YTools.UI;

namespace YTools.Services;

/// <summary>
/// Wires every service and window together, mirroring the macOS AppDelegate:
/// global hotkeys, clipboard monitoring, tray icon, launcher and settings.
/// </summary>
public sealed class MainController
{
    private const string ShowLauncherEventName = "YTools.ShowLauncher";
    private readonly AppPreferences _preferences = new();
    private MessageWindowService? _messages;
    private HotKeyManager? _hotKeys;
    private ClipboardMonitor? _clipboardMonitor;
    private ClipboardHistoryManager? _clipboard;
    private SnippetManager? _snippets;
    private RecentDocumentsManager? _recentDocuments;
    private LauncherModel? _launcher;
    private LauncherWindow? _launcherWindow;
    private ClipboardWindow? _clipboardWindow;
    private SettingsWindow? _settingsWindow;
    private LargeTypeWindow? _largeTypeWindow;
    private TrayIconService? _tray;
    private EventWaitHandle? _showLauncherEvent;
    private HotKeyDefinition? _lastWorkingLauncher;
    private HotKeyDefinition? _lastWorkingClipboard;

    public void Start()
    {
        AppPaths.EnsureDirectories();
        ThemeService.Subscribe();
        ThemeService.Apply(_preferences);

        _messages = new MessageWindowService();
        _hotKeys = new HotKeyManager(_messages);
        _clipboardMonitor = new ClipboardMonitor(_messages);
        _snippets = new SnippetManager();
        _recentDocuments = new RecentDocumentsManager();
        _clipboard = new ClipboardHistoryManager(_preferences, _clipboardMonitor);

        _launcherWindow = new LauncherWindow();
        _clipboardWindow = new ClipboardWindow();
        _largeTypeWindow = new LargeTypeWindow();
        _launcher = new LauncherModel(
            _preferences,
            _snippets,
            _recentDocuments,
            OpenSettings,
            ShowLargeType,
            ActivePanel);
        _launcherWindow.Attach(_launcher, _preferences);
        _launcherWindow.OnOpenSettings = OpenSettings;
        _launcherWindow.OnShowLargeType = ShowLargeType;
        _clipboardWindow.Attach(_clipboard, _snippets);
        _clipboardWindow.OnOpenSettings = OpenSettings;

        _tray = new TrayIconService(_preferences);
        _tray.ShowLauncherRequested += ShowLauncher;
        _tray.ShowClipboardRequested += ShowClipboard;
        _tray.TogglePauseRequested += ToggleClipboardPause;
        _tray.ShowSettingsRequested += OpenSettings;
        _tray.QuitRequested += () => Application.Current.Shutdown();

        _preferences.HotKeysChanged += ConfigureHotKeys;
        _preferences.ClearUsageLearningRequested += () => _launcher?.ClearUsageLearning();
        ConfigureHotKeys();

        _showLauncherEvent = new EventWaitHandle(
            false,
            EventResetMode.AutoReset,
            ShowLauncherEventName);
        _ = WaitForShowSignalAsync();

        _launcherWindow.ShowLauncher();
    }

    public void Shutdown()
    {
        _preferences.HotKeysChanged -= ConfigureHotKeys;
        _snippets?.FlushPendingChanges();
        _launcher?.Dispose();
        _tray?.Dispose();
        _showLauncherEvent?.Dispose();
        _showLauncherEvent = null;
        _hotKeys?.Dispose();
        _clipboardMonitor?.Dispose();
        _messages?.Dispose();
        _messages = null;
    }

    private void ConfigureHotKeys()
    {
        if (_hotKeys is null || _launcherWindow is null || _clipboardWindow is null)
        {
            return;
        }

        _hotKeys.RemoveAll();
        _preferences.HotKeyError = null;

        var launcherRegistered = _hotKeys.Register(
            1,
            _preferences.LauncherHotKey,
            ShowLauncher);
        var clipboardRegistered = !_preferences.ClipboardEnabled
            || _hotKeys.Register(
                2,
                _preferences.ClipboardHotKey,
                ShowClipboard);

        if (launcherRegistered && clipboardRegistered)
        {
            _lastWorkingLauncher = _preferences.LauncherHotKey;
            _lastWorkingClipboard = _preferences.ClipboardHotKey;
            _tray?.UpdateHotKeyTitles(
                _preferences.LauncherHotKey.DisplayString,
                _preferences.ClipboardHotKey.DisplayString);
            return;
        }

        _hotKeys.RemoveAll();
        var hadPrevious = _lastWorkingLauncher is not null;
        var launcher = _lastWorkingLauncher ?? HotKeyDefinition.LauncherFallback;
        var clipboard = _lastWorkingClipboard ?? HotKeyDefinition.ClipboardFallback;
        launcherRegistered = _hotKeys.Register(1, launcher, ShowLauncher);
        clipboardRegistered = !_preferences.ClipboardEnabled
            || _hotKeys.Register(2, clipboard, ShowClipboard);
        if (launcherRegistered && clipboardRegistered)
        {
            _preferences.RestoreHotKeysWithoutNotifying(launcher, clipboard);
            _lastWorkingLauncher = launcher;
            _lastWorkingClipboard = clipboard;
            _preferences.HotKeyError = hadPrevious
                ? "新快捷键已被占用，已恢复上一个可用组合。"
                : "默认快捷键被占用，已启用备用组合。";
            _tray?.UpdateHotKeyTitles(launcher.DisplayString, clipboard.DisplayString);
        }
        else
        {
            _hotKeys.RemoveAll();
            _preferences.HotKeyError = "快捷键已被其他应用占用，请在启动器中按 Ctrl+, 打开设置后更换。";
        }
    }

    private void ShowLauncher()
    {
        if (_launcherWindow is null)
        {
            return;
        }

        if (_launcherWindow.IsVisible)
        {
            _launcherWindow.HidePanel();
            return;
        }

        _clipboardWindow?.HidePanel();
        _launcherWindow.ShowLauncher();
    }

    private void ShowClipboard()
    {
        if (_clipboardWindow is null)
        {
            return;
        }

        if (_clipboardWindow.IsVisible)
        {
            _clipboardWindow.HidePanel();
            return;
        }

        _launcherWindow?.HidePanel();
        _clipboardWindow.ShowClipboard();
    }

    private void ToggleClipboardPause()
    {
        _preferences.ClipboardPaused = !_preferences.ClipboardPaused;
        _tray?.UpdatePauseMenu(_preferences.ClipboardPaused);
    }

    private void OpenSettings()
    {
        if (_settingsWindow is null)
        {
            _settingsWindow = new SettingsWindow();
            _settingsWindow.Attach(
                _preferences,
                _clipboard!,
                _snippets!,
                _recentDocuments!);
            _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        }

        _settingsWindow.Show();
        _settingsWindow.Activate();
    }

    private void ShowLargeType(string text)
    {
        _largeTypeWindow?.ShowText(text);
    }

    private Window? ActivePanel()
    {
        if (_launcherWindow?.IsVisible == true)
        {
            return _launcherWindow;
        }

        if (_clipboardWindow?.IsVisible == true)
        {
            return _clipboardWindow;
        }

        return _settingsWindow;
    }

    private async Task WaitForShowSignalAsync()
    {
        while (_showLauncherEvent is not null)
        {
            try
            {
                await Task.Run(() => _showLauncherEvent.WaitOne());
            }
            catch
            {
                return;
            }

            Application.Current.Dispatcher.Invoke(ShowLauncher);
        }
    }
}
