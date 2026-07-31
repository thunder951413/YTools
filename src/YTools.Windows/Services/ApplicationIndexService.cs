using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using YTools.Core;
using YTools.ModuleKit;

namespace YTools.Services;

/// <summary>
/// Windows equivalent of the macOS application scanner: Start Menu shortcuts
/// and App Execution Aliases in WindowsApps. Shortcut targets are resolved
/// through the shell's IShellLink interface with fixed, non-shell invocation.
/// </summary>
public sealed class ApplicationIndexService
{
    private readonly object _lock = new();
    private readonly SearchTextNormalizer _normalizer = new();
    private readonly ApplicationAliasMatcher _aliasMatcher = new();
    private readonly List<FileSystemWatcher> _watchers = [];
    private List<ApplicationEntry> _applications = [];
    private DateTimeOffset _lastScanAt = DateTimeOffset.MinValue;
    private bool _indexIsDirty = true;

    public void Prepare()
    {
        StartWatchingIfNeeded();
        if (_indexIsDirty)
        {
            RefreshApplications();
        }
    }

    public IReadOnlyList<LauncherResult> Search(
        string query,
        IReadOnlyDictionary<string, string> aliases)
    {
        lock (_lock)
        {
            StartWatchingIfNeeded();
            if (_indexIsDirty || DateTimeOffset.UtcNow - _lastScanAt > TimeSpan.FromMinutes(5))
            {
                RefreshApplications();
            }
        }

        var term = query.Trim();
        if (string.IsNullOrEmpty(term))
        {
            return [];
        }

        var termForms = _normalizer.Forms(term);
        List<ApplicationEntry> snapshot;
        lock (_lock)
        {
            snapshot = _applications;
        }

        var results = new List<LauncherResult>();
        foreach (var application in snapshot)
        {
            var nameScore = MatchScore(application, term, termForms);
            var aliasScore = aliases.TryGetValue(application.TargetPath, out var rawAliases)
                ? _aliasMatcher.Score(term, _aliasMatcher.Aliases(rawAliases))
                : null;
            var score = new[] { nameScore, aliasScore }.Where(value => value is not null).Max();
            if (score is null)
            {
                continue;
            }

            results.Add(new LauncherResult(
                $"application:{application.TargetPath}",
                "applications",
                application.Name,
                application.TargetPath,
                new ResultIcon.Application(application.TargetPath),
                score.Value,
                new ResultAction.Open(application.TargetPath)));
        }

        return results
            .OrderByDescending(result => result.Score)
            .ThenBy(result => result.Title, StringComparer.OrdinalIgnoreCase)
            .Take(12)
            .ToList();
    }

