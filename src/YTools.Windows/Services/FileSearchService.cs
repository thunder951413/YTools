using System.IO;
using YTools.Core;
using YTools.ModuleKit;

namespace YTools.Services;

public enum FileSearchMode
{
    Default,
    Open,
    Reveal,
    Content,
    Tag
}

/// <summary>
/// Local file search. Uses the Everything engine when installed; otherwise a
/// pruned, offline filename scan over the configured scopes. Content and tag
/// searches degrade to filename matching when Everything is unavailable.
/// </summary>
public sealed class FileSearchService : IDisposable
{
    private readonly EverythingClient? _everything;
    private readonly object _indexLock = new();
    private readonly Dictionary<string, FileNameIndex> _indexes = new(StringComparer.OrdinalIgnoreCase);
    private readonly CancellationTokenSource _disposeCancellation = new();
    private readonly Func<IReadOnlyList<string>, CancellationToken, IReadOnlyList<string>>? _fallbackIndexBuilder;

    public event EventHandler? FallbackIndexRefreshed;

    public FileSearchService()
        : this(enableEverything: true)
    {
    }

    internal FileSearchService(
        bool enableEverything,
        Func<IReadOnlyList<string>, CancellationToken, IReadOnlyList<string>>? fallbackIndexBuilder = null)
    {
        _everything = enableEverything ? EverythingClient.TryCreate() : null;
        _fallbackIndexBuilder = fallbackIndexBuilder;
    }

    public bool UsesEverything => _everything?.IsAvailable == true;

    public string BackendDescription
    {
        get
        {
            if (_everything is null)
            {
                return "文件搜索：内置扫描";
            }

            return _everything.AvailabilityStatus switch
            {
                EverythingAvailabilityStatus.Available => "文件搜索：Everything",
                EverythingAvailabilityStatus.IntegrityMismatch => "文件搜索：Everything 权限不匹配",
                EverythingAvailabilityStatus.AccessDenied => "文件搜索：Everything 无法访问",
                EverythingAvailabilityStatus.IpcUnavailable => "文件搜索：Everything IPC 不可用",
                _ => "文件搜索：内置扫描"
            };
        }
    }

    public Task<IReadOnlyList<LauncherResult>> SearchAsync(
        string rawQuery,
        FileSearchMode mode,
        IReadOnlyList<string> scopePaths,
        int maximumResults,
        CancellationToken cancellationToken)
    {
        return Task.Run(
            () => Search(rawQuery, mode, scopePaths, maximumResults, cancellationToken),
            cancellationToken);
    }

    public static bool HasExplicitMode(string rawQuery)
    {
        return ParseQuery(rawQuery).Mode is not null;
    }

    private IReadOnlyList<LauncherResult> Search(
        string rawQuery,
        FileSearchMode mode,
        IReadOnlyList<string> scopePaths,
        int maximumResults,
        CancellationToken cancellationToken)
    {
        var parsed = ParseQuery(rawQuery);
        var effectiveMode = parsed.Mode ?? mode;
        var term = parsed.Term;
        if (string.IsNullOrEmpty(term))
        {
            return [];
        }

        cancellationToken.ThrowIfCancellationRequested();

        var paths = new List<string>();
        var usedEverything = false;
        if (UsesEverything)
        {
            // Embedded quotes would break the Everything query syntax.
            var safeTerm = term.Replace("\"", "");
            var search = effectiveMode switch
            {
                FileSearchMode.Content => $"content:\"{safeTerm}\"",
                FileSearchMode.Tag => $"tag:{safeTerm}",
                _ => term
            };
            if (_everything!.Query(search, Math.Max(30, maximumResults), out var everythingPaths, cancellationToken)
                && _everything.LastError() == 0)
            {
                paths = everythingPaths;
                usedEverything = true;
            }
        }

        if (!usedEverything)
        {
            var roots = EffectiveRoots(scopePaths);
            paths = GetOrStartIndex(roots).Match(term, maximumResults, cancellationToken);
        }

        var explicitMode = effectiveMode != FileSearchMode.Default;
        var output = paths
            .Where(path => File.Exists(path) || Directory.Exists(path))
            .Take(Math.Max(30, maximumResults))
            .Select(path =>
            {
                var name = Path.GetFileName(path);
                var prefixScore = name.StartsWith(term, StringComparison.OrdinalIgnoreCase) ? 80 : 0;
                return new LauncherResult(
                    $"spotlight:{path}",
                    "spotlight",
                    name,
                    DisplayPath(path),
                    new ResultIcon.File(path),
                    (explicitMode ? 680 : 260) + prefixScore,
                    effectiveMode == FileSearchMode.Reveal
                        ? new ResultAction.Reveal(path)
                        : new ResultAction.Open(path));
            })
            .Cast<LauncherResult>()
            .ToList();
        return output;
    }

