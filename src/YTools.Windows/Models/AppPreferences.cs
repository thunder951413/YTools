using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using YTools.Infrastructure;
using YTools.Services;

namespace YTools.Models;

public sealed class AppPreferences : ObservableObject
{
    private const int CurrentSchemaVersion = 8;

    private bool _launchAtLogin;
    private HotKeyDefinition _launcherHotKey;
    private HotKeyDefinition _clipboardHotKey;
    private AppTheme _theme;
    private AppAccentColor _accentColor;
    private LauncherAppearanceStyle _launcherAppearanceStyle;
    private PanelPosition _panelPosition;
    private ScreenPreference _screenPreference;
    private double[]? _savedPanelTopLeft;
    private SavedPanelPlacement? _savedPanelPlacement;
    private string _forcedKeyboardInputSourceID = "";
    private bool _showTrayIcon = true;
    private bool _compactResults;
    private double _panelWidth = 720;
    private double _panelCornerRadius = 14;
    private bool _showSubtitles = true;
    private bool _showNumberShortcuts = true;
    private double _searchInputDelay = 0.15;
    private double _previewSelectionDelay = 0.3;
    private double _resultExpansionDuration = 0.15;
    private IReadOnlySet<SearchContentType> _enabledSearchContentTypes = AllContentTypes();
    private IReadOnlySet<SystemCommandID> _enabledSystemCommands = AllCommands();
    private IReadOnlyDictionary<SystemCommandID, string> _systemCommandKeywords = DefaultKeywords();
    private bool _includeFilesInDefaultResults = true;
    private bool _includeAutomaticDictionary = true;
    private int _maximumSearchResults = 8;
    private IReadOnlyList<string> _searchScopePaths = [];
    private IReadOnlyDictionary<string, string> _applicationAliases =
        new Dictionary<string, string>();
    private IReadOnlyList<string> _customApplicationPaths = [];
    private bool _fileNavigationShowsHiddenFiles;
    private FileNavigationSort _fileNavigationSort = FileNavigationSort.Name;
    private bool _fileNavigationSortAscending = true;
    private bool _fileNavigationFoldersFirst = true;
    private string _lastLauncherQuery = "";
    private bool _clipboardEnabled = true;
    private bool _clipboardPaused;
    private int _clipboardRetentionDays = 7;
    private int _clipboardMaximumItems = 300;
    private int _clipboardMaximumTextCharacters = 1_000;
    private bool _clipboardStoreImages;
    private IReadOnlyList<string> _clipboardIgnoredProcessNames = [];
    private bool _clipboardCloudSyncEnabled;
    private string _clipboardCloudSyncFolder = "YTools/clipboard-sync";
    private int _clipboardCloudSyncIntervalMinutes = 15;
    private string? _hotKeyError;
    private string? _launchAtLoginError;

    public AppPreferences()
    {
        Load();
    }

    public event Action? HotKeysChanged;

    public event Action? MenuBarVisibilityChanged;

    public event Action? ClearUsageLearningRequested;

    public bool LaunchAtLogin
    {
        get => _launchAtLogin;
        set
        {
            if (SetField(ref _launchAtLogin, value))
            {
                Save();
                ConfigureLaunchAtLogin();
            }
        }
    }

    public HotKeyDefinition LauncherHotKey
    {
        get => _launcherHotKey;
        set
        {
            if (SetField(ref _launcherHotKey, value))
            {
                Save();
                NotifyHotKeyChange();
            }
        }
    }

    public HotKeyDefinition ClipboardHotKey
    {
        get => _clipboardHotKey;
        set
        {
            if (SetField(ref _clipboardHotKey, value))
            {
                Save();
                NotifyHotKeyChange();
            }
        }
    }

    public AppTheme Theme
    {
        get => _theme;
        set
        {
            if (SetField(ref _theme, value))
            {
                Save();
            }
        }
    }

    public AppAccentColor AccentColor
    {
        get => _accentColor;
        set
        {
            if (SetField(ref _accentColor, value))
            {
                Save();
            }
        }
    }

    public LauncherAppearanceStyle LauncherAppearanceStyle
    {
        get => _launcherAppearanceStyle;
        set
        {
            if (SetField(ref _launcherAppearanceStyle, value))
            {
                Save();
            }
        }
    }

    public PanelPosition PanelPosition
    {
        get => _panelPosition;
        set
        {
            if (SetField(ref _panelPosition, value))
            {
                Save();
                ClearSavedPanelPosition();
            }
        }
    }

    public ScreenPreference ScreenPreference
    {
        get => _screenPreference;
        set
        {
            if (SetField(ref _screenPreference, value))
            {
                Save();
                ClearSavedPanelPosition();
            }
        }
    }

