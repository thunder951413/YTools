using System.IO;
using YTools.Core;
using YTools.Infrastructure;
using YTools.Models;
using YTools.ModuleKit;
using YTools.Services.Modules;

namespace YTools.Services;

/// <summary>
/// Query state, ordering and selection facade for the launcher UI. File search
/// runs on its own debounce (like the macOS Spotlight path); every other
/// provider runs through the SearchCoordinator.
/// </summary>
public sealed class LauncherModel : ObservableObject
{
    private readonly AppPreferences _preferences;
    private readonly SnippetManager _snippets;
    private readonly RecentDocumentsManager _recentDocuments;
    private readonly FileSearchService _fileSearch;
    private readonly SearchCoordinator _searchCoordinator;
    private readonly ResultAggregator _resultAggregator;
    private readonly ActionDispatcher _actionDispatcher;
    private readonly ActionMenuController _actionMenu = new();
    private readonly FileBufferStore _fileBuffer = new();
    private readonly DebouncedAction _searchDebouncer = new();
    private readonly DebouncedAction _fileSearchDebouncer = new();
    private readonly DebouncedAction _previewDebouncer = new();
    private CancellationTokenSource? _searchCancellation;
    private string _query = "";
    private List<LauncherResult> _results = [];
    private List<LauncherResult> _fileResults = [];
    private List<LauncherResult> _backgroundResults = [];
    private bool _isSearchPending;
    private int _selectedIndex;
    private bool _showsPreview;
    private string? _displayedPreviewPath;
    private string? _pinnedPreviewPath;
    private bool _momentaryPreviewActive;

    public LauncherModel(
        AppPreferences preferences,
        SnippetManager snippets,
        RecentDocumentsManager recentDocuments,
        Action onOpenSettings,
        Action<string> onShowLargeType,
        Func<System.Windows.Window?> ownerProvider)
    {
        _preferences = preferences;
        _snippets = snippets;
        _recentDocuments = recentDocuments;
        _fileSearch = new FileSearchService();
        _searchCoordinator = new SearchCoordinator(new SpellingService());
        _resultAggregator = new ResultAggregator();
        _actionDispatcher = new ActionDispatcher(
            snippets,
            recentDocuments,
            onOpenSettings,
            onShowLargeType,
            ownerProvider);
        preferences.PropertyChanged += (_, args) =>
        {
            switch (args.PropertyName)
            {
                case nameof(AppPreferences.EnabledSearchContentTypes):
                case nameof(AppPreferences.ApplicationAliases):
                    RefreshImmediately();
                    break;
                case nameof(AppPreferences.SearchInputDelay):
                    ScheduleSearch();
                    break;
                case nameof(AppPreferences.PreviewSelectionDelay):
                    SchedulePreviewUpdate();
                    break;
            }
        };
        _ = _searchCoordinator.PrepareAsync();
    }

    public string Query
    {
        get => _query;
        set
        {
            if (SetField(ref _query, value))
            {
                QueryDidChange();
            }
        }
    }

    public IReadOnlyList<LauncherResult> Results => _results;

    public bool IsSearchPending
    {
        get => _isSearchPending;
        private set => SetField(ref _isSearchPending, value);
    }

    public int SelectedIndex
    {
        get => _selectedIndex;
        set
        {
            if (SetField(ref _selectedIndex, value))
            {
                SchedulePreviewUpdate();
            }
        }
    }

    public bool ShowsPreview
    {
        get => _showsPreview;
        set
        {
            if (SetField(ref _showsPreview, value))
            {
                if (!_showsPreview)
                {
                    _displayedPreviewPath = null;
                    RaisePropertyChanged(nameof(DisplayedPreviewPath));
                }
            }
        }
    }

    public string? DisplayedPreviewPath
    {
        get => _displayedPreviewPath;
        private set => SetField(ref _displayedPreviewPath, value);
    }

    public IReadOnlyList<LauncherAction> Actions => _actionMenu.Actions;

    public bool IsShowingActions => _actionMenu.IsShowing;

    public string ActionTitle => _actionMenu.Title;

    public int SelectedActionIndex
    {
        get => _actionMenu.SelectedIndex;
        set => _actionMenu.SelectedIndex = value;
    }

    public IReadOnlyList<string> FileBuffer => _fileBuffer.Paths;