    private static (FileSearchMode? Mode, string Term) ParseQuery(string rawQuery)
    {
        var normalized = rawQuery;
        if (normalized.StartsWith(' '))
        {
            normalized = normalized.TrimStart();
        }

        var lowered = normalized.ToLowerInvariant();
        (string Prefix, FileSearchMode Mode)[] prefixes =
        {
            ("open ", FileSearchMode.Open),
            ("find ", FileSearchMode.Reveal),
            ("in ", FileSearchMode.Content),
            ("打开 ", FileSearchMode.Open),
            ("查找 ", FileSearchMode.Reveal),
            ("内容 ", FileSearchMode.Content),
            ("tag ", FileSearchMode.Tag),
            ("标签 ", FileSearchMode.Tag)
        };
        foreach (var (prefix, mode) in prefixes)
        {
            if (lowered.StartsWith(prefix, StringComparison.Ordinal))
            {
                return (mode, normalized[prefix.Length..].Trim());
            }
        }

        return (null, normalized.Trim());
    }

    private FileNameIndex GetOrStartIndex(IReadOnlyList<string> roots)
    {
        var key = string.Join("|", roots);
        lock (_indexLock)
        {
            if (!_indexes.TryGetValue(key, out var index))
            {
                index = new FileNameIndex(
                    roots,
                    () => FallbackIndexRefreshed?.Invoke(this, EventArgs.Empty),
                    _fallbackIndexBuilder is null
                        ? null
                        : token => _fallbackIndexBuilder(roots, token));
                _indexes.Add(key, index);
            }

            index.EnsureBuilding(_disposeCancellation.Token);
            return index;
        }
    }

    internal void RefreshFallbackIndexes()
    {
        lock (_indexLock)
        {
            foreach (var index in _indexes.Values)
            {
                index.EnsureBuilding(_disposeCancellation.Token, force: true);
            }
        }
    }

    private static IReadOnlyList<string> EffectiveRoots(IReadOnlyList<string> scopePaths)
    {
        var candidates = scopePaths.Count > 0
            ? scopePaths
            : [Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)];
        return candidates
            .Select(NormalizeLocalDirectory)
            .Where(path => path is not null)
            .Cast<string>()
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static string? NormalizeLocalDirectory(string path)
    {
        if (!LocalPathPolicy.TryNormalize(path, out var fullPath))
        {
            return null;
        }

        try
        {
            return Directory.Exists(fullPath) ? fullPath : null;
        }
        catch
        {
            return null;
        }
    }

    private static bool ShouldSkipDirectory(string name)
    {
        return name is "AppData"
            or "Application Data"
            or "Local Settings"
            or "node_modules"
            or ".git"
            or ".svn"
            or "$RECYCLE.BIN"
            or "System Volume Information"
            or "Windows"
            or "Program Files"
            or "Program Files (x86)"
            or "ProgramData";
    }