    public double[]? SavedPanelTopLeft
    {
        get => _savedPanelTopLeft;
        private set => SetField(ref _savedPanelTopLeft, value);
    }

    public SavedPanelPlacement? SavedPanelPlacement
    {
        get => _savedPanelPlacement;
        private set => SetField(ref _savedPanelPlacement, value);
    }

    public string ForcedKeyboardInputSourceID
    {
        get => _forcedKeyboardInputSourceID;
        set
        {
            if (SetField(ref _forcedKeyboardInputSourceID, value))
            {
                Save();
            }
        }
    }

    public bool ShowTrayIcon
    {
        get => _showTrayIcon;
        set
        {
            if (SetField(ref _showTrayIcon, value))
            {
                Save();
                MenuBarVisibilityChanged?.Invoke();
            }
        }
    }

    public bool CompactResults
    {
        get => _compactResults;
        set
        {
            if (SetField(ref _compactResults, value))
            {
                Save();
            }
        }
    }

    public double PanelWidth
    {
        get => _panelWidth;
        set
        {
            if (SetField(ref _panelWidth, Math.Clamp(value, 640, 960)))
            {
                Save();
            }
        }
    }

    public double PanelCornerRadius
    {
        get => _panelCornerRadius;
        set
        {
            if (SetField(ref _panelCornerRadius, Math.Clamp(value, 10, 20)))
            {
                Save();
            }
        }
    }

    public bool ShowSubtitles
    {
        get => _showSubtitles;
        set
        {
            if (SetField(ref _showSubtitles, value))
            {
                Save();
            }
        }
    }

    public bool ShowNumberShortcuts
    {
        get => _showNumberShortcuts;
        set
        {
            if (SetField(ref _showNumberShortcuts, value))
            {
                Save();
            }
        }
    }

    public double SearchInputDelay
    {
        get => _searchInputDelay;
        set
        {
            if (SetField(ref _searchInputDelay, Math.Clamp(value, 0.05, 0.4)))
            {
                Save();
            }
        }
    }

    public double PreviewSelectionDelay
    {
        get => _previewSelectionDelay;
        set
        {
            if (SetField(ref _previewSelectionDelay, Math.Clamp(value, 0, 0.8)))
            {
                Save();
            }
        }
    }

    public double ResultExpansionDuration
    {
        get => _resultExpansionDuration;
        set
        {
            if (SetField(ref _resultExpansionDuration, Math.Clamp(value, 0, 0.4)))
            {
                Save();
            }
        }
    }

    public string LastLauncherQuery
    {
        get => _lastLauncherQuery;
        set
        {
            if (SetField(ref _lastLauncherQuery, value))
            {
                Save();
            }
        }
    }

    public IReadOnlySet<SearchContentType> EnabledSearchContentTypes
    {
        get => _enabledSearchContentTypes;
        set
        {
            if (SetField(ref _enabledSearchContentTypes, value))
            {
                Save();
            }
        }
    }

    public IReadOnlySet<SystemCommandID> EnabledSystemCommands
    {
        get => _enabledSystemCommands;
        set
        {
            if (SetField(ref _enabledSystemCommands, value))
            {
                Save();
            }
        }
    }

    public IReadOnlyDictionary<SystemCommandID, string> SystemCommandKeywords
    {
        get => _systemCommandKeywords;
        set
        {
            if (SetField(ref _systemCommandKeywords, value))
            {
                Save();
            }
        }
    }

    public bool IncludeFilesInDefaultResults
    {
        get => _includeFilesInDefaultResults;
        set
        {
            if (SetField(ref _includeFilesInDefaultResults, value))
            {
                Save();
            }
        }
    }

    public bool IncludeAutomaticDictionary
    {
        get => _includeAutomaticDictionary;
        set
        {
            if (SetField(ref _includeAutomaticDictionary, value))
            {
                Save();
            }
        }
    }

    public int MaximumSearchResults
    {
        get => _maximumSearchResults;
        set
        {
            if (SetField(ref _maximumSearchResults, Math.Clamp(value, 3, 20)))
            {
                Save();
            }
        }
    }

    public IReadOnlyList<string> SearchScopePaths
    {
        get => _searchScopePaths;
        set
        {
            if (SetField(ref _searchScopePaths, ValidSearchScopes(value)))
            {
                Save();
            }
        }
    }

    public IReadOnlyDictionary<string, string> ApplicationAliases
    {
        get => _applicationAliases;
        set
        {
            var aliases = new Dictionary<string, string>(value, StringComparer.OrdinalIgnoreCase);
            if (SetField(ref _applicationAliases, aliases))
            {
                Save();
            }
        }
    }