    public string? SelectedFilePath
    {
        get
        {
            if (_pinnedPreviewPath is not null)
            {
                return _pinnedPreviewPath;
            }

            if (IsShowingActions && _actionMenu.Subject?.ResourcePath is { } subjectPath)
            {
                return subjectPath;
            }

            return _results.Count > _selectedIndex && _selectedIndex >= 0
                ? _results[_selectedIndex].FilePath
                : null;
        }
    }

    public int VisibleItemCount => IsShowingActions ? Actions.Count : _results.Count;

    public bool IsFileNavigationActive
    {
        get
        {
            var trimmed = Query.Trim();
            return trimmed.StartsWith('/')
                || trimmed.StartsWith('~')
                || trimmed.StartsWith(@"\\", StringComparison.Ordinal)
                || (trimmed.Length >= 2 && trimmed[1] == ':');
        }
    }

    public bool ActivateSelected()
    {
        if (IsShowingActions)
        {
            return ActivateSelectedAction();
        }

        if (_results.Count <= _selectedIndex || _selectedIndex < 0)
        {
            return false;
        }

        return Activate(_results[_selectedIndex]);
    }

    public bool Activate(LauncherResult result, bool recordUsage = true)
    {
        if (recordUsage)
        {
            _resultAggregator.Record(result, Query);
        }

        return Apply(_actionDispatcher.Execute(result.Action));
    }

    public void MoveSelection(int offset)
    {
        if (IsShowingActions)
        {
            _actionMenu.MoveSelection(offset);
            RaisePropertyChanged(nameof(Actions));
            RaisePropertyChanged(nameof(SelectedActionIndex));
            RaisePropertyChanged(nameof(VisibleItemCount));
            return;
        }

        if (_results.Count == 0)
        {
            return;
        }

        SelectedIndex = (_selectedIndex + offset + _results.Count) % _results.Count;
    }

    public bool ActivateResult(int index)
    {
        if (IsShowingActions || _results.Count <= index || index < 0)
        {
            return false;
        }

        SelectedIndex = index;
        return Activate(_results[index]);
    }

    public void TogglePreview()
    {
        if (SelectedFilePath is null)
        {
            ShowsPreview = false;
            return;
        }

        ShowsPreview = !ShowsPreview;
        if (ShowsPreview)
        {
            DisplayPreviewImmediately();
        }
        else
        {
            _pinnedPreviewPath = null;
        }

        _momentaryPreviewActive = false;
    }

    public bool BeginMomentaryPreview()
    {
        if (IsShowingActions || SelectedFilePath is null || ShowsPreview)
        {
            return false;
        }

        ShowsPreview = true;
        DisplayPreviewImmediately();
        _momentaryPreviewActive = true;
        return true;
    }

    public void EndMomentaryPreview()
    {
        if (!_momentaryPreviewActive)
        {
            return;
        }

        ShowsPreview = false;
        _pinnedPreviewPath = null;
        _momentaryPreviewActive = false;
    }

    public void EndPreviewSession()
    {
        ShowsPreview = false;
        _pinnedPreviewPath = null;
        _momentaryPreviewActive = false;
    }

    public bool ShowActionsForSelected()
    {
        if (IsShowingActions || _results.Count <= _selectedIndex || _selectedIndex < 0)
        {
            return false;
        }

        if (!_actionMenu.Show(_results[_selectedIndex]))
        {
            return false;
        }

        ShowsPreview = false;
        _pinnedPreviewPath = null;
        RaisePropertyChanged(nameof(Actions));
        RaisePropertyChanged(nameof(IsShowingActions));
        RaisePropertyChanged(nameof(ActionTitle));
        RaisePropertyChanged(nameof(VisibleItemCount));
        return true;
    }

    public bool DismissSecondaryView()
    {
        if (ShowsPreview)
        {
            ShowsPreview = false;
            _pinnedPreviewPath = null;
            _momentaryPreviewActive = false;
            return true;
        }

        if (IsShowingActions)
        {
            DismissActions();
            return true;
        }

        return false;
    }

    public bool NavigateToParent()
    {
        if (!IsFileNavigationActive)
        {
            return false;
        }

        var trimmed = Query.Trim();
        var expanded = ExpandTilde(trimmed);
        var withoutTrailingSeparator = expanded.Length > 1
            && (expanded.EndsWith('\\') || expanded.EndsWith('/'))
            ? expanded[..^1]
            : expanded;
        var parent = Path.GetDirectoryName(withoutTrailingSeparator);
        if (string.IsNullOrEmpty(parent))
        {
            return false;
        }

        Query = DisplayPath(parent) + "\\";
        return true;
    }

