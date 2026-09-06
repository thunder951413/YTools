using System.Globalization;
using System.Windows;
using YTools.Core;
using YTools.Infrastructure;
using YTools.Models;
using YTools.ModuleKit;
using YTools.Services.Storage;

namespace YTools.Services;

public sealed class SnippetManager : ObservableObject
{
    private readonly Func<SecureCodableStore> _storeFactory;
    private readonly OrderedBackgroundWriter _writer = new();
    private readonly DebouncedAction _saveDebouncer = new();
    private readonly List<Action<List<SnippetItem>>> _pendingLoadMutations = [];
    private List<SnippetItem> _items = [];
    private string? _storageError;
    private SecureCodableStore? _store;
    private bool _isLoaded;
    private bool _isSaving;
    private long _revision;
    private long _queuedRevision;
    private readonly Task _initialization;
    private SecureStoreLoadResult<List<SnippetItem>>? _loadedResult;
    private Task<bool>? _latestSaveTask;

    public SnippetManager()
        : this(() => new SecureCodableStore("snippets"))
    {
    }

    internal SnippetManager(Func<SecureCodableStore> storeFactory)
    {
        _storeFactory = storeFactory;
        _initialization = _writer.Enqueue(LoadOnWorker);
    }

    private bool LoadOnWorker()
    {
        SecureStoreLoadResult<List<SnippetItem>> result;
        try
        {
            _store = _storeFactory();
            result = _store.Load<List<SnippetItem>>();
        }
        catch (Exception exception)
        {
            result = SecureStoreLoadResult<List<SnippetItem>>.Unavailable(exception.Message);
        }
        _loadedResult = result;
        PostToOwner(() => ApplyLoad(result));
        return true;
    }

    private void ApplyLoad(SecureStoreLoadResult<List<SnippetItem>> result)
    {
        if (_isLoaded) { return; }
        var loaded = result.Kind == SecureStoreLoadResultKind.Loaded ? result.Value ?? [] : [];
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

        foreach (var mutation in _pendingLoadMutations)
        {
            mutation(loaded);
        }

        _pendingLoadMutations.Clear();
        _items = loaded;
        _isLoaded = true;
        RaisePropertyChanged(nameof(Items));
        RaisePropertyChanged(nameof(IsLoaded));
        RaisePropertyChanged(nameof(StorageStatus));
        if (_revision > 0)
        {
            _ = QueueCurrentSnapshot("无法写入加密文本片段；现有文件未被覆盖。");
        }
    }

    public IReadOnlyList<SnippetItem> Items => _items;

    public string? StorageError
    {
        get => _storageError;
        private set
        {
            if (SetField(ref _storageError, value)) { RaisePropertyChanged(nameof(StorageStatus)); }
        }
    }

    public string? SaveError => StorageError;

    public bool IsLoaded => _isLoaded;

    public bool IsSaving
    {
        get => _isSaving;
        private set
        {
            if (SetField(ref _isSaving, value))
            {
                RaisePropertyChanged(nameof(StorageStatus));
            }
        }
    }

    public string StorageStatus => !_isLoaded ? "正在读取加密片段…" : IsSaving ? "正在加密保存…" : StorageError ?? "已安全保存";

    public SnippetSearchModule SearchModule(string clipboardText, DateTimeOffset now)
    {
        return new SnippetSearchModule(_items.ToList(), clipboardText, now);
    }

    public bool Save(string text, string? title = null, string keyword = "", string collection = "默认")
    {
        return BeginSave(text, title, keyword, collection, out _) is not null;
    }

    public Task<bool> SaveAsync(string text, string? title = null, string keyword = "", string collection = "默认")
    {
        return BeginSave(text, title, keyword, collection, out var revision)
            ?? Task.FromResult(false);
    }

    private Task<bool>? BeginSave(
        string text,
        string? title,
        string keyword,
        string collection,
        out long revision)
    {
        revision = 0;
        var trimmed = text.Trim();
        if (string.IsNullOrEmpty(trimmed))
        {
            return null;
        }

        var finalTitle = string.IsNullOrWhiteSpace(title)
            ? Preview(trimmed)
            : title.Trim();
        var now = DateTimeOffset.UtcNow;
        var newItem = new SnippetItem(
                Guid.NewGuid(),
                finalTitle,
                keyword,
                text,
                collection,
                now,
                now);
        ApplyMutation(items => items.Insert(0, newItem));
        revision = _revision;
        return _isLoaded
            ? QueueCurrentSnapshot("无法写入加密文本片段；现有文件未被覆盖。")
            : WaitForRevisionAsync(revision);
    }

    public void Delete(SnippetItem item)
    {
        ApplyMutation(items => items.RemoveAll(existing => existing.Id == item.Id));
        if (_isLoaded) { _ = QueueCurrentSnapshot("无法保存删除操作。"); }
    }

    public void Update(
        Guid id,
        string? title = null,
        string? keyword = null,
        string? content = null,
        string? collection = null)
    {
        if (_items.All(item => item.Id != id))
        {
            return;
        }

        ApplyMutation(items =>
        {
            var index = items.FindIndex(item => item.Id == id);
            if (index < 0) { return; }
            var item = items[index];
            items[index] = item with
            {
                Title = title ?? item.Title,
                Keyword = keyword ?? item.Keyword,
                Content = content ?? item.Content,
                Collection = collection ?? item.Collection,
                UpdatedAt = DateTimeOffset.UtcNow
            };
        });
        _saveDebouncer.Schedule(TimeSpan.FromMilliseconds(350), () =>
        {
            if (_isLoaded) { _ = QueueCurrentSnapshot("无法保存文本片段修改。"); }
        });
    }