    public IReadOnlyList<string> CustomApplicationPaths
    {
        get => _customApplicationPaths;
        set
        {
            if (SetField(ref _customApplicationPaths, ValidCustomApplications(value)))
            {
                Save();
            }
        }
    }

    public bool FileNavigationShowsHiddenFiles
    {
        get => _fileNavigationShowsHiddenFiles;
        set
        {
            if (SetField(ref _fileNavigationShowsHiddenFiles, value))
            {
                Save();
            }
        }
    }

    public FileNavigationSort FileNavigationSort
    {
        get => _fileNavigationSort;
        set
        {
            if (SetField(ref _fileNavigationSort, value))
            {
                Save();
            }
        }
    }

    public bool FileNavigationSortAscending
    {
        get => _fileNavigationSortAscending;
        set
        {
            if (SetField(ref _fileNavigationSortAscending, value))
            {
                Save();
            }
        }
    }

    public bool FileNavigationFoldersFirst
    {
        get => _fileNavigationFoldersFirst;
        set
        {
            if (SetField(ref _fileNavigationFoldersFirst, value))
            {
                Save();
            }
        }
    }

    public bool ClipboardEnabled
    {
        get => _clipboardEnabled;
        set
        {
            if (SetField(ref _clipboardEnabled, value))
            {
                Save();
                NotifyHotKeyChange();
            }
        }
    }

    public bool ClipboardPaused
    {
        get => _clipboardPaused;
        set
        {
            if (SetField(ref _clipboardPaused, value))
            {
                Save();
            }
        }
    }

    public int ClipboardRetentionDays
    {
        get => _clipboardRetentionDays;
        set
        {
            var normalized = new[] { 1, 7, 30, 90 }.Contains(value) ? value : 7;
            if (SetField(ref _clipboardRetentionDays, normalized))
            {
                Save();
            }
        }
    }

    public int ClipboardMaximumItems
    {
        get => _clipboardMaximumItems;
        set
        {
            if (SetField(ref _clipboardMaximumItems, Math.Clamp(value, 50, 1_000)))
            {
                Save();
            }
        }
    }

    public int ClipboardMaximumTextCharacters
    {
        get => _clipboardMaximumTextCharacters;
        set
        {
            if (SetField(ref _clipboardMaximumTextCharacters, Math.Clamp(value, 100, 10_000)))
            {
                Save();
            }
        }
    }

    public bool ClipboardStoreImages
    {
        get => _clipboardStoreImages;
        set
        {
            if (SetField(ref _clipboardStoreImages, value))
            {
                Save();
            }
        }
    }

    public IReadOnlyList<string> ClipboardIgnoredProcessNames
    {
        get => _clipboardIgnoredProcessNames;
        set
        {
            var normalized = value
                .Select(name => name.Trim().ToLowerInvariant())
                .Where(name => !string.IsNullOrEmpty(name))
                .Distinct()
                .OrderBy(name => name)
                .ToList();
            if (SetField(ref _clipboardIgnoredProcessNames, normalized))
            {
                Save();
            }
        }
    }

    public bool ClipboardCloudSyncEnabled
    {
        get => _clipboardCloudSyncEnabled;
        set
        {
            if (SetField(ref _clipboardCloudSyncEnabled, value))
            {
                Save();
            }
        }
    }

    public string ClipboardCloudSyncFolder
    {
        get => _clipboardCloudSyncFolder;
        set
        {
            var normalized = value.Trim().Replace('\\', '/');
            if (SetField(ref _clipboardCloudSyncFolder, normalized))
            {
                Save();
            }
        }
    }

    public int ClipboardCloudSyncIntervalMinutes
    {
        get => _clipboardCloudSyncIntervalMinutes;
        set
        {
            if (SetField(ref _clipboardCloudSyncIntervalMinutes, Math.Clamp(value, 15, 240)))
            {
                Save();
            }
        }
    }

    public string? HotKeyError
    {
        get => _hotKeyError;
        set => SetField(ref _hotKeyError, value);
    }

    public string? LaunchAtLoginError
    {
        get => _launchAtLoginError;
        set => SetField(ref _launchAtLoginError, value);
    }

    public SystemCommandConfiguration SystemCommandConfiguration =>
        new(_enabledSystemCommands, _systemCommandKeywords);

    public bool IsSearchContentEnabled(SearchContentType type)
    {
        return _enabledSearchContentTypes.Contains(type);
    }

    public void SetSearchContent(SearchContentType type, bool enabled)
    {
        var updated = new HashSet<SearchContentType>(_enabledSearchContentTypes);
        if (enabled)
        {
            updated.Add(type);
        }
        else
        {
            updated.Remove(type);
        }

        EnabledSearchContentTypes = updated;
    }

    public bool IsSystemCommandEnabled(SystemCommandID id)
    {
        return _enabledSystemCommands.Contains(id);
    }

