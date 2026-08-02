using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using YTools.Core;
using YTools.ModuleKit;

namespace YTools.Services;

/// <summary>
/// Builds an index from launchable Start Menu entries, App Execution Aliases
/// and the AppsFolder shell namespace. Start Menu shortcuts are launched as
/// shortcuts rather than being reduced to their target executable: that keeps
/// packaged apps, shortcuts with arguments and multiple apps sharing one host.
/// </summary>
public sealed class ApplicationIndexService
{
    private readonly object _lock = new();
    private readonly SearchTextNormalizer _normalizer = new();
    private readonly ApplicationAliasMatcher _aliasMatcher = new();
    private readonly List<FileSystemWatcher> _watchers = [];
    private readonly IReadOnlyList<string> _startMenuRoots;
    private readonly string _windowsAppsRoot;
    private readonly bool _includesRegisteredApplications;
    private List<ApplicationEntry> _applications = [];
    private List<ApplicationEntry> _customApplications = [];
    private IReadOnlyList<string> _customApplicationPaths = [];
    private DateTimeOffset _lastScanAt = DateTimeOffset.MinValue;
    private bool _indexIsDirty = true;
    private Task? _refreshTask;
    private long _indexGeneration;

    public ApplicationIndexService()
        : this(DefaultStartMenuRoots(), DefaultWindowsAppsRoot(), includesRegisteredApplications: true)
    {
    }

    internal ApplicationIndexService(
        IReadOnlyList<string> startMenuRoots,
        string windowsAppsRoot,
        bool includesRegisteredApplications)
    {
        _startMenuRoots = startMenuRoots;
        _windowsAppsRoot = windowsAppsRoot;
        _includesRegisteredApplications = includesRegisteredApplications;
    }

    public void Prepare()
    {
        lock (_lock)
        {
            StartWatchingIfNeeded();
        }

        // Startup preparation already runs on the coordinator's worker. Keep this
        // synchronous for callers that explicitly await readiness, while searches
        // themselves never wait for a scan.
        if (NeedsRefresh())
        {
            RefreshApplications(CurrentGeneration());
        }
    }

    public IReadOnlyList<LauncherResult> Search(
        string query,
        IReadOnlyDictionary<string, string> aliases)
    {
        return Search(query, aliases, []);
    }

    public IReadOnlyList<LauncherResult> Search(
        string query,
        IReadOnlyDictionary<string, string> aliases,
        IReadOnlyList<string> customApplicationPaths)
    {
        lock (_lock)
        {
            StartWatchingIfNeeded();
            UpdateCustomApplicationsLocked(customApplicationPaths);
            if (NeedsRefreshLocked())
            {
                QueueRefreshLocked();
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
            snapshot = _applications
                .Concat(_customApplications)
                .DistinctBy(application => application.Id, StringComparer.OrdinalIgnoreCase)
                .ToList();
        }

        var results = new List<LauncherResult>();
        foreach (var application in snapshot)
        {
            var nameScore = application.SearchCandidates
                .Select(candidate => MatchScore(candidate.Forms, termForms, candidate.AllowsFuzzy))
                .Where(score => score is not null)
                .DefaultIfEmpty(null)
                .Max();
            var aliasScore = application.AliasKeys
                .Where(aliases.ContainsKey)
                .Select(key => _aliasMatcher.Score(term, _aliasMatcher.Aliases(aliases[key])))
                .Where(score => score is not null)
                .DefaultIfEmpty(null)
                .Max();
            var score = new[] { nameScore, aliasScore }
                .Where(value => value is not null)
                .DefaultIfEmpty(null)
                .Max();
            if (score is null)
            {
                continue;
            }

            results.Add(new LauncherResult(
                application.Id,
                "applications",
                application.Name,
                application.Subtitle,
                application.Icon,
                score.Value,
                application.Action));
        }

        return results
            .OrderByDescending(result => result.Score)
            .ThenBy(result => result.Title, StringComparer.OrdinalIgnoreCase)
            .DistinctBy(result => result.Title, StringComparer.OrdinalIgnoreCase)
            .Take(12)
            .ToList();
    }

    private void UpdateCustomApplicationsLocked(IReadOnlyList<string> customApplicationPaths)
    {
        var normalizedPaths = customApplicationPaths
            .Select(NormalizeCustomApplicationPath)
            .Where(path => path is not null)
            .Cast<string>()
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (_customApplicationPaths.SequenceEqual(normalizedPaths, StringComparer.OrdinalIgnoreCase))
        {
            return;
        }

        _customApplicationPaths = normalizedPaths;
        _customApplications = normalizedPaths
            .Select(CreateCustomApplicationEntry)
            .ToList();
    }

    private static string? NormalizeCustomApplicationPath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
        }

