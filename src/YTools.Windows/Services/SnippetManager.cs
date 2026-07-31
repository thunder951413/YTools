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
    private readonly SecureCodableStore _store = new("snippets");
    private readonly DebouncedAction _saveDebouncer = new();
    private List<SnippetItem> _items;
    private List<SnippetItem> _persistedItems;
    private string? _storageError;

    public SnippetManager()
    {
        var result = _store.Load<List<SnippetItem>>();
        switch (result.Kind)
        {
            case SecureStoreLoadResultKind.Missing:
                _items = [];
                _storageError = null;
                break;
            case SecureStoreLoadResultKind.Loaded:
                _items = result.Value ?? [];
                _storageError = null;
                break;
            default:
                _items = [];
                _storageError = result.Message;
                break;
        }

        _persistedItems = _items;
    }

    public IReadOnlyList<SnippetItem> Items => _items;

    public string? StorageError
    {
        get => _storageError;
        private set => SetField(ref _storageError, value);
    }

    public string? SaveError => StorageError;

    public SnippetSearchModule SearchModule(string clipboardText, DateTimeOffset now)
    {
        return new SnippetSearchModule(_items, clipboardText, now);
    }

    public bool Save(string text, string? title = null, string keyword = "", string collection = "默认")
    {
        var trimmed = text.Trim();
        if (string.IsNullOrEmpty(trimmed))
        {
            return false;
        }

        var finalTitle = string.IsNullOrWhiteSpace(title)
            ? Preview(trimmed)
            : title.Trim();
        var now = DateTimeOffset.UtcNow;
        _items.Insert(
            0,
            new SnippetItem(
                Guid.NewGuid(),
                finalTitle,
                keyword,
                text,
                collection,
                now,
                now));
        return PersistCurrent("无法写入加密文本片段；现有文件未被覆盖。");
    }

    public void Delete(SnippetItem item)
    {
        _items.RemoveAll(existing => existing.Id == item.Id);
        _ = PersistCurrent("无法保存删除操作。");
    }

    public void Update(
        Guid id,
        string? title = null,
        string? keyword = null,
        string? content = null,
        string? collection = null)
    {
        var index = _items.FindIndex(item => item.Id == id);
        if (index < 0)
        {
            return;
        }

        var item = _items[index];
        _items[index] = item with
        {
            Title = title ?? item.Title,
            Keyword = keyword ?? item.Keyword,
            Content = content ?? item.Content,
            Collection = collection ?? item.Collection,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        _saveDebouncer.Schedule(TimeSpan.FromMilliseconds(350), () =>
        {
            _ = PersistCurrent("无法保存文本片段修改。");
        });
    }

    public void FlushPendingChanges()
    {
        _saveDebouncer.Cancel();
        if (!_items.SequenceEqual(_persistedItems))
        {
            _ = PersistCurrent("无法保存文本片段修改。");
        }
    }

    private bool PersistCurrent(string failureMessage)
    {
        _saveDebouncer.Cancel();
        if (_store.Save(_items))
        {
            _persistedItems = _items.ToList();
            StorageError = null;
            return true;
        }

        _items = _persistedItems.ToList();
        StorageError = failureMessage;
        return false;
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