    public void SetSystemCommand(SystemCommandID id, bool enabled)
    {
        var updated = new HashSet<SystemCommandID>(_enabledSystemCommands);
        if (enabled)
        {
            updated.Add(id);
        }
        else
        {
            updated.Remove(id);
        }

        EnabledSystemCommands = updated;
    }

    public void SetSystemCommandKeyword(SystemCommandID id, string keyword)
    {
        var updated = new Dictionary<SystemCommandID, string>(_systemCommandKeywords)
        {
            [id] = keyword
        };
        SystemCommandKeywords = updated;
    }

    public void RestoreSystemCommandDefaults()
    {
        EnabledSystemCommands = AllCommands();
        SystemCommandKeywords = DefaultKeywords();
    }

    public void AddSearchScope(string path)
    {
        if (_searchScopePaths.Contains(path))
        {
            return;
        }

        SearchScopePaths = _searchScopePaths.Append(path).ToList();
    }

    public void RemoveSearchScope(string path)
    {
        SearchScopePaths = _searchScopePaths.Where(p => p != path).ToList();
    }

    public void AddApplicationAliasTarget(string path)
    {
        if (_applicationAliases.ContainsKey(path))
        {
            return;
        }

        var updated = new Dictionary<string, string>(_applicationAliases)
        {
            [path] = ""
        };
        ApplicationAliases = updated;
    }

    public void SetApplicationAliases(string path, string aliases)
    {
        if (!_applicationAliases.ContainsKey(path))
        {
            return;
        }

        var updated = new Dictionary<string, string>(_applicationAliases)
        {
            [path] = aliases
        };
        ApplicationAliases = updated;
    }

    public void RemoveApplicationAliasTarget(string path)
    {
        if (!_applicationAliases.ContainsKey(path))
        {
            return;
        }

        var updated = new Dictionary<string, string>(_applicationAliases);
        updated.Remove(path);
        ApplicationAliases = updated;
    }

    public string? AddCustomApplication(string path)
    {
        var application = ValidCustomApplications([path]);
        if (application.Count == 0)
        {
            return null;
        }

        var normalizedPath = application[0];
        if (!_customApplicationPaths.Contains(normalizedPath, StringComparer.OrdinalIgnoreCase))
        {
            CustomApplicationPaths = _customApplicationPaths.Append(normalizedPath).ToList();
        }

        return normalizedPath;
    }

    public void RemoveCustomApplication(string path)
    {
        var normalizedPath = NormalizeCustomApplicationPath(path, requireExists: false);
        if (normalizedPath is null)
        {
            return;
        }

        var updatedPaths = _customApplicationPaths
            .Where(item => !string.Equals(item, normalizedPath, StringComparison.OrdinalIgnoreCase))
            .ToList();
        var updatedAliases = _applicationAliases
            .Where(pair => !string.Equals(pair.Key, normalizedPath, StringComparison.OrdinalIgnoreCase))
            .ToDictionary(pair => pair.Key, pair => pair.Value);
        var pathsChanged = updatedPaths.Count != _customApplicationPaths.Count;
        var aliasesChanged = updatedAliases.Count != _applicationAliases.Count;
        if (!pathsChanged && !aliasesChanged)
        {
            return;
        }

        _customApplicationPaths = ValidCustomApplications(updatedPaths);
        _applicationAliases = updatedAliases;
        RaisePropertyChanged(nameof(CustomApplicationPaths));
        RaisePropertyChanged(nameof(ApplicationAliases));
        Save();
    }

    public void AddClipboardIgnoredApplication(string processName)
    {
        ClipboardIgnoredProcessNames = _clipboardIgnoredProcessNames.Append(processName).ToList();
    }

    public void RemoveClipboardIgnoredApplication(string processName)
    {
        ClipboardIgnoredProcessNames = _clipboardIgnoredProcessNames
            .Where(name => name != processName)
            .ToList();
    }

    public void SavePanelPosition(
        double left,
        double top,
        double visibleOriginX,
        double visibleOriginY,
        double visibleWidth,
        double visibleHeight,
        string? screenIdentifier)
    {
        var placement = Core.RelativePanelPlacement.Create(
            left,
            top,
            visibleOriginX,
            visibleOriginY,
            visibleWidth,
            visibleHeight);
        if (placement is null)
        {
            return;
        }

        SavedPanelTopLeft = [left, top];
        SavedPanelPlacement = new SavedPanelPlacement(
            placement.Value.HorizontalFraction,
            placement.Value.TopFraction,
            placement.Value.SourceVisibleWidth,
            placement.Value.SourceVisibleHeight,
            screenIdentifier);
        Save();
    }

