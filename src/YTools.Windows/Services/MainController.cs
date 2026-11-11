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
    private TranslatorWindow? _translatorWindow;
    private TrayIconService? _tray;
    private EventWaitHandle? _showLauncherEvent;
    private RegisteredWaitHandle? _showLauncherWaitRegistration;
    private HotKeyDefinition? _lastWorkingLauncher;
    private HotKeyDefinition? _lastWorkingClipboard;
    private bool _shutdownRequested;

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
            ActivePanel,
            text => ShowTranslator(text));
        _launcherWindow.Attach(_launcher, _preferences);
        _launcherWindow.OnOpenSettings = OpenSettings;
        _launcherWindow.OnShowLargeType = ShowLargeType;
        _clipboardWindow.Attach(_clipboard, _snippets, _preferences);
        _clipboardWindow.OnOpenSettings = OpenSettings;
        _clipboardWindow.OnNotice = ShowNotice;

        _tray = new TrayIconService(_preferences);
        _tray.ShowLauncherRequested += ShowLauncher;
        _tray.ShowClipboardRequested += ShowClipboard;
        _tray.TogglePauseRequested += ToggleClipboardPause;
        _tray.ShowSettingsRequested += OpenSettings;
        _tray.QuitRequested += () => _ = SafeRequestShutdownAsync();

        _preferences.HotKeysChanged += ConfigureHotKeys;
        _preferences.ClearUsageLearningRequested += () => _launcher?.ClearUsageLearning();
        _preferences.PropertyChanged += OnPreferencePropertyChanged;
        ConfigureHotKeys();

        _showLauncherEvent = new EventWaitHandle(
            false,
            EventResetMode.AutoReset,
            ShowLauncherEventName);
        _showLauncherWaitRegistration = ThreadPool.RegisterWaitForSingleObject(
            _showLauncherEvent,
            (_, timedOut) =>
            {
                if (timedOut || _shutdownRequested) { return; }
                var dispatcher = Application.Current?.Dispatcher;
                if (dispatcher is not null && !dispatcher.HasShutdownStarted && !dispatcher.HasShutdownFinished)
                {
                    _ = dispatcher.BeginInvoke(ShowLauncher);
                }
            },
            state: null,
            millisecondsTimeOutInterval: Timeout.Infinite,
            executeOnlyOnce: false);

        _launcherWindow.ShowLauncher();
    }

    public void Shutdown()
    {
        _preferences.HotKeysChanged -= ConfigureHotKeys;
        _snippets?.FlushPendingChanges();
        _recentDocuments?.FlushPendingChanges();
        _launcher?.PersistLastQuery();
        _preferences.FlushPendingChanges();
        _launcher?.Dispose();
        _clipboard?.Dispose();
        _tray?.Dispose();
        _showLauncherWaitRegistration?.Unregister(null);
        _showLauncherWaitRegistration = null;
        _showLauncherEvent?.Dispose();
        _showLauncherEvent = null;
        _hotKeys?.Dispose();
        _clipboardMonitor?.Dispose();
        _messages?.Dispose();
        _messages = null;
    }

    private async Task SafeRequestShutdownAsync()
    {
        try
        {
            await RequestShutdownAsync();
        }
        catch (Exception exception)
        {
            AppPaths.LogException(exception);
            Application.Current?.Shutdown();
        }
    }

    private async Task RequestShutdownAsync()
    {
        if (_shutdownRequested) { return; }
        _shutdownRequested = true;
        _hotKeys?.RemoveAll();
        _launcherWindow?.HidePanel();
        _clipboardWindow?.HidePanel();
        _translatorWindow?.Close();
        try
        {
            _settingsWindow?.Close();
            // Each flush is isolated: one failing store must neither skip the
            // others nor leave the app half shut down with hotkeys removed.
            await FlushQuietly(() => _launcher?.FlushPendingActionsAsync());
            await FlushQuietly(() => _clipboard?.FlushPendingChangesAsync());
            _launcher?.PersistLastQuery();
            await FlushQuietly(() => _preferences.FlushPendingChangesAsync());
            await FlushQuietly(() => _snippets?.FlushPendingChangesAsync());
            await FlushQuietly(() => _recentDocuments?.FlushPendingChangesAsync());
        }
        finally
        {
            Application.Current.Shutdown();
        }
    }

    private static async Task FlushQuietly(Func<Task?> flush)
    {
        try
        {
            var task = flush();
            if (task is not null) { await task; }
        }
        catch (Exception exception)
        {
            System.Diagnostics.Debug.WriteLine($"YTools shutdown flush failed: {exception}");
        }
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
            RegisterTranslatorHotKey();
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
            RegisterTranslatorHotKey();
        }
        else
        {
            _hotKeys.RemoveAll();
            _preferences.HotKeyError = "所有候选快捷键均被其他应用占用，请关闭占用程序或在设置中更换快捷键。";
        }
    }

    /// <summary>
    /// The AI translator shortcut is only claimed while the feature is enabled,
    /// and a conflict is reported without touching the launcher/clipboard keys.
    /// </summary>
    private void RegisterTranslatorHotKey()
    {
        if (_hotKeys is null || !_preferences.AITranslation.Enabled) { return; }
        var translator = _preferences.TranslatorHotKey;
        if (_hotKeys.Register(3, translator, () => ToggleTranslator()))
        {
            return;
        }

        var message = $"AI 翻译快捷键 {translator.DisplayString} 已被其他应用占用，请在设置中更换。";
        _preferences.HotKeyError = _preferences.HotKeyError is { Length: > 0 } existing ? existing + "\n" + message : message;
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

        PasteService.Shared.RememberForegroundWindow();
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

        PasteService.Shared.RememberForegroundWindow();
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

    private TranslatorWindow TranslatorWindow()
    {
        if (_translatorWindow is null)
        {
            var window = new TranslatorWindow(_preferences)
            {
                OnOpenSettings = OpenSettings,
                OnNotice = ShowNotice
            };
            window.Closed += (_, _) => _translatorWindow = null;
            _translatorWindow = window;
        }

        return _translatorWindow;
    }

    private void ShowTranslator(string text = "")
    {
        var window = TranslatorWindow();
        if (!window.IsVisible) { PasteService.Shared.RememberForegroundWindow(); }
        window.ShowTranslator(text);
    }

    private void ToggleTranslator()
    {
        var window = TranslatorWindow();
        if (!window.IsVisible) { PasteService.Shared.RememberForegroundWindow(); }
        window.Toggle();
    }

    private void ShowNotice(string text)
    {
        _tray?.ShowNotice(text);
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
}