    public bool IsBuffered(LauncherResult result)
    {
        return result.ResourcePath is { } path && _fileBuffer.Contains(path);
    }

    public bool AddSelectedToBuffer(bool moveToNext)
    {
        if (IsShowingActions
            || _results.Count <= _selectedIndex
            || _selectedIndex < 0
            || _results[_selectedIndex].ResourcePath is not { } path)
        {
            return false;
        }

        _fileBuffer.Add(path);
        RaisePropertyChanged(nameof(FileBuffer));
        if (moveToNext)
        {
            MoveSelection(1);
        }

        return true;
    }

    public bool RemoveLastBufferedItem()
    {
        var removed = _fileBuffer.RemoveLast();
        if (removed)
        {
            RaisePropertyChanged(nameof(FileBuffer));
        }

        return removed;
    }

    public void ClearFileBuffer()
    {
        _fileBuffer.Clear();
        RaisePropertyChanged(nameof(FileBuffer));
    }

    public bool ShowFileBufferActions()
    {
        if (!_actionMenu.ShowForBufferedPaths(_fileBuffer.Paths))
        {
            return false;
        }

        ShowsPreview = false;
        _pinnedPreviewPath = null;
        RaisePropertyChanged(nameof(Actions));
        RaisePropertyChanged(nameof(IsShowingActions));
        RaisePropertyChanged(nameof(ActionTitle));
        RaisePropertyChanged(nameof(VisibleItemCount));
        return true;
    }

    public bool RevealSelected()
    {
        if (SelectedFilePath is not { } path)
        {
            return false;
        }

        if (_results.Count > _selectedIndex && _selectedIndex >= 0)
        {
            _resultAggregator.Record(_results[_selectedIndex], Query);
        }

        _actionDispatcher.Reveal(path);
        return true;
    }

    public void Reveal(string path)
    {
        _actionDispatcher.Reveal(path);
    }

    public void CopyPath(string path)
    {
        _actionDispatcher.CopyPath(path);
    }

    public void ClearUsageLearning()
    {
        _resultAggregator.ClearLearning();
        RebuildResults();
    }

    public bool ClearQuery()
    {
        if (string.IsNullOrEmpty(Query))
        {
            return false;
        }

        Query = "";
        return true;
    }

    public string? SelectedLargeTypeText
    {
        get
        {
            if (IsShowingActions || _results.Count <= _selectedIndex || _selectedIndex < 0)
            {
                return null;
            }

            var result = _results[_selectedIndex];
            return result.Action is ResultAction.Copy copy
                ? copy.Text
                : string.IsNullOrEmpty(result.Title) ? null : result.Title;
        }
    }

    public void Dispose()
    {
        _searchDebouncer.Cancel();
        _fileSearchDebouncer.Cancel();
        _previewDebouncer.Cancel();
        _searchCancellation?.Cancel();
        _fileSearch.Dispose();
    }

    private void QueryDidChange()
    {
        if (IsShowingActions)
        {
            DismissActions();
        }

        if (ShowsPreview || _pinnedPreviewPath is not null)
        {
            EndPreviewSession();
        }

        _searchCancellation?.Cancel();
        _fileSearchDebouncer.Cancel();
        if (string.IsNullOrWhiteSpace(Query))
        {
            ResetForEmptyQuery();
        }
        else
        {
            if (!IsSearchPending)
            {
                IsSearchPending = true;
            }

            if (_results.Count > 0)
            {
                _results = [];
                RaisePropertyChanged(nameof(Results));
                if (SelectedIndex != 0)
                {
                    SelectedIndex = 0;
                }
            }

            ScheduleSearch();
        }
    }

    private void ScheduleSearch()
    {
        if (string.IsNullOrWhiteSpace(Query))
        {
            return;
        }

        var delayMilliseconds = (int)(_preferences.SearchInputDelay * 1_000);
        _searchDebouncer.Schedule(TimeSpan.FromMilliseconds(delayMilliseconds), PerformSearch);
    }