    public void ClearSavedPanelPosition()
    {
        if (SavedPanelTopLeft is not null || SavedPanelPlacement is not null)
        {
            SavedPanelTopLeft = null;
            SavedPanelPlacement = null;
            Save();
        }
    }

    public void RestoreHotKeysWithoutNotifying(HotKeyDefinition launcher, HotKeyDefinition clipboard)
    {
        _launcherHotKey = launcher;
        _clipboardHotKey = clipboard;
        RaisePropertyChanged(nameof(LauncherHotKey));
        RaisePropertyChanged(nameof(ClipboardHotKey));
        Save();
    }

    public void ClearUsageLearning()
    {
        ClearUsageLearningRequested?.Invoke();
    }

    public void RestoreDefaults()
    {
        LaunchAtLogin = false;
        LauncherHotKey = HotKeyDefinition.LauncherDefault;
        ClipboardHotKey = HotKeyDefinition.ClipboardDefault;
        Theme = AppTheme.System;
        AccentColor = AppAccentColor.Blue;
        LauncherAppearanceStyle = LauncherAppearanceStyle.Minimal;
        PanelPosition = PanelPosition.Upper;
        ScreenPreference = ScreenPreference.Main;
        ForcedKeyboardInputSourceID = "";
        ShowTrayIcon = true;
        CompactResults = false;
        PanelWidth = 720;
        PanelCornerRadius = 14;
        ShowSubtitles = true;
        ShowNumberShortcuts = true;
        SearchInputDelay = 0.15;
        PreviewSelectionDelay = 0.3;
        ResultExpansionDuration = 0.15;
        EnabledSearchContentTypes = AllContentTypes();
        RestoreSystemCommandDefaults();
        IncludeFilesInDefaultResults = true;
        IncludeAutomaticDictionary = true;
        MaximumSearchResults = 8;
        SearchScopePaths = [];
        ApplicationAliases = new Dictionary<string, string>();
        CustomApplicationPaths = [];
        FileNavigationShowsHiddenFiles = false;
        FileNavigationSort = FileNavigationSort.Name;
        FileNavigationSortAscending = true;
        FileNavigationFoldersFirst = true;
        ClipboardEnabled = true;
        ClipboardPaused = false;
        ClipboardRetentionDays = 7;
        ClipboardMaximumItems = 300;
        ClipboardMaximumTextCharacters = 1_000;
        ClipboardStoreImages = false;
        ClipboardIgnoredProcessNames = [];
    }

    private void NotifyHotKeyChange()
    {
        HotKeysChanged?.Invoke();
    }

    private void ConfigureLaunchAtLogin()
    {
        try
        {
            LaunchAtLoginService.SetEnabled(LaunchAtLogin);
            LaunchAtLoginError = null;
        }
        catch (Exception exception)
        {
            LaunchAtLoginError = $"无法修改登录启动：{exception.Message}";
        }
    }

