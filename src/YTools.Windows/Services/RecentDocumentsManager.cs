using System.IO;
using System.Windows;
using YTools.Infrastructure;
using YTools.Models;
using YTools.ModuleKit;
using YTools.Services.Storage;

namespace YTools.Services;

/// <summary>
/// Keeps a private, encrypted list of files opened through YTools, independent
/// of Windows shared recent items.
/// </summary>
public sealed class RecentDocumentsManager : ObservableObject
{
    private readonly Func<SecureCodableStore> _storeFactory;
    private readonly OrderedBackgroundWriter _writer = new();
    private readonly List<Action<List<RecentDocumentItem>>> _pendingLoadMutations = [];
    private readonly Task _initialization;
    private SecureCodableStore? _store;
    private SecureStoreLoadResult<List<RecentDocumentItem>>? _loadedResult;
    private List<RecentDocumentItem> _items = [];
    private string? _storageError;
    private bool _isLoaded;
    private bool _isSaving;
    private long _revision;
    private long _queuedRevision;
    private Task<bool>? _latestSaveTask;
    private bool _loadedItemsRemoved;
    private const int MaximumItems = 200;

    public RecentDocumentsManager()
        : this(() => new SecureCodableStore("recent-documents"))
    {
    }

    internal RecentDocumentsManager(Func<SecureCodableStore> storeFactory)
    {
        _storeFactory = storeFactory;
        _initialization = _writer.Enqueue(LoadOnWorker);
    }

    private bool LoadOnWorker()
    {
        SecureStoreLoadResult<List<RecentDocumentItem>> result;
        try
        {
            _store = _storeFactory();
            result = _store.Load<List<RecentDocumentItem>>();
            if (result.Kind == SecureStoreLoadResultKind.Loaded)
            {
                var source = result.Value ?? [];
                var filtered = source.Where(item => File.Exists(item.Path)).ToList();
                _loadedItemsRemoved = filtered.Count != source.Count;
                result = SecureStoreLoadResult<List<RecentDocumentItem>>.Loaded(filtered);
            }
        }
        catch (Exception exception)
        {
            result = SecureStoreLoadResult<List<RecentDocumentItem>>.Unavailable(exception.Message);
        }
        _loadedResult = result;
        PostToOwner(() => ApplyLoad(result));
        return true;
    }

    private void ApplyLoad(SecureStoreLoadResult<List<RecentDocumentItem>> result)
    {
        if (_isLoaded) { return; }
        var loaded = result.Kind == SecureStoreLoadResultKind.Loaded
            ? result.Value ?? []
            : [];
        switch (result.Kind)
        {
            case SecureStoreLoadResultKind.Missing:
                StorageError = null;
                break;
            case SecureStoreLoadResultKind.Loaded:
                StorageError = null;
                break;
            default:
                StorageError = result.Message;
                break;
        }

        foreach (var mutation in _pendingLoadMutations) { mutation(loaded); }
        _pendingLoadMutations.Clear();
        _items = loaded;
        _isLoaded = true;
        RaisePropertyChanged(nameof(Items));
        RaisePropertyChanged(nameof(IsLoaded));
        RaisePropertyChanged(nameof(StorageStatus));
        if (_revision > 0 || _loadedItemsRemoved)
        {
            _revision = Math.Max(1, _revision);
            _ = QueueCurrentSnapshot();
        }
    }

    public IReadOnlyList<RecentDocumentItem> Items => _items;

    public string? StorageError
    {
        get => _storageError;
        private set
        {
            if (SetField(ref _storageError, value)) { RaisePropertyChanged(nameof(StorageStatus)); }
        }
    }

    public bool IsLoaded => _isLoaded;

    public bool IsSaving
    {
        get => _isSaving;
        private set
        {
            if (SetField(ref _isSaving, value)) { RaisePropertyChanged(nameof(StorageStatus)); }
        }
    }

    public string StorageStatus => !_isLoaded ? "正在读取加密最近文档…" : IsSaving ? "正在加密保存…" : StorageError ?? "已安全保存";