    private void RefreshImmediately()
    {
        _searchDebouncer.Cancel();
        _fileSearchDebouncer.Cancel();
        if (string.IsNullOrWhiteSpace(Query))
        {
            ResetForEmptyQuery();
            return;
        }

        PerformSearch();
    }

    private void PerformSearch()
    {
        var requestedQuery = Query;
        if (string.IsNullOrWhiteSpace(requestedQuery))
        {
            ResetForEmptyQuery();
            return;
        }

        if (!IsSearchPending)
        {
            IsSearchPending = true;
        }

        _fileResults = [];
        _backgroundResults = [];
        _searchCancellation?.Cancel();
        var cancellation = new CancellationTokenSource();
        _searchCancellation = cancellation;

        var request = new BackgroundSearchRequest(
            requestedQuery,
            IsFileNavigationActive,
            _preferences.FileNavigationShowsHiddenFiles,
            _preferences.FileNavigationSort,
            _preferences.FileNavigationSortAscending,
            _preferences.FileNavigationFoldersFirst,
            _preferences.EnabledSearchContentTypes,
            _preferences.ApplicationAliases,
            _preferences.SearchScopePaths,
            _preferences.MaximumSearchResults,
            _preferences.IncludeFilesInDefaultResults,
            MakeRequestModules(requestedQuery),
            cancellation.Token);

        _ = Task.Run(
                () => _searchCoordinator.SearchAsync(request),
                cancellation.Token)
            .ContinueWith(task =>
            {
                if (task.IsCompletedSuccessfully && Query == requestedQuery)
                {
                    _backgroundResults = task.Result.ToList();
                    IsSearchPending = false;
                    RebuildResults();
                }
                else if (task.IsFaulted && Query == requestedQuery)
                {
                    _backgroundResults = [];
                    IsSearchPending = false;
                    RebuildResults();
                }
            }, TaskScheduler.FromCurrentSynchronizationContext());

        var fileQuery = IsFileNavigationActive || !_preferences.IsSearchContentEnabled(SearchContentType.Files)
            ? ""
            : requestedQuery;
        ScheduleFileSearch(fileQuery, requestedQuery, cancellation.Token);
        RebuildResults();
    }

    private void ScheduleFileSearch(string fileQuery, string requestedQuery, CancellationToken cancellationToken)
    {
        if (string.IsNullOrEmpty(fileQuery))
        {
            return;
        }

        var additionalDelay = Math.Max(0, 0.3 - _preferences.SearchInputDelay);
        var start = () =>
        {
            if (Query != requestedQuery)
            {
                return;
            }

            _ = _fileSearch.SearchAsync(
                    fileQuery,
                    FileSearchMode.Default,
                    _preferences.SearchScopePaths,
                    _preferences.MaximumSearchResults,
                    cancellationToken)
                .ContinueWith(task =>
                {
                    if (task.IsCompletedSuccessfully && Query == requestedQuery)
                    {
                        _fileResults = task.Result.ToList();
                        RebuildResults();
                    }
                }, TaskScheduler.FromCurrentSynchronizationContext());
        };
        if (additionalDelay <= 0)
        {
            start();
        }
        else
        {
            var milliseconds = (int)(additionalDelay * 1_000);
            _fileSearchDebouncer.Schedule(TimeSpan.FromMilliseconds(milliseconds), start);
        }
    }

    private void ResetForEmptyQuery()
    {
        _searchDebouncer.Cancel();
        _searchCancellation?.Cancel();
        _fileResults = [];
        _backgroundResults = [];
        if (IsSearchPending)
        {
            IsSearchPending = false;
        }

        if (_results.Count > 0)
        {
            _results = [];
            RaisePropertyChanged(nameof(Results));
        }

        if (SelectedIndex != 0)
        {
            SelectedIndex = 0;
        }
    }

    private void RebuildResults()
    {
        var aggregated = _resultAggregator.Aggregate(
            _backgroundResults,
            _fileResults,
            Query,
            _results,
            _selectedIndex);
        _results = aggregated.Results.ToList();
        SelectedIndex = aggregated.SelectedIndex;
        RaisePropertyChanged(nameof(Results));
        RaisePropertyChanged(nameof(VisibleItemCount));
        if (SelectedFilePath is null)
        {
            ShowsPreview = false;
        }
        else if (ShowsPreview)
        {
            SchedulePreviewUpdate();
        }
    }