    private void Load()
    {
        AppPaths.EnsureDirectories();
        if (!File.Exists(AppPaths.SettingsFile))
        {
            ApplyDefaults();
            return;
        }

        try
        {
            var json = File.ReadAllText(AppPaths.SettingsFile);
            var data = JsonSerializer.Deserialize<PreferencesData>(json, JsonOptions);
            if (data is null)
            {
                ApplyDefaults();
                return;
            }

            Migrate(data);
            _launchAtLogin = LaunchAtLoginService.IsEnabled;
            _launcherHotKey = ValidHotKey(data.LauncherHotKey, HotKeyDefinition.LauncherDefault);
            _clipboardHotKey = ValidHotKey(data.ClipboardHotKey, HotKeyDefinition.ClipboardDefault);
            _theme = data.Theme ?? AppTheme.System;
            _accentColor = data.AccentColor ?? AppAccentColor.Blue;
            _launcherAppearanceStyle = data.LauncherAppearanceStyle ?? LauncherAppearanceStyle.Minimal;
            _panelPosition = data.PanelPosition ?? PanelPosition.Upper;
            _screenPreference = data.ScreenPreference ?? ScreenPreference.Main;
            _savedPanelTopLeft = data.SavedPanelTopLeft;
            _savedPanelPlacement = ValidSavedPlacement(data.SavedPanelPlacement);
            _forcedKeyboardInputSourceID = data.ForcedKeyboardInputSourceID ?? "";
            _showTrayIcon = data.ShowTrayIcon ?? true;
            _compactResults = data.CompactResults ?? false;
            _panelWidth = Math.Clamp(data.PanelWidth ?? 720, 640, 960);
            _panelCornerRadius = Math.Clamp(data.PanelCornerRadius ?? 14, 10, 20);
            _showSubtitles = data.ShowSubtitles ?? true;
            _showNumberShortcuts = data.ShowNumberShortcuts ?? true;
            _searchInputDelay = Math.Clamp(data.SearchInputDelay ?? 0.15, 0.05, 0.4);
            _previewSelectionDelay = Math.Clamp(data.PreviewSelectionDelay ?? 0.3, 0, 0.8);
            _resultExpansionDuration = Math.Clamp(data.ResultExpansionDuration ?? 0.15, 0, 0.4);
            _lastLauncherQuery = data.LastLauncherQuery ?? "";
            _enabledSearchContentTypes = data.EnabledSearchContentTypes is { Count: > 0 }
                ? data.EnabledSearchContentTypes.ToHashSet()
                : AllContentTypes();
            _enabledSystemCommands = data.EnabledSystemCommands is { Count: > 0 }
                ? data.EnabledSystemCommands.ToHashSet()
                : AllCommands();
            var storedKeywords = data.SystemCommandKeywords ?? [];
            _systemCommandKeywords = Enum.GetValues<SystemCommandID>().ToDictionary(
                id => id,
                id => storedKeywords.TryGetValue(id, out var keyword) && !string.IsNullOrEmpty(keyword)
                    ? keyword
                    : id.DefaultKeyword());
            _includeFilesInDefaultResults = data.IncludeFilesInDefaultResults ?? true;
            _includeAutomaticDictionary = data.IncludeAutomaticDictionary ?? true;
            _maximumSearchResults = Math.Clamp(data.MaximumSearchResults ?? 8, 3, 20);
            _searchScopePaths = ValidSearchScopes(data.SearchScopePaths ?? []);
            _applicationAliases = new Dictionary<string, string>(
                data.ApplicationAliases ?? new Dictionary<string, string>(),
                StringComparer.OrdinalIgnoreCase);
            _customApplicationPaths = ValidCustomApplicationReferences(data.CustomApplicationPaths ?? []);
            _fileNavigationShowsHiddenFiles = data.FileNavigationShowsHiddenFiles ?? false;
            _fileNavigationSort = data.FileNavigationSort ?? FileNavigationSort.Name;
            _fileNavigationSortAscending = data.FileNavigationSortAscending ?? true;
            _fileNavigationFoldersFirst = data.FileNavigationFoldersFirst ?? true;
            _clipboardEnabled = data.ClipboardEnabled ?? true;
            _clipboardPaused = data.ClipboardPaused ?? false;
            _clipboardRetentionDays = new[] { 1, 7, 30, 90 }.Contains(data.ClipboardRetentionDays ?? 7)
                ? data.ClipboardRetentionDays!.Value
                : 7;
            _clipboardMaximumItems = Math.Clamp(data.ClipboardMaximumItems ?? 300, 50, 1_000);
            _clipboardMaximumTextCharacters = Math.Clamp(
                data.ClipboardMaximumTextCharacters ?? 1_000,
                100,
                10_000);
            _clipboardStoreImages = data.ClipboardStoreImages ?? false;
            _clipboardIgnoredProcessNames = (data.ClipboardIgnoredProcessNames ?? [])
                .Select(name => name.Trim().ToLowerInvariant())
                .Where(name => !string.IsNullOrEmpty(name))
                .Distinct()
                .OrderBy(name => name)
                .ToList();
            _clipboardCloudSyncEnabled = data.ClipboardCloudSyncEnabled ?? false;
            _clipboardCloudSyncFolder = string.IsNullOrWhiteSpace(data.ClipboardCloudSyncFolder)
                ? "YTools/clipboard-sync"
                : data.ClipboardCloudSyncFolder.Trim().Replace('\\', '/');
            _clipboardCloudSyncIntervalMinutes = Math.Clamp(data.ClipboardCloudSyncIntervalMinutes ?? 15, 15, 240);
            Save();
        }
        catch
        {
            ApplyDefaults();
        }
    }

    private void ApplyDefaults()
    {
        _launchAtLogin = LaunchAtLoginService.IsEnabled;
        _launcherHotKey = HotKeyDefinition.LauncherDefault;
        _clipboardHotKey = HotKeyDefinition.ClipboardDefault;
        _theme = AppTheme.System;
        _accentColor = AppAccentColor.Blue;
        _launcherAppearanceStyle = LauncherAppearanceStyle.Minimal;
        _panelPosition = PanelPosition.Upper;
        _screenPreference = ScreenPreference.Main;
        _enabledSearchContentTypes = AllContentTypes();
        _enabledSystemCommands = AllCommands();
        _systemCommandKeywords = DefaultKeywords();
        _customApplicationPaths = [];
        _clipboardCloudSyncEnabled = false;
        _clipboardCloudSyncFolder = "YTools/clipboard-sync";
        _clipboardCloudSyncIntervalMinutes = 15;
        Save();
    }

