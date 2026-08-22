using System.IO;
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
    private readonly SecureCodableStore _store = new("recent-documents");
    private List<RecentDocumentItem> _items;
    private string? _storageError;
    private const int MaximumItems = 200;

    public RecentDocumentsManager()
    {
        var result = _store.Load<List<RecentDocumentItem>>();
        switch (result.Kind)
        {
            case SecureStoreLoadResultKind.Missing:
                _items = [];
                _storageError = null;
                break;
            case SecureStoreLoadResultKind.Loaded:
                _items = (result.Value ?? []).Where(item => File.Exists(item.Path)).ToList();
                _storageError = null;
                if (_items.Count != (result.Value ?? []).Count)
                {
                    Persist();
                }

                break;
            default:
                _items = [];
                _storageError = result.Message;
                break;
        }
    }

    public IReadOnlyList<RecentDocumentItem> Items => _items;

    public string? StorageError
    {
        get => _storageError;
        private set => SetField(ref _storageError, value);
    }

    public void Record(string path)
    {
        if (!File.Exists(path)
            || path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
            || path.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        _items.RemoveAll(item => item.Path == path);
        _items.Insert(0, new RecentDocumentItem(Guid.NewGuid(), path, DateTimeOffset.UtcNow));
        _items = _items.Take(MaximumItems).ToList();
        Persist();
    }

    public void Clear()
    {
        _items = [];
        Persist();
    }

    public RecentDocumentsSearchModule SearchModule()
    {
        return new RecentDocumentsSearchModule(_items);
    }

    private void Persist()
    {
        if (_store.Save(_items))
        {
            StorageError = null;
        }
        else
        {
            StorageError = "无法写入加密最近文档；现有文件未被明文替代。";
        }
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