    private IReadOnlyList<RegisteredSearchModule> MakeRequestModules(string query)
    {
        var clipboardText = SnippetSearchModule.Accepts(query)
            ? (System.Windows.Clipboard.ContainsText() ? System.Windows.Clipboard.GetText() : "")
            : "";
        return
        [
            new RegisteredSearchModule(
                _snippets.SearchModule(clipboardText, DateTimeOffset.UtcNow),
                SearchContentType.Snippets,
                new ModuleResultPolicy()),
            new RegisteredSearchModule(
                _recentDocuments.SearchModule(),
                SearchContentType.RecentDocuments,
                new ModuleResultPolicy(
                    allowedCapabilities: new HashSet<ModuleCapability> { ModuleCapability.LocalFileRead })),
            new RegisteredSearchModule(
                new DictionaryModule(new DictionaryService(), _preferences.IncludeAutomaticDictionary),
                SearchContentType.Dictionary,
                new ModuleResultPolicy()),
            new RegisteredSearchModule(
                new SystemCommandsModule(_preferences.SystemCommandConfiguration),
                SearchContentType.SystemTools,
                new ModuleResultPolicy(allowsPrivilegedActions: true))
        ];
    }

    private bool ActivateSelectedAction()
    {
        if (_actionMenu.SelectedAction is not { } action)
        {
            return false;
        }

        if (_actionMenu.Subject is { } subject)
        {
            _resultAggregator.Record(subject, Query);
        }

        return Apply(_actionDispatcher.Execute(action));
    }

    private void DismissActions()
    {
        _actionMenu.Dismiss();
        RaisePropertyChanged(nameof(Actions));
        RaisePropertyChanged(nameof(IsShowingActions));
        RaisePropertyChanged(nameof(ActionTitle));
        RaisePropertyChanged(nameof(VisibleItemCount));
    }

    private void DisplayPreviewImmediately()
    {
        DisplayedPreviewPath = SelectedFilePath;
    }

    private void SchedulePreviewUpdate()
    {
        if (!ShowsPreview || _pinnedPreviewPath is not null)
        {
            return;
        }

        var requestedPath = SelectedFilePath;
        var delayMilliseconds = (int)(_preferences.PreviewSelectionDelay * 1_000);
        if (delayMilliseconds <= 0)
        {
            DisplayedPreviewPath = requestedPath;
            return;
        }

        _previewDebouncer.Schedule(TimeSpan.FromMilliseconds(delayMilliseconds), () =>
        {
            if (ShowsPreview && _pinnedPreviewPath is null && SelectedFilePath == requestedPath)
            {
                DisplayedPreviewPath = requestedPath;
            }
        });
    }

    private bool Apply(ActionExecutionResult result)
    {
        switch (result.Outcome)
        {
            case ActionExecutionOutcome.HidePanel:
                return true;
            case ActionExecutionOutcome.KeepPanel:
                return false;
            case ActionExecutionOutcome.Navigate when result.Path is { } path:
                Query = path;
                RefreshImmediately();
                return false;
            case ActionExecutionOutcome.Preview when result.Path is { } path:
                DismissActions();
                _pinnedPreviewPath = path;
                DisplayedPreviewPath = path;
                ShowsPreview = true;
                return false;
            case ActionExecutionOutcome.ClearFileBufferAndHide:
                ClearFileBuffer();
                return true;
            default:
                return false;
        }
    }

    private static string ExpandTilde(string path)
    {
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (path == "~")
        {
            return profile;
        }

        if (path.StartsWith("~/", StringComparison.Ordinal) || path.StartsWith("~\\", StringComparison.Ordinal))
        {
            return Path.Combine(profile, path[2..].Replace('/', Path.DirectorySeparatorChar));
        }

        if (path == "/")
        {
            return Path.GetPathRoot(Environment.CurrentDirectory) ?? @"C:\";
        }

        if (path.StartsWith('/'))
        {
            return Path.Combine(
                Path.GetPathRoot(Environment.CurrentDirectory) ?? @"C:\",
                path[1..].Replace('/', Path.DirectorySeparatorChar));
        }

        return path;
    }

    private static string DisplayPath(string path)
    {
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.Equals(path, profile, StringComparison.OrdinalIgnoreCase))
        {
            return "~";
        }

        if (path.StartsWith(profile + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
        {
            return "~" + path[profile.Length..];
        }

        return path;
    }
}