    private void Save()
    {
        try
        {
            var data = new PreferencesData
            {
                SchemaVersion = CurrentSchemaVersion,
                LaunchAtLogin = _launchAtLogin,
                LauncherHotKey = _launcherHotKey,
                ClipboardHotKey = _clipboardHotKey,
                Theme = _theme,
                AccentColor = _accentColor,
                LauncherAppearanceStyle = _launcherAppearanceStyle,
                PanelPosition = _panelPosition,
                ScreenPreference = _screenPreference,
                SavedPanelTopLeft = _savedPanelTopLeft,
                SavedPanelPlacement = _savedPanelPlacement,
                ForcedKeyboardInputSourceID = _forcedKeyboardInputSourceID,
                ShowTrayIcon = _showTrayIcon,
                CompactResults = _compactResults,
                PanelWidth = _panelWidth,
                PanelCornerRadius = _panelCornerRadius,
                ShowSubtitles = _showSubtitles,
                ShowNumberShortcuts = _showNumberShortcuts,
                SearchInputDelay = _searchInputDelay,
                PreviewSelectionDelay = _previewSelectionDelay,
                ResultExpansionDuration = _resultExpansionDuration,
                LastLauncherQuery = _lastLauncherQuery,
                EnabledSearchContentTypes = _enabledSearchContentTypes.ToList(),
                EnabledSystemCommands = _enabledSystemCommands.ToList(),
                SystemCommandKeywords = _systemCommandKeywords.ToDictionary(
                    pair => pair.Key,
                    pair => pair.Value),
                IncludeFilesInDefaultResults = _includeFilesInDefaultResults,
                IncludeAutomaticDictionary = _includeAutomaticDictionary,
                MaximumSearchResults = _maximumSearchResults,
                SearchScopePaths = _searchScopePaths.ToList(),
                ApplicationAliases = _applicationAliases.ToDictionary(
                    pair => pair.Key,
                    pair => pair.Value),
                CustomApplicationPaths = _customApplicationPaths.ToList(),
                FileNavigationShowsHiddenFiles = _fileNavigationShowsHiddenFiles,
                FileNavigationSort = _fileNavigationSort,
                FileNavigationSortAscending = _fileNavigationSortAscending,
                FileNavigationFoldersFirst = _fileNavigationFoldersFirst,
                ClipboardEnabled = _clipboardEnabled,
                ClipboardPaused = _clipboardPaused,
                ClipboardRetentionDays = _clipboardRetentionDays,
                ClipboardMaximumItems = _clipboardMaximumItems,
                ClipboardMaximumTextCharacters = _clipboardMaximumTextCharacters,
                ClipboardStoreImages = _clipboardStoreImages,
                ClipboardIgnoredProcessNames = _clipboardIgnoredProcessNames.ToList(),
                ClipboardCloudSyncEnabled = _clipboardCloudSyncEnabled,
                ClipboardCloudSyncFolder = _clipboardCloudSyncFolder,
                ClipboardCloudSyncIntervalMinutes = _clipboardCloudSyncIntervalMinutes
            };
            var json = JsonSerializer.Serialize(data, JsonOptions);
            File.WriteAllText(AppPaths.SettingsFile, json);
            AppPaths.RestrictFile(AppPaths.SettingsFile);
        }
        catch
        {
            // Preferences are non-critical; never crash the launcher for a write failure.
        }
    }

    private static void Migrate(PreferencesData data)
    {
        if (data.SchemaVersion < 6
            && data.PanelWidth is { } width
            && Math.Abs(width - 860) < 0.5)
        {
            data.PanelWidth = 720;
        }
    }

    private static HotKeyDefinition ValidHotKey(HotKeyDefinition? value, HotKeyDefinition fallback)
    {
        return value is { KeyCode: > 0 and < 256 } ? value.Value : fallback;
    }

    private static SavedPanelPlacement? ValidSavedPlacement(SavedPanelPlacement? placement)
    {
        if (placement is null)
        {
            return null;
        }

        return Core.RelativePanelPlacement.Create(
            placement.HorizontalFraction,
            placement.TopFraction,
            placement.SourceVisibleWidth,
            placement.SourceVisibleHeight) is null
            ? null
            : placement;
    }

    private static IReadOnlyList<string> ValidSearchScopes(IEnumerable<string> paths)
    {
        var seen = new HashSet<string>();
        var output = new List<string>();
        foreach (var path in paths)
        {
            var full = Path.GetFullPath(path);
            if (Directory.Exists(full) && seen.Add(full))
            {
                output.Add(full);
            }
        }

        return output;
    }

    private static IReadOnlyList<string> ValidCustomApplications(IEnumerable<string> paths)
    {
        return ValidCustomApplicationReferences(paths, requireExists: true);
    }

