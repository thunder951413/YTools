using System.IO;
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

    public FileSearchService()
    {
        _everything = EverythingClient.TryCreate();
    }

    public bool UsesEverything => _everything?.IsAvailable == true;

    public string BackendDescription => UsesEverything ? "Everything" : "内置文件名扫描";

    public Task<IReadOnlyList<LauncherResult>> SearchAsync(
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
            return Task.FromResult<IReadOnlyList<LauncherResult>>([]);
        }

        var paths = new List<string>();
        var usedEverything = false;
        if (UsesEverything)
        {
            var search = effectiveMode switch
            {
                FileSearchMode.Content => $"content:\"{term}\"",
                FileSearchMode.Tag => $"tag:{term}",
                _ => term
            };
            if (_everything!.Query(search, Math.Max(30, maximumResults), out var everythingPaths)
                && _everything.LastError() == 0)
            {
                paths = everythingPaths;
                usedEverything = true;
            }
        }

        if (!usedEverything)
        {
            var roots = scopePaths.Count > 0
                ? scopePaths.ToList()
                : new List<string>
                {
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
                };
            var scanned = 0;
            foreach (var root in roots)
            {
                if (!Directory.Exists(root))
                {
                    continue;
                }

                Walk(root, term, maximumResults, cancellationToken, ref scanned, paths);
                if (paths.Count >= maximumResults || cancellationToken.IsCancellationRequested)
                {
                    break;
                }
            }
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
        return Task.FromResult<IReadOnlyList<LauncherResult>>(output);
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

    private static void Walk(
        string directory,
        string term,
        int limit,
        CancellationToken cancellationToken,
        ref int scanned,
        List<string> output)
    {
        if (cancellationToken.IsCancellationRequested || output.Count >= limit || scanned > 200_000)
        {
            return;
        }

        IEnumerable<FileSystemInfo> entries;
        try
        {
            entries = new DirectoryInfo(directory).EnumerateFileSystemInfos();
        }
        catch
        {
            return;
        }

        foreach (var entry in entries)
        {
            if (cancellationToken.IsCancellationRequested || output.Count >= limit || scanned > 200_000)
            {
                return;
            }

            scanned += 1;
            if (entry is DirectoryInfo childDirectory)
            {
                if (ShouldSkipDirectory(childDirectory.Name))
                {
                    continue;
                }

                if (childDirectory.Name.Contains(term, StringComparison.OrdinalIgnoreCase))
                {
                    output.Add(childDirectory.FullName);
                }

                Walk(childDirectory.FullName, term, limit, cancellationToken, ref scanned, output);
            }
            else if (entry.Name.Contains(term, StringComparison.OrdinalIgnoreCase))
            {
                output.Add(entry.FullName);
            }
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
        _everything?.Dispose();
    }
}