        try
        {
            var expandedPath = Environment.ExpandEnvironmentVariables(path.Trim());
            if (!Path.IsPathFullyQualified(expandedPath)
                || expandedPath.StartsWith("\\\\", StringComparison.Ordinal))
            {
                return null;
            }

            var fullPath = Path.GetFullPath(expandedPath);
            var extension = Path.GetExtension(fullPath);
            return File.Exists(fullPath)
                && (extension.Equals(".exe", StringComparison.OrdinalIgnoreCase)
                    || extension.Equals(".lnk", StringComparison.OrdinalIgnoreCase)
                    || extension.Equals(".appref-ms", StringComparison.OrdinalIgnoreCase))
                ? fullPath
                : null;
        }
        catch
        {
            return null;
        }
    }

    private ApplicationEntry CreateCustomApplicationEntry(string launchPath)
    {
        var shortcut = Path.GetExtension(launchPath).Equals(".lnk", StringComparison.OrdinalIgnoreCase)
            ? LnkResolver.Resolve(launchPath)
            : new ShortcutMetadata("", "");
        var target = Environment.ExpandEnvironmentVariables(shortcut.TargetPath.Trim());
        var name = Path.GetFileNameWithoutExtension(launchPath).Trim();
        var searchNames = new List<string> { name };
        AddSearchName(searchNames, Path.GetFileNameWithoutExtension(target));
        AddSearchNames(searchNames, PathTokens(launchPath));
        AddSearchNames(searchNames, PathTokens(target));
        var aliasKeys = new List<string> { launchPath };
        if (!string.IsNullOrWhiteSpace(target))
        {
            aliasKeys.Add(target);
        }

        var iconPath = !string.IsNullOrWhiteSpace(target) && File.Exists(target)
            ? target
            : launchPath;
        return new ApplicationEntry(
            $"application:file:{launchPath}",
            name,
            "自定义应用",
            new ResultIcon.Application(iconPath),
            new ResultAction.Open(launchPath),
            aliasKeys,
            SearchCandidates(name, searchNames.Skip(1)));
    }

    private void RefreshApplications(long generation)
    {
        var entriesById = new Dictionary<string, ApplicationEntry>(StringComparer.OrdinalIgnoreCase);
        foreach (var root in _startMenuRoots)
        {
            ScanStartMenu(root, entriesById);
        }

        ScanExecutionAliases(_windowsAppsRoot, entriesById);
        if (_includesRegisteredApplications)
        {
            AppsFolderEnumerator.AddRegisteredApplications(entriesById, CreateRegisteredEntry);
        }

        var applications = entriesById.Values
            .OrderBy(entry => entry.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
        lock (_lock)
        {
            _applications = applications;
            _lastScanAt = DateTimeOffset.UtcNow;
            _indexIsDirty = _indexGeneration != generation;
        }
    }

    private void ScanStartMenu(string root, IDictionary<string, ApplicationEntry> entriesById)
    {
        if (!Directory.Exists(root))
        {
            return;
        }

        try
        {
            foreach (var path in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
            {
                var extension = Path.GetExtension(path);
                if (!extension.Equals(".lnk", StringComparison.OrdinalIgnoreCase)
                    && !extension.Equals(".appref-ms", StringComparison.OrdinalIgnoreCase)
                    && !extension.Equals(".exe", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var shortcut = extension.Equals(".lnk", StringComparison.OrdinalIgnoreCase)
                    ? LnkResolver.Resolve(path)
                    : new ShortcutMetadata("", "");
                var entry = CreateFileEntry(root, path, shortcut);
                entriesById.TryAdd(entry.Id, entry);
            }
        }
        catch
        {
            // A locked Start Menu folder must never break the launcher.
        }
    }

    private void ScanExecutionAliases(string root, IDictionary<string, ApplicationEntry> entriesById)
    {
        if (!Directory.Exists(root))
        {
            return;
        }

        try
        {
            foreach (var alias in Directory.EnumerateFiles(root, "*.exe"))
            {
                var name = Path.GetFileNameWithoutExtension(alias);
                if (string.IsNullOrWhiteSpace(name))
                {
                    continue;
                }

                var id = $"application:file:{alias}";
                entriesById.TryAdd(id, new ApplicationEntry(
                    id,
                    name,
                    "应用执行别名",
                    new ResultIcon.Application(alias),
                    new ResultAction.Open(alias),
                    [alias],
                    SearchCandidates(name, PathTokens(alias))));
            }
        }
        catch
        {
            // WindowsApps may be unavailable under a restricted user token.
        }
    }

    private ApplicationEntry CreateFileEntry(string root, string launchPath, ShortcutMetadata shortcut)
    {
        var name = Path.GetFileNameWithoutExtension(launchPath).Trim();
        var target = Environment.ExpandEnvironmentVariables(shortcut.TargetPath.Trim());
        var folder = Path.GetDirectoryName(Path.GetRelativePath(root, launchPath)) ?? "";
        var searchNames = new List<string> { name };
        AddSearchName(searchNames, shortcut.Description);
        AddSearchName(searchNames, Path.GetFileNameWithoutExtension(target));
        AddSearchNames(searchNames, PathTokens(launchPath));
        AddSearchNames(searchNames, PathTokens(target));
        if (!folder.Equals(".", StringComparison.Ordinal))
        {
            foreach (var segment in folder.Split(Path.DirectorySeparatorChar, StringSplitOptions.RemoveEmptyEntries))
            {
                AddSearchName(searchNames, segment);
            }
        }

        var aliasKeys = new List<string> { launchPath };
        if (!string.IsNullOrWhiteSpace(target))
        {
            aliasKeys.Add(target);
        }

        var subtitle = !string.IsNullOrWhiteSpace(shortcut.Description)
            && !shortcut.Description.Equals(name, StringComparison.OrdinalIgnoreCase)
                ? shortcut.Description.Trim()
                : folder.Equals(".", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(folder)
                    ? "开始菜单应用"
                    : $"开始菜单 · {folder}";
        var iconPath = !string.IsNullOrWhiteSpace(target)
            && (File.Exists(target) || Directory.Exists(target))
            ? target
            : launchPath;
        return new ApplicationEntry(
            $"application:file:{launchPath}",
            name,
            subtitle,
            new ResultIcon.Application(iconPath),
            new ResultAction.Open(launchPath),
            aliasKeys,
            SearchCandidates(name, searchNames.Skip(1)));
    }

    private ApplicationEntry CreateRegisteredEntry(string name, string appUserModelId)
    {
        return new ApplicationEntry(
            $"application:registered:{appUserModelId}",
            name,
            appUserModelId.Contains('!') ? "Microsoft Store 应用" : "Windows 已注册应用",
            new ResultIcon.RegisteredApplication(appUserModelId),
            new ResultAction.ActivateApplication(appUserModelId),
            [appUserModelId],
            SearchCandidates(name, IdentifierTokens(appUserModelId)));
    }

    private IReadOnlyList<SearchCandidate> SearchCandidates(
        string primaryName,
        IEnumerable<string> additionalNames)
    {
        var values = new List<SearchCandidate>();
        if (!string.IsNullOrWhiteSpace(primaryName))
        {
            values.Add(new SearchCandidate(_normalizer.Forms(primaryName), AllowsFuzzy: true));
        }

        values.AddRange(additionalNames
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Select(value => new SearchCandidate(_normalizer.Forms(value), AllowsFuzzy: false)));
        return values;
    }

    private static void AddSearchName(ICollection<string> values, string value)
    {
        var trimmed = value.Trim();
        if (!string.IsNullOrEmpty(trimmed)
            && !values.Contains(trimmed, StringComparer.OrdinalIgnoreCase))
        {
            values.Add(trimmed);
        }
    }

    private static void AddSearchNames(ICollection<string> values, IEnumerable<string> names)
    {
        foreach (var name in names)
        {
            AddSearchName(values, name);
        }
    }

    private static IEnumerable<string> PathTokens(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return [];
        }

        var fileName = Path.GetFileNameWithoutExtension(path);
        var folder = Path.GetDirectoryName(path) ?? "";
        return IdentifierTokens($"{fileName} {folder}");
    }

    private static IEnumerable<string> IdentifierTokens(string value)
    {
        return value.Split(
                ['\\', '/', '!', '_', '-', '.'],
                StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(token => token.Length >= 2)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(16);
    }

    private int? MatchScore(SearchTextForms candidate, SearchTextForms term, bool allowsFuzzy)
    {
        if (candidate.Normalized == term.Normalized)
        {
            return 900;
        }

        if (candidate.Normalized.StartsWith(term.Normalized, StringComparison.Ordinal))
        {
            return 760;
        }

        if (candidate.Normalized.Contains(term.Normalized, StringComparison.Ordinal))
        {
            return 560;
        }

        if (candidate.Abbreviation.StartsWith(term.Normalized, StringComparison.Ordinal))
        {
            return 500;
        }

        if (candidate.Transliteration == term.Normalized)
        {
            return 740;
        }

        if (candidate.Transliteration.StartsWith(term.Normalized, StringComparison.Ordinal))
        {
            return 700;
        }

        if (candidate.Transliteration.Contains(term.Normalized, StringComparison.Ordinal))
        {
            return 520;
        }

        if (candidate.TransliterationInitials.StartsWith(term.Normalized, StringComparison.Ordinal))
        {
            return 620;
        }

        if (allowsFuzzy && term.Normalized.Length >= 2)
        {
            if (_normalizer.FuzzyScore(term.Normalized, candidate.Normalized) is { } fuzzy)
            {
                return 390 + fuzzy;
            }

            if (_normalizer.FuzzyScore(term.Normalized, candidate.Transliteration) is { } transliteratedFuzzy)
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

        foreach (var root in _startMenuRoots.Append(_windowsAppsRoot))
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
            _indexGeneration += 1;
        }
    }

    private bool NeedsRefresh()
    {
        lock (_lock)
        {
            return NeedsRefreshLocked();
        }
    }

    private long CurrentGeneration()
    {
        lock (_lock)
        {
            return _indexGeneration;
        }
    }

    private bool NeedsRefreshLocked()
    {
        return _indexIsDirty || DateTimeOffset.UtcNow - _lastScanAt > TimeSpan.FromMinutes(5);
    }

    private void QueueRefreshLocked()
    {
        if (_refreshTask is null || _refreshTask.IsCompleted)
        {
            var generation = _indexGeneration;
            _refreshTask = Task.Run(() => RefreshApplications(generation));
        }
    }

    private static IReadOnlyList<string> DefaultStartMenuRoots()
    {
        return
        [
            Environment.GetFolderPath(Environment.SpecialFolder.Programs),
            Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms)
        ];
    }

    private static string DefaultWindowsAppsRoot()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Microsoft",
            "WindowsApps");
    }

    private sealed record ApplicationEntry(
        string Id,
        string Name,
        string Subtitle,
        ResultIcon Icon,
        ResultAction Action,
        IReadOnlyList<string> AliasKeys,
        IReadOnlyList<SearchCandidate> SearchCandidates);

    private sealed record SearchCandidate(SearchTextForms Forms, bool AllowsFuzzy);
}

internal sealed record ShortcutMetadata(string TargetPath, string Description);

/// <summary>Resolves optional .lnk metadata through the fixed shell COM interface.</summary>
internal static class LnkResolver
{
    public static ShortcutMetadata Resolve(string shortcutPath)
    {
        IShellLinkW? shellLink = null;
        IPersistFile? persistFile = null;
        try
        {
            shellLink = (IShellLinkW)new ShellLink();
            persistFile = (IPersistFile)shellLink;
            persistFile.Load(shortcutPath, 0 /* STGM_READ */);
            var target = new StringBuilder(32_768);
            var description = new StringBuilder(1_024);
            shellLink.GetPath(target, target.Capacity, IntPtr.Zero, 0x00000001 /* SLGP_UNCPRIORITY */);
            shellLink.GetDescription(description, description.Capacity);
            return new ShortcutMetadata(target.ToString(), description.ToString().Trim());
        }
        catch
        {
            return new ShortcutMetadata("", "");
        }
        finally
        {
            if (shellLink is not null)
            {
                _ = Marshal.FinalReleaseComObject(shellLink);
            }
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

/// <summary>Reads desktop and packaged applications from the Windows AppsFolder namespace.</summary>
internal static class AppsFolderEnumerator
{
    private static readonly Guid FolderIdAppsFolder = new("1e87508d-89c2-42f0-8a7e-645a0f50ca58");
    private static readonly Guid ShellItemId = new("43826d1e-e718-42ee-bc55-a1e261c37bfe");
    private static readonly Guid EnumItemsHandlerId = new("94f60519-2850-4924-aa5a-d15e84868039");
    private static readonly Guid EnumShellItemsId = new("70629033-e363-4a28-a567-0db78006e6d7");

    public static void AddRegisteredApplications<T>(
        IDictionary<string, T> entriesById,
        Func<string, string, T> createEntry)
    {
        var initialized = CoInitializeEx(IntPtr.Zero, 0) >= 0;
        IShellItem? appsFolder = null;
        IEnumShellItems? items = null;
        try
        {
            var folderId = FolderIdAppsFolder;
            var shellItemId = ShellItemId;
            if (SHGetKnownFolderItem(ref folderId, 0, IntPtr.Zero, ref shellItemId, out appsFolder) < 0)
            {
                return;
            }

            var handlerId = EnumItemsHandlerId;
            var enumId = EnumShellItemsId;
            appsFolder.BindToHandler(IntPtr.Zero, ref handlerId, ref enumId, out var value);
            items = (IEnumShellItems)value;
            while (items.Next(1, out var item, out var fetched) == 0 && fetched == 1)
            {
                try
                {
                    var name = DisplayName(item, ShellDisplayName.NormalDisplay);
                    var appUserModelId = DisplayName(item, ShellDisplayName.ParentRelativeParsing);
                    if (string.IsNullOrWhiteSpace(name)
                        || string.IsNullOrWhiteSpace(appUserModelId))
                    {
                        continue;
                    }

                    entriesById.TryAdd(
                        $"application:registered:{appUserModelId}",
                        createEntry(name.Trim(), appUserModelId.Trim()));
                }
                finally
                {
                    _ = Marshal.FinalReleaseComObject(item);
                }
            }
        }
        catch
        {
            // AppsFolder enumeration is optional on older/restricted systems.
        }
        finally
        {
            if (items is not null)
            {
                _ = Marshal.FinalReleaseComObject(items);
            }

            if (appsFolder is not null)
            {
                _ = Marshal.FinalReleaseComObject(appsFolder);
            }

            if (initialized)
            {
                CoUninitialize();
            }
        }
    }

    private static string DisplayName(IShellItem item, ShellDisplayName displayName)
    {
        item.GetDisplayName(displayName, out var pointer);
        if (pointer == IntPtr.Zero)
        {
            return "";
        }

        try
        {
            return Marshal.PtrToStringUni(pointer) ?? "";
        }
        finally
        {
            Marshal.FreeCoTaskMem(pointer);
        }
    }

    private enum ShellDisplayName : uint
    {
        NormalDisplay = 0,
        ParentRelativeParsing = 0x80018001
    }

    [ComImport]
    [Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem
    {
        void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object ppv);
        void GetParent(out IShellItem ppsi);
        void GetDisplayName(ShellDisplayName sigdnName, out IntPtr ppszName);
        void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
        void Compare(IShellItem psi, uint hint, out int piOrder);
    }

    [ComImport]
    [Guid("70629033-e363-4a28-a567-0db78006e6d7")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IEnumShellItems
    {
        [PreserveSig]
        int Next(uint celt, out IShellItem rgelt, out uint pceltFetched);
        void Skip(uint celt);
        void Reset();
        void Clone(out IEnumShellItems ppenum);
    }

    [DllImport("shell32.dll")]
    private static extern int SHGetKnownFolderItem(
        ref Guid rfid,
        uint flags,
        IntPtr token,
        ref Guid riid,
        out IShellItem item);

    [DllImport("ole32.dll")]
    private static extern int CoInitializeEx(IntPtr reserved, uint coInit);

    [DllImport("ole32.dll")]
    private static extern void CoUninitialize();
}
