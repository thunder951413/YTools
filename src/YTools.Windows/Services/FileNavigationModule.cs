using System.IO;
using System.Text.RegularExpressions;
using YTools.Models;
using YTools.ModuleKit;

namespace YTools.Services;

/// <summary>
/// `/`, `~` and rooted-path directory navigation. Windows paths are handled
/// natively; `/` maps to the current drive root for parity with the macOS UI.
/// </summary>
public sealed class FileNavigationModule
{
    public IReadOnlyList<LauncherResult> Results(
        string query,
        bool showsHiddenFiles,
        FileNavigationSort sort,
        bool ascending,
        bool foldersFirst)
    {
        var input = query.Trim();
        var expanded = ExpandTilde(input);
        if (!input.StartsWith('/') && !input.StartsWith('~') && !Path.IsPathRooted(expanded))
        {
            return [];
        }

        var isDirectory = Directory.Exists(expanded);
        string directoryPath;
        string filter;
        if (input.EndsWith('/') || input.EndsWith('\\') || isDirectory)
        {
            directoryPath = expanded;
            filter = "";
        }
        else
        {
            var candidate = expanded;
            directoryPath = Path.GetDirectoryName(candidate) ?? candidate;
            filter = Path.GetFileName(candidate);
        }

        if (!Directory.Exists(directoryPath))
        {
            return [];
        }

        DirectoryInfo directoryInfo;
        try
        {
            directoryInfo = new DirectoryInfo(directoryPath);
        }
        catch
        {
            return [];
        }

        IEnumerable<FileSystemInfo> entries;
        try
        {
            entries = showsHiddenFiles
                ? directoryInfo.EnumerateFileSystemInfos()
                : directoryInfo.EnumerateFileSystemInfos().Where(info => (info.Attributes & FileAttributes.Hidden) == 0);
        }
        catch
        {
            return [];
        }

        var matched = new List<(FileSystemInfo Info, bool IsDirectory, DateTime Created, DateTime Modified)>();
        foreach (var info in entries)
        {
            if (!Matches(info.Name, filter))
            {
                continue;
            }

            var isDir = info is DirectoryInfo;
            matched.Add((
                info,
                isDir,
                info.CreationTime,
                info.LastWriteTime));
        }

        matched.Sort((left, right) =>
        {
            if (foldersFirst && left.IsDirectory != right.IsDirectory)
            {
                return left.IsDirectory ? -1 : 1;
            }

            var comparison = sort switch
            {
                FileNavigationSort.Name => string.Compare(
                    left.Info.Name,
                    right.Info.Name,
                    StringComparison.OrdinalIgnoreCase),
                FileNavigationSort.Created => left.Created.CompareTo(right.Created),
                FileNavigationSort.Modified => left.Modified.CompareTo(right.Modified),
                _ => 0
            };
            return ascending ? comparison : -comparison;
        });

        return matched.Take(40).Select(item =>
        {
            var path = item.Info.FullName;
            return new LauncherResult(
                $"file-navigation:{path}",
                "file-navigation",
                item.Info.Name,
                DisplayPath(path),
                new ResultIcon.File(path),
                item.IsDirectory ? 920 : 900,
                item.IsDirectory
                    ? new ResultAction.Navigate(NavigationQuery(path))
                    : new ResultAction.Open(path));
        }).Cast<LauncherResult>().ToList();
    }

    private static bool Matches(string name, string filter)
    {
        if (string.IsNullOrEmpty(filter))
        {
            return true;
        }

        if (!filter.Contains('*'))
        {
            return name.Contains(filter, StringComparison.OrdinalIgnoreCase);
        }

        var pattern = "^" + string.Join(
            ".*",
            filter.Split('*').Select(Regex.Escape)) + "$";
        return Regex.IsMatch(name, pattern, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    }

    private static string ExpandTilde(string path)
    {
        if (path == "~")
        {
            return Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        }

        if (path.StartsWith("~/", StringComparison.Ordinal) || path.StartsWith("~\\", StringComparison.Ordinal))
        {
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                path[2..].Replace('/', Path.DirectorySeparatorChar));
        }

        if (path == "/" || path.StartsWith('/'))
        {
            var root = Path.GetPathRoot(Environment.CurrentDirectory) ?? @"C:\";
            return path == "/" ? root : Path.Combine(root, path[1..].Replace('/', Path.DirectorySeparatorChar));
        }

        return path;
    }

    private static string NavigationQuery(string path)
    {
        var display = DisplayPath(path);
        return display.EndsWith('\\') || display.EndsWith('/') ? display : display + "\\";
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