    private static string DisplayPath(string path)
    {
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (path.StartsWith(profile + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
        {
            return "~" + path[profile.Length..];
        }

        return path;
    }

    public void Dispose()
    {
        _disposeCancellation.Cancel();
        _disposeCancellation.Dispose();
        _everything?.Dispose();
    }

    /// <summary>Process-local, best-effort filename cache for the non-Everything fallback.</summary>
    private sealed class FileNameIndex
    {
        private readonly object _lock = new();
        private readonly IReadOnlyList<string> _roots;
        private IReadOnlyList<string> _paths = [];
        private Task? _buildTask;
        private DateTimeOffset _lastSuccessfulBuild = DateTimeOffset.MinValue;
        private readonly Action _onRefreshed;
        private readonly Func<CancellationToken, IReadOnlyList<string>>? _builder;

        public FileNameIndex(
            IReadOnlyList<string> roots,
            Action onRefreshed,
            Func<CancellationToken, IReadOnlyList<string>>? builder)
        {
            _roots = roots;
            _onRefreshed = onRefreshed;
            _builder = builder;
        }

        public void EnsureBuilding(CancellationToken cancellationToken, bool force = false)
        {
            lock (_lock)
            {
                // A failed build must be retried on the next query, otherwise
                // the fallback index stays empty for the rest of the session.
                var stale = DateTimeOffset.UtcNow - _lastSuccessfulBuild > TimeSpan.FromMinutes(2);
                if (_buildTask is null
                    || _buildTask.IsFaulted
                    || _buildTask.IsCanceled
                    || (force && _buildTask.IsCompleted)
                    || (stale && _buildTask.IsCompleted))
                {
                    _buildTask = Task.Run(() => Build(cancellationToken), CancellationToken.None);
                }
            }
        }

        public List<string> Match(string term, int limit, CancellationToken cancellationToken)
        {
            if (limit <= 0)
            {
                return [];
            }

            IReadOnlyList<string> snapshot;
            lock (_lock)
            {
                snapshot = _paths;
            }

            var matches = new List<string>();
            foreach (var path in snapshot)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (Path.GetFileName(path).Contains(term, StringComparison.OrdinalIgnoreCase))
                {
                    matches.Add(path);
                    if (matches.Count >= limit)
                    {
                        break;
                    }
                }
            }

            return matches;
        }

        private void Build(CancellationToken cancellationToken)
        {
            IReadOnlyList<string> paths;
            if (_builder is not null)
            {
                paths = _builder(cancellationToken);
            }
            else
            {
                var builtPaths = new List<string>();
                var scanned = 0;
                foreach (var root in _roots)
                {
                    Walk(root, cancellationToken, ref scanned, builtPaths);
                    if (cancellationToken.IsCancellationRequested || scanned > 200_000)
                    {
                        break;
                    }
                }

                paths = builtPaths;
            }

            if (!cancellationToken.IsCancellationRequested)
            {
                lock (_lock)
                {
                    _paths = paths;
                    _lastSuccessfulBuild = DateTimeOffset.UtcNow;
                }

                try
                {
                    _onRefreshed();
                }
                catch
                {
                    // A UI refresh subscriber must not invalidate a completed snapshot.
                }
            }
        }

        private static void Walk(string directory, CancellationToken cancellationToken, ref int scanned, List<string> output)
        {
            if (cancellationToken.IsCancellationRequested || scanned > 200_000)
            {
                return;
            }

            FileSystemInfo[] entries;
            try
            {
                // Materialize inside the try: lazy enumeration can throw from
                // MoveNext after EnumerateFileSystemInfos itself succeeds.
                entries = new DirectoryInfo(directory).GetFileSystemInfos();
            }
            catch
            {
                return;
            }

            foreach (var entry in entries)
            {
                if (cancellationToken.IsCancellationRequested || scanned > 200_000)
                {
                    return;
                }

                scanned += 1;
                if (entry is DirectoryInfo childDirectory)
                {
                    if (ShouldSkipDirectory(childDirectory.Name)
                        || childDirectory.Attributes.HasFlag(FileAttributes.ReparsePoint))
                    {
                        continue;
                    }

                    output.Add(childDirectory.FullName);
                    Walk(childDirectory.FullName, cancellationToken, ref scanned, output);
                }
                else
                {
                    output.Add(entry.FullName);
                }
            }
        }
    }
}
