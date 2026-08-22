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

    private static readonly HotKeyDefinition[] LauncherFallbacks =
    [
        HotKeyDefinition.LauncherDefault,
        HotKeyDefinition.LauncherFallback,
        new(0x4C, HotKeyModifiers.Control | HotKeyModifiers.Alt), // Ctrl+Alt+L
        new(0x50, HotKeyModifiers.Control | HotKeyModifiers.Alt)  // Ctrl+Alt+P
    ];

    private static readonly HotKeyDefinition[] ClipboardFallbacks =
    [
        HotKeyDefinition.ClipboardDefault,
        HotKeyDefinition.ClipboardFallback,
        new(0x56, HotKeyModifiers.Alt | HotKeyModifiers.Control), // Alt+Ctrl+V
        new(0x43, HotKeyModifiers.Alt | HotKeyModifiers.Control | HotKeyModifiers.Shift)
    ];

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
        _preferences.PropertyChanged += OnPreferencePropertyChanged;
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
        _launcher?.PersistLastQuery();
        _launcher?.Dispose();
        _clipboard?.Dispose();
        _tray?.Dispose();
        _showLauncherEvent?.Dispose();
        _showLauncherEvent = null;
        _hotKeys?.Dispose();
        _clipboardMonitor?.Dispose();
        _messages?.Dispose();
        _messages = null;
    }

    /// <summary>Diagnostic entry: opens the settings window directly.</summary>
    public void ShowSettings()
    {
        OpenSettings();
    }

    private void ConfigureHotKeys()
    {
        if (_hotKeys is null || _launcherWindow is null || _clipboardWindow is null)
        {
            return;
        }

        _hotKeys.RemoveAll();
        var configuredLauncher = _preferences.LauncherHotKey;
        var configuredClipboard = _preferences.ClipboardHotKey;
        var launcherRegistered = _hotKeys.Register(1, configuredLauncher, ShowLauncher);
        var clipboardRegistered = !_preferences.ClipboardEnabled
            || _hotKeys.Register(2, configuredClipboard, ShowClipboard);

        if (launcherRegistered && clipboardRegistered)
        {
            _lastWorkingLauncher = configuredLauncher;
            _lastWorkingClipboard = configuredClipboard;
            _preferences.HotKeyError = null;
            UpdateTrayHotKeyTitles(configuredLauncher, configuredClipboard);
            return;
        }

        _hotKeys.RemoveAll();
        var hadPrevious = _lastWorkingLauncher is not null;
        HotKeyDefinition? launcher = null;
        HotKeyDefinition? clipboard = null;

        if (_lastWorkingLauncher is { } previousLauncher
            && _hotKeys.Register(1, previousLauncher, ShowLauncher))
        {
            launcher = previousLauncher;
        }

        if (launcher is null)
        {
            launcher = TryRegisterFirstAvailable(
                LauncherFallbacks.Append(configuredLauncher).Distinct(),
                id: 1,
                ShowLauncher);
        }

        if (_preferences.ClipboardEnabled)
        {
            if (_lastWorkingClipboard is { } previousClipboard
                && _hotKeys.Register(2, previousClipboard, ShowClipboard))
            {
                clipboard = previousClipboard;
            }

            if (clipboard is null)
            {
                clipboard = TryRegisterFirstAvailable(
                    ClipboardFallbacks.Append(configuredClipboard).Distinct(),
                    id: 2,
                    ShowClipboard);
            }
        }
        else
        {
            clipboard = configuredClipboard;
        }

        launcherRegistered = launcher is not null;
        clipboardRegistered = !_preferences.ClipboardEnabled || clipboard is not null;
        if (launcherRegistered && clipboardRegistered)
        {
            var launcherHotKey = launcher ?? configuredLauncher;
            var clipboardHotKey = clipboard ?? configuredClipboard;
            _preferences.RestoreHotKeysWithoutNotifying(launcherHotKey, clipboardHotKey);
            _lastWorkingLauncher = launcherHotKey;
            _lastWorkingClipboard = clipboardHotKey;
            _preferences.HotKeyError = hadPrevious
                ? $"新快捷键已被占用，已启用可用组合：{launcherHotKey.DisplayString} / {clipboardHotKey.DisplayString}"
                : $"默认快捷键被占用，已启用可用组合：{launcherHotKey.DisplayString} / {clipboardHotKey.DisplayString}";
            UpdateTrayHotKeyTitles(launcherHotKey, clipboardHotKey);
        }
        else
        {
            _hotKeys.RemoveAll();
            _preferences.HotKeyError = "所有候选快捷键均被其他应用占用，请关闭占用程序或在设置中更换快捷键。";
        }
    }

    private HotKeyDefinition? TryRegisterFirstAvailable(
        IEnumerable<HotKeyDefinition> candidates,
        int id,
        Action action)
    {
        foreach (var candidate in candidates)
        {
            if (_hotKeys!.Register(id, candidate, action))
            {
                return candidate;
            }
        }

        return null;
    }

    private void UpdateTrayHotKeyTitles(HotKeyDefinition launcher, HotKeyDefinition clipboard)
    {
        _tray?.UpdateHotKeyTitles(launcher.DisplayString, TrayClipboardTitle(clipboard));
    }

    private string TrayClipboardTitle(HotKeyDefinition clipboard)
    {
        return _preferences.ClipboardEnabled ? clipboard.DisplayString : "已停用";
    }

    private void OnPreferencePropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(AppPreferences.Theme):
            case nameof(AppPreferences.AccentColor):
            case nameof(AppPreferences.LauncherAppearanceStyle):
                ThemeService.Apply(_preferences);
                _settingsWindow?.RefreshChrome();
                break;
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
        try
        {
            if (_settingsWindow is null)
            {
                var settingsWindow = new SettingsWindow();
                settingsWindow.Attach(
                    _preferences,
                    _clipboard!,
                    _snippets!,
                    _recentDocuments!);
                settingsWindow.Closed += (_, _) => _settingsWindow = null;
                _settingsWindow = settingsWindow;
            }

            _settingsWindow.Show();
            _settingsWindow.Activate();
        }
        catch (Exception exception)
        {
            AppPaths.LogException(exception);
            MessageBox.Show(
                $"无法打开设置：\n{exception.Message}\n\n详细日志已写入 %APPDATA%\\YTools\\error.log。",
                "YTools",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
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

            try
            {
                Application.Current.Dispatcher.Invoke(ShowLauncher);
            }
            catch
            {
                // Dispatcher may be shutting down; stop waiting.
                return;
            }
        }
    }
}