    public void FlushPendingChanges()
    {
        _saveDebouncer.Cancel();
        _initialization.GetAwaiter().GetResult();
        if (!_isLoaded && _loadedResult is { } loaded) { ApplyLoad(loaded); }
        if (_queuedRevision < _revision) { _ = QueueCurrentSnapshot("无法保存文本片段修改。"); }
        _writer.DrainAsync().GetAwaiter().GetResult();
    }

    public async Task FlushPendingChangesAsync()
    {
        _saveDebouncer.Cancel();
        await _initialization.ConfigureAwait(false);
        Task<bool>? save = null;
        PostToOwner(() =>
        {
            if (!_isLoaded && _loadedResult is { } loaded) { ApplyLoad(loaded); }
            save = _queuedRevision < _revision
                ? QueueCurrentSnapshot("无法保存文本片段修改。")
                : _latestSaveTask;
        }, synchronous: true);
        if (save is not null) { _ = await save.ConfigureAwait(false); }
        await _writer.DrainAsync().ConfigureAwait(false);
    }

    internal Task WaitUntilLoadedAsync() => _initialization;

    private void ApplyMutation(Action<List<SnippetItem>> mutation)
    {
        _saveDebouncer.Cancel();
        mutation(_items);
        if (!_isLoaded) { _pendingLoadMutations.Add(mutation); }
        _revision += 1;
        RaisePropertyChanged(nameof(Items));
    }

    private Task<bool> QueueCurrentSnapshot(string failureMessage)
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
            StorageError = completed.IsCompletedSuccessfully && completed.Result ? null : failureMessage;
            RaisePropertyChanged(nameof(StorageStatus));
        }), TaskScheduler.Default);
        return task;
    }

    private async Task<bool> WaitForRevisionAsync(long revision)
    {
        await _initialization.ConfigureAwait(false);
        Task<bool>? save = null;
        PostToOwner(() =>
        {
            if (!_isLoaded && _loadedResult is { } loaded) { ApplyLoad(loaded); }
            save = _queuedRevision >= revision
                ? _latestSaveTask
                : QueueCurrentSnapshot("无法写入加密文本片段；现有文件未被覆盖。");
        }, synchronous: true);
        return save is not null && await save.ConfigureAwait(false);
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

    private static string Preview(string text, int limit = 72)
    {
        var singleLine = text.Replace("\n", " ");
        return singleLine.Length <= limit ? singleLine : singleLine[..limit] + "…";
    }
}

public sealed class SnippetSearchModule : IYToolsModule
{
    private readonly IReadOnlyList<SnippetItem> _items;
    private readonly string _clipboardText;
    private readonly DateTimeOffset _now;

    public SnippetSearchModule(IReadOnlyList<SnippetItem> items, string clipboardText, DateTimeOffset now)
    {
        _items = items;
        _clipboardText = clipboardText;
        _now = now;
    }

    public ModuleDescriptor Descriptor { get; } = new("snippets", "文本片段");

    public static bool Accepts(string query)
    {
        return SearchTerm(query) is not null;
    }

    public Task<IReadOnlyList<LauncherResult>> SearchAsync(ModuleSearchRequest request)
    {
        var term = SearchTerm(request.Query);
        if (term is null)
        {
            return Task.FromResult<IReadOnlyList<LauncherResult>>([]);
        }

        var results = _items
            .Where(item =>
                string.IsNullOrEmpty(term)
                || item.Title.Contains(term, StringComparison.OrdinalIgnoreCase)
                || item.Keyword.Contains(term, StringComparison.OrdinalIgnoreCase)
                || item.Content.Contains(term, StringComparison.OrdinalIgnoreCase)
                || item.Collection.Contains(term, StringComparison.OrdinalIgnoreCase))
            .Take(30)
            .Select(item =>
            {
                var expanded = Expand(item.Content);
                return new LauncherResult(
                    $"snippet:{item.Id:N}",
                    Descriptor.Id,
                    item.Title,
                    string.Join(" · ", new[] { item.Collection, item.Keyword, Preview(expanded) }
                        .Where(part => !string.IsNullOrEmpty(part))),
                    new ResultIcon.System("text.quote"),
                    820,
                    new ResultAction.Copy(expanded));
            }).Cast<LauncherResult>().ToList();

        return Task.FromResult<IReadOnlyList<LauncherResult>>(results);
    }

    private static string? SearchTerm(string query)
    {
        var trimmed = query.Trim();
        foreach (var prefix in new[] { "snip", "snippet", "片段" })
        {
            if (string.Equals(trimmed, prefix, StringComparison.OrdinalIgnoreCase))
            {
                return "";
            }

            if (trimmed.StartsWith(prefix + " ", StringComparison.OrdinalIgnoreCase))
            {
                return trimmed[(prefix.Length + 1)..];
            }
        }

        return null;
    }

    private string Expand(string content)
    {
        var date = _now.ToLocalTime().ToString("yyyy/M/d", CultureInfo.InvariantCulture);
        var time = _now.ToLocalTime().ToString("HH:mm:ss", CultureInfo.InvariantCulture);
        return content
            .Replace("{date}", date)
            .Replace("{time}", time)
            .Replace("{clipboard}", _clipboardText)
            .Replace("{cursor}", "");
    }

    private static string Preview(string text, int limit = 72)
    {
        var singleLine = text.Replace("\n", " ");
        return singleLine.Length <= limit ? singleLine : singleLine[..limit] + "…";
    }
}