    public void Record(string path)
    {
        if (!File.Exists(path)
            || path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
            || path.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        ApplyMutation(items =>
        {
            items.RemoveAll(item => item.Path == path);
            items.Insert(0, new RecentDocumentItem(Guid.NewGuid(), path, DateTimeOffset.UtcNow));
            if (items.Count > MaximumItems) { items.RemoveRange(MaximumItems, items.Count - MaximumItems); }
        });
        if (_isLoaded) { _ = QueueCurrentSnapshot(); }
    }

    public void Clear()
    {
        ApplyMutation(items => items.Clear());
        if (_isLoaded) { _ = QueueCurrentSnapshot(); }
    }

    public RecentDocumentsSearchModule SearchModule()
    {
        return new RecentDocumentsSearchModule(_items.ToList());
    }

    public void FlushPendingChanges()
    {
        _initialization.GetAwaiter().GetResult();
        if (!_isLoaded && _loadedResult is { } loaded) { ApplyLoad(loaded); }
        if (_queuedRevision < _revision) { _ = QueueCurrentSnapshot(); }
        _writer.DrainAsync().GetAwaiter().GetResult();
    }

    public async Task FlushPendingChangesAsync()
    {
        await _initialization.ConfigureAwait(false);
        Task<bool>? save = null;
        PostToOwner(() =>
        {
            if (!_isLoaded && _loadedResult is { } loaded) { ApplyLoad(loaded); }
            save = _queuedRevision < _revision ? QueueCurrentSnapshot() : _latestSaveTask;
        }, synchronous: true);
        if (save is not null) { _ = await save.ConfigureAwait(false); }
        await _writer.DrainAsync().ConfigureAwait(false);
    }

    internal Task WaitUntilLoadedAsync() => _initialization;

    private void ApplyMutation(Action<List<RecentDocumentItem>> mutation)
    {
        mutation(_items);
        if (!_isLoaded) { _pendingLoadMutations.Add(mutation); }
        _revision += 1;
        RaisePropertyChanged(nameof(Items));
    }

    private Task<bool> QueueCurrentSnapshot()
    {
        var snapshot = _items.ToList();
        var revision = _revision;
        _queuedRevision = Math.Max(_queuedRevision, revision);
        IsSaving = true;
        var task = _writer.Enqueue(() => _store?.Save(snapshot) == true);
        _latestSaveTask = task;
        _ = task.ContinueWith(completed => PostToOwner(() =>
        {
            if (revision != _revision) { return; }
            IsSaving = false;
            StorageError = completed.IsCompletedSuccessfully && completed.Result
                ? null
                : "无法写入加密最近文档；现有文件未被明文替代。";
            RaisePropertyChanged(nameof(StorageStatus));
        }), TaskScheduler.Default);
        return task;
    }

    private static void PostToOwner(Action action, bool synchronous = false)
    {
        var dispatcher = Application.Current?.Dispatcher;
        if (dispatcher is not null && !dispatcher.CheckAccess())
        {
            if (synchronous) { dispatcher.Invoke(action); }
            else { _ = dispatcher.BeginInvoke(action); }
        }
        else { action(); }
    }
}

public sealed class RecentDocumentsSearchModule : IYToolsModule
{
    private readonly IReadOnlyList<RecentDocumentItem> _items;

    public RecentDocumentsSearchModule(IReadOnlyList<RecentDocumentItem> items)
    {
        _items = items;
    }

    public ModuleDescriptor Descriptor { get; } = new(
        "recent-documents",
        "最近文档",
        new HashSet<ModuleCapability> { ModuleCapability.LocalFileRead });

    public Task<IReadOnlyList<LauncherResult>> SearchAsync(ModuleSearchRequest request)
    {
        var trimmed = request.Query.Trim();
        var prefixes = new[] { "recent", "最近", "最近文档" };
        var prefix = prefixes.FirstOrDefault(candidate =>
            string.Equals(trimmed, candidate, StringComparison.OrdinalIgnoreCase)
            || trimmed.StartsWith(candidate + " ", StringComparison.OrdinalIgnoreCase));
        if (prefix is null)
        {
            return Task.FromResult<IReadOnlyList<LauncherResult>>([]);
        }

        var term = trimmed[prefix.Length..].Trim();
        // Existence is validated when loading, when recording and again at open
        // time — not on every keystroke of the search path.
        var results = _items
            .Select((item, index) => (item, index))
            .Where(pair =>
            {
                var name = Path.GetFileName(pair.item.Path);
                return string.IsNullOrEmpty(term)
                    || name.Contains(term, StringComparison.OrdinalIgnoreCase)
                    || pair.item.Path.Contains(term, StringComparison.OrdinalIgnoreCase);
            })
            .Select(pair =>
            {
                var name = Path.GetFileName(pair.item.Path);
                return new LauncherResult(
                    $"recent:{pair.item.Path}",
                    Descriptor.Id,
                    name,
                    $"最近打开 · {AbbreviatedPath(pair.item.Path)}",
                    new ResultIcon.File(pair.item.Path),
                    1_300 - pair.index,
                    new ResultAction.Open(pair.item.Path));
            }).Cast<LauncherResult>().ToList();

        return Task.FromResult<IReadOnlyList<LauncherResult>>(results);
    }

    private static string AbbreviatedPath(string path)
    {
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (path.StartsWith(profile + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
        {
            return "~" + path[profile.Length..];
        }

        return path;
    }
}