    private static IReadOnlyList<string> ValidCustomApplicationReferences(
        IEnumerable<string> paths,
        bool requireExists = false)
    {
        var output = new List<string>();
        foreach (var path in paths)
        {
            var normalizedPath = NormalizeCustomApplicationPath(path, requireExists);
            if (normalizedPath is not null)
            {
                output.Add(normalizedPath);
            }
        }

        return output
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .ThenBy(path => path, StringComparer.Ordinal)
            .ToList();
    }

    private static string? NormalizeCustomApplicationPath(string path, bool requireExists)
    {
        if (string.IsNullOrWhiteSpace(path)
            || !Path.IsPathFullyQualified(path)
            || path.StartsWith("\\\\", StringComparison.Ordinal))
        {
            return null;
        }

        try
        {
            var fullPath = Path.GetFullPath(path);
            var extension = Path.GetExtension(fullPath);
            var supported = extension.Equals(".exe", StringComparison.OrdinalIgnoreCase)
                || extension.Equals(".lnk", StringComparison.OrdinalIgnoreCase)
                || extension.Equals(".appref-ms", StringComparison.OrdinalIgnoreCase);
            return supported && (!requireExists || File.Exists(fullPath))
                ? fullPath
                : null;
        }
        catch (ArgumentException)
        {
            return null;
        }
        catch (NotSupportedException)
        {
            return null;
        }
        catch (PathTooLongException)
        {
            return null;
        }
    }

    private static IReadOnlySet<SearchContentType> AllContentTypes()
    {
        return Enum.GetValues<SearchContentType>().ToHashSet();
    }

    private static IReadOnlySet<SystemCommandID> AllCommands()
    {
        return Enum.GetValues<SystemCommandID>().ToHashSet();
    }

    private static IReadOnlyDictionary<SystemCommandID, string> DefaultKeywords()
    {
        return Enum.GetValues<SystemCommandID>().ToDictionary(id => id, id => id.DefaultKeyword());
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    private sealed class PreferencesData
    {
        public int SchemaVersion { get; set; }

        public bool LaunchAtLogin { get; set; }

        public HotKeyDefinition? LauncherHotKey { get; set; }

        public HotKeyDefinition? ClipboardHotKey { get; set; }

        public AppTheme? Theme { get; set; }

        public AppAccentColor? AccentColor { get; set; }

        public LauncherAppearanceStyle? LauncherAppearanceStyle { get; set; }

        public PanelPosition? PanelPosition { get; set; }

        public ScreenPreference? ScreenPreference { get; set; }

        public double[]? SavedPanelTopLeft { get; set; }

        public SavedPanelPlacement? SavedPanelPlacement { get; set; }

        public string? ForcedKeyboardInputSourceID { get; set; }

        public bool? ShowTrayIcon { get; set; }

        public bool? CompactResults { get; set; }

        public double? PanelWidth { get; set; }

        public double? PanelCornerRadius { get; set; }

        public bool? ShowSubtitles { get; set; }

        public bool? ShowNumberShortcuts { get; set; }

        public double? SearchInputDelay { get; set; }

        public double? PreviewSelectionDelay { get; set; }

        public double? ResultExpansionDuration { get; set; }

        public string? LastLauncherQuery { get; set; }

        public List<SearchContentType>? EnabledSearchContentTypes { get; set; }

        public List<SystemCommandID>? EnabledSystemCommands { get; set; }

        public Dictionary<SystemCommandID, string>? SystemCommandKeywords { get; set; }

        public bool? IncludeFilesInDefaultResults { get; set; }

        public bool? IncludeAutomaticDictionary { get; set; }

        public int? MaximumSearchResults { get; set; }

        public List<string>? SearchScopePaths { get; set; }

        public Dictionary<string, string>? ApplicationAliases { get; set; }

        public List<string>? CustomApplicationPaths { get; set; }

        public bool? FileNavigationShowsHiddenFiles { get; set; }

        public FileNavigationSort? FileNavigationSort { get; set; }

        public bool? FileNavigationSortAscending { get; set; }

        public bool? FileNavigationFoldersFirst { get; set; }

        public bool? ClipboardEnabled { get; set; }

        public bool? ClipboardPaused { get; set; }

        public int? ClipboardRetentionDays { get; set; }

        public int? ClipboardMaximumItems { get; set; }

        public int? ClipboardMaximumTextCharacters { get; set; }

        public bool? ClipboardStoreImages { get; set; }

        public List<string>? ClipboardIgnoredProcessNames { get; set; }

        public bool? ClipboardCloudSyncEnabled { get; set; }

        public string? ClipboardCloudSyncFolder { get; set; }

        public int? ClipboardCloudSyncIntervalMinutes { get; set; }
    }
}