    private void RefreshApplications()
    {
        var roots = new List<string>
        {
            Environment.GetFolderPath(Environment.SpecialFolder.Programs),
            Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms),
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Microsoft",
                "WindowsApps")
        };

        var entriesByPath = new Dictionary<string, ApplicationEntry>(StringComparer.OrdinalIgnoreCase);
        foreach (var root in roots.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (!Directory.Exists(root))
            {
                continue;
            }

            try
            {
                if (root.EndsWith("WindowsApps", StringComparison.OrdinalIgnoreCase))
                {
                    foreach (var alias in Directory.EnumerateFiles(root, "*.exe"))
                    {
                        var name = Path.GetFileNameWithoutExtension(alias);
                        if (!string.IsNullOrEmpty(name) && !entriesByPath.ContainsKey(alias))
                        {
                            entriesByPath[alias] = new ApplicationEntry(name, alias, _normalizer.Forms(name));
                        }
                    }
                }
                else
                {
                    foreach (var shortcut in Directory.EnumerateFiles(root, "*.lnk", SearchOption.AllDirectories))
                    {
                        var target = LnkResolver.ResolveTarget(shortcut);
                        if (string.IsNullOrEmpty(target)
                            || !File.Exists(target)
                            || !target.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                        {
                            continue;
                        }

                        var description = LnkResolver.ResolveDescription(shortcut);
                        var name = !string.IsNullOrEmpty(description)
                            ? description
                            : Path.GetFileNameWithoutExtension(target);
                        if (string.IsNullOrEmpty(name) || entriesByPath.ContainsKey(target))
                        {
                            continue;
                        }

                        entriesByPath[target] = new ApplicationEntry(name, target, _normalizer.Forms(name));
                    }
                }
            }
            catch
            {
                // A locked directory must never break the launcher.
            }
        }

        _applications = entriesByPath.Values
            .OrderBy(entry => entry.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
        _lastScanAt = DateTimeOffset.UtcNow;
        _indexIsDirty = false;
    }

    private int? MatchScore(ApplicationEntry application, string term, SearchTextForms termForms)
    {
        if (string.Equals(application.Name, term, StringComparison.OrdinalIgnoreCase))
        {
            return 900;
        }

        var candidate = application.Forms;
        if (candidate.Normalized.StartsWith(termForms.Normalized, StringComparison.Ordinal))
        {
            return 760;
        }

        if (candidate.Normalized.Contains(termForms.Normalized, StringComparison.Ordinal))
        {
            return 560;
        }

        if (candidate.Abbreviation.StartsWith(termForms.Normalized, StringComparison.Ordinal))
        {
            return 500;
        }

        if (candidate.Transliteration == termForms.Normalized)
        {
            return 740;
        }

        if (candidate.Transliteration.StartsWith(termForms.Normalized, StringComparison.Ordinal))
        {
            return 700;
        }

        if (candidate.Transliteration.Contains(termForms.Normalized, StringComparison.Ordinal))
        {
            return 520;
        }

        if (candidate.TransliterationInitials.StartsWith(termForms.Normalized, StringComparison.Ordinal))
        {
            return 620;
        }

        if (termForms.Normalized.Length >= 2)
        {
            if (_normalizer.FuzzyScore(termForms.Normalized, candidate.Normalized) is { } fuzzy)
            {
                return 390 + fuzzy;
            }

            if (_normalizer.FuzzyScore(termForms.Normalized, candidate.Transliteration) is { } transliteratedFuzzy)
            {
                return 380 + transliteratedFuzzy;
            }
        }

        return null;
    }

    private void StartWatchingIfNeeded()
    {
        if (_watchers.Count > 0)
        {
            return;
        }

        var roots = new List<string>
        {
            Environment.GetFolderPath(Environment.SpecialFolder.Programs),
            Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms),
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Microsoft",
                "WindowsApps")
        };
        foreach (var root in roots.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (!Directory.Exists(root))
            {
                continue;
            }

            try
            {
                var watcher = new FileSystemWatcher(root)
                {
                    IncludeSubdirectories = true,
                    NotifyFilter = NotifyFilters.FileName
                        | NotifyFilters.DirectoryName
                        | NotifyFilters.LastWrite
                };
                watcher.Changed += (_, _) => MarkDirty();
                watcher.Created += (_, _) => MarkDirty();
                watcher.Deleted += (_, _) => MarkDirty();
                watcher.Renamed += (_, _) => MarkDirty();
                watcher.EnableRaisingEvents = true;
                _watchers.Add(watcher);
            }
            catch
            {
                // Watching is best-effort; periodic rescans still refresh the index.
            }
        }
    }

    private void MarkDirty()
    {
        lock (_lock)
        {
            _indexIsDirty = true;
        }
    }

    private sealed record ApplicationEntry(string Name, string TargetPath, SearchTextForms Forms);
}

/// <summary>Resolves .lnk targets through the fixed shell COM interface.</summary>
internal static class LnkResolver
{
    public static string ResolveTarget(string shortcutPath)
    {
        try
        {
            var shellLink = (IShellLinkW)new ShellLink();
            var persistFile = (IPersistFile)shellLink;
            persistFile.Load(shortcutPath, 0 /* STGM_READ */);
            var buffer = new StringBuilder(1024);
            shellLink.GetPath(buffer, buffer.Capacity, IntPtr.Zero, 0x00000001 /* SLGP_UNCPRIORITY */);
            Marshal.FinalReleaseComObject(persistFile);
            Marshal.FinalReleaseComObject(shellLink);
            return buffer.Length == 0 ? "" : buffer.ToString();
        }
        catch
        {
            return "";
        }
    }

    public static string ResolveDescription(string shortcutPath)
    {
        try
        {
            var shellLink = (IShellLinkW)new ShellLink();
            var persistFile = (IPersistFile)shellLink;
            persistFile.Load(shortcutPath, 0);
            var buffer = new StringBuilder(512);
            shellLink.GetDescription(buffer, buffer.Capacity);
            Marshal.FinalReleaseComObject(persistFile);
            Marshal.FinalReleaseComObject(shellLink);
            return buffer.ToString().Trim();
        }
        catch
        {
            return "";
        }
    }

    [ComImport]
    [Guid("00021401-0000-0000-C000-000000000046")]
    private class ShellLink
    {
    }

    [ComImport]
    [Guid("000214F9-0000-0000-C000-000000000046")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cch, IntPtr pfd, uint fFlags);

        void GetIDList(out IntPtr ppidl);

        void SetIDList(IntPtr pidl);

        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cch);

        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);

        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cch);

        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);

        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cch);

        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);

        void GetHotkey(out short pwHotkey);

        void SetHotkey(short wHotkey);

        void GetShowCmd(out int piShowCmd);

        void SetShowCmd(int iShowCmd);

        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cch, out int piIcon);

        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);

        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);

        void Resolve(IntPtr hwnd, uint fFlags);

        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    [ComImport]
    [Guid("0000010B-0000-0000-C000-000000000046")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPersistFile
    {
        void GetClassID(out Guid pClassID);

        void IsDirty();

        void Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);

        void Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, bool fRemember);

        void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);

        void GetCurFile([Out, MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
    }
}
