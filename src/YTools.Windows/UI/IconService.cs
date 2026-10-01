using System.Collections.Concurrent;
using System.Drawing;
using System.IO;
using Microsoft.Win32;
using System.Runtime.InteropServices;
using System.Xml.Linq;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using YTools.ModuleKit;
using YTools.Core;

namespace YTools.UI;

/// <summary>
/// Supplies result icons: Segoe glyphs for system icons, shell file icons for
/// files and applications, with a bounded in-memory cache.
/// </summary>
public static class IconService
{
    private static readonly ConcurrentDictionary<string, string> GlyphCache = new();
    private static readonly ConcurrentDictionary<string, ImageSource> IconCache = new();
    private static readonly ConcurrentDictionary<string, byte> PendingIconKeys = new();
    private static readonly ConcurrentDictionary<string, byte> UnavailableIconKeys = new();
    private static readonly string DefaultGlyph = "\uE8A5";

    /// <summary>Raised on the UI dispatcher after a background icon is cached.</summary>
    public static event EventHandler? IconAvailable;

    public static string GlyphFor(string systemIconName)
    {
        return GlyphCache.GetOrAdd(systemIconName, name =>
        {
            return name switch
            {
                "function" => "\uE8EF",
                "ruler" => "\uE8A1",
                "gearshape" or "gearshape.fill" => "\uE713",
                "character.book.closed" => "\uE8D6",
                "checkmark.seal" => "\uE73E",
                "textformat.abc.dottedunderline" => "\uE8D4",
                "textformat.123" => "\uE8F2",
                "text.quote" or "text.badge.plus" => "\uE8FD",
                "trash" or "trash.slash" => "\uE74D",
                "sparkles.rectangle.stack" => "\uE7B8",
                "display.trianglebadge.exclamationmark" => "\uE7F4",
                "moon.fill" => "\uE708",
                "circle.lefthalf.filled" => "\uE790",
                "doc.on.doc" => "\uE7C3",
                "textformat.size.larger" => "\uE8D9",
                "arrow.up.forward.app" => "\uE71D",
                "folder" => "\uE8B7",
                "arrow.right.circle" => "\uE72A",
                "eye" or "eye.slash" => "\uE7B3",
                "square.stack.3d.up" => "\uE8A0",
                "folder.badge.plus" => "\uE7D1",
                "xmark.circle" => "\uE711",
                "clock.arrow.circlepath" => "\uE823",
                "doc.text.magnifyingglass" => "\uE8A5",
                "app.dashed" => "\uE71B",
                "gearshape.2" => "\uE713",
                _ => DefaultGlyph
            };
        });
    }

    public static ImageSource? IconFor(string path)
    {
        if (!LocalPathPolicy.TryNormalize(path, out var localPath))
        {
            return null;
        }
        path = localPath;

        if (IconCache.TryGetValue(path, out var cached))
        {
            return cached;
        }

        QueueIconExtraction(path, path, useFileAttributes: true);
        return null;
    }

    public static ImageSource? IconForRegisteredApplication(string appUserModelId)
    {
        if (string.IsNullOrWhiteSpace(appUserModelId))
        {
            return null;
        }

        var cacheKey = $"registered:{appUserModelId}";
        if (IconCache.TryGetValue(cacheKey, out var cached))
        {
            return cached;
        }

        // SHGetFileInfo resolves AppsFolder entries only when the shell is told
        // to use the path's file attributes; without this flag many packaged
        // applications return no icon at all.
        QueueIconExtraction(
            cacheKey,
            $"shell:AppsFolder\\{appUserModelId}",
            useFileAttributes: true,
            preferredPathFactory: () => ResolvePackageIconPath(appUserModelId));
        return null;
    }

    public static bool HasCachedIcon(ResultIcon icon)
    {
        var key = icon switch
        {
            ResultIcon.Application application => application.Path,
            ResultIcon.File file => file.Path,
            ResultIcon.RegisteredApplication application => $"registered:{application.AppUserModelId}",
            _ => ""
        };
        return !string.IsNullOrEmpty(key) && IconCache.ContainsKey(key);
    }

    public static void Preload(IEnumerable<ResultIcon> icons)
    {
        foreach (var icon in icons)
        {
            switch (icon)
            {
                case ResultIcon.Application application:
                    _ = IconFor(application.Path);
                    break;
                case ResultIcon.RegisteredApplication application:
                    _ = IconForRegisteredApplication(application.AppUserModelId);
                    break;
                case ResultIcon.File file:
                    _ = IconFor(file.Path);
                    break;
            }
        }
    }

    private static void QueueIconExtraction(
        string cacheKey,
        string shellPath,
        bool useFileAttributes,
        Func<string?>? preferredPathFactory = null)
    {
        if (UnavailableIconKeys.ContainsKey(cacheKey) || !PendingIconKeys.TryAdd(cacheKey, 0))
        {
            return;
        }

        _ = Task.Run(() =>
        {
            ImageSource? source = null;
            try
            {
                InitializeCom();
                var preferredPath = preferredPathFactory?.Invoke();
                source = preferredPath is not null
                    ? LoadImageSource(preferredPath)
                    : null;
                source ??= ExtractShellIconSource(shellPath, useFileAttributes)
                    ?? ExtractShellItemIconSource(shellPath);
                if (source is null)
                {
                    TrimCaches();
                    UnavailableIconKeys.TryAdd(cacheKey, 0);
                    return;
                }

                TrimCaches();
                IconCache[cacheKey] = source;
                Application.Current?.Dispatcher.BeginInvoke(() => IconAvailable?.Invoke(null, EventArgs.Empty));
            }
            catch
            {
                // Icon extraction is best-effort; callers retain the generic glyph.
                UnavailableIconKeys.TryAdd(cacheKey, 0);
            }
            finally
            {
                PendingIconKeys.TryRemove(cacheKey, out _);
            }
        });
    }

    private static string? ResolvePackageIconPath(string appUserModelId)
    {
        var separator = appUserModelId.IndexOf('!');
        if (separator <= 0 || separator == appUserModelId.Length - 1)
        {
            return null;
        }

        var packageFamily = appUserModelId[..separator];
        var applicationId = appUserModelId[(separator + 1)..];
        var familySeparator = packageFamily.LastIndexOf('_');
        if (familySeparator <= 0 || familySeparator == packageFamily.Length - 1)
        {
            return null;
        }

        var packagePrefix = packageFamily[..familySeparator] + "_";
        var publisherIdSuffix = "__" + packageFamily[(familySeparator + 1)..];
        const string packageRegistryPath =
            "Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\CurrentVersion\\AppModel\\Repository\\Packages";
        using var packages = Registry.CurrentUser.OpenSubKey(packageRegistryPath);
        if (packages is null)
        {
            return null;
        }

        foreach (var packageName in packages.GetSubKeyNames())
        {
            if (!packageName.StartsWith(packagePrefix, StringComparison.OrdinalIgnoreCase)
                || !packageName.EndsWith(publisherIdSuffix, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            using var package = packages.OpenSubKey(packageName);
            var root = package?.GetValue("PackageRootFolder") as string;
            if (string.IsNullOrWhiteSpace(root) || !Directory.Exists(root))
            {
                continue;
            }

            var manifest = Path.Combine(root, "AppxManifest.xml");
            if (!File.Exists(manifest))
            {
                continue;
            }

            try
            {
                var document = XDocument.Load(manifest, LoadOptions.None);
                var application = document.Descendants()
                    .FirstOrDefault(element =>
                        element.Name.LocalName == "Application"
                        && string.Equals(
                            (string?)element.Attribute("Id"),
                            applicationId,
                            StringComparison.OrdinalIgnoreCase));
                var visualElements = application?.Descendants()
                    .FirstOrDefault(element => element.Name.LocalName == "VisualElements");
                var logo = (string?)visualElements?.Attribute("Square44x44Logo")
                    ?? (string?)visualElements?.Attribute("Square150x150Logo")
                    ?? (string?)application?.Attribute("Logo");
                var path = ResolvePackageAsset(root, logo);
                if (path is not null)
                {
                    return path;
                }
            }
            catch
            {
                // A package can be removed between registry and manifest reads.
            }
        }

        return null;
    }

    private static string? ResolvePackageAsset(string root, string? relativePath)
    {
        if (string.IsNullOrWhiteSpace(relativePath))
        {
            return null;
        }

        var normalized = relativePath.Replace('/', Path.DirectorySeparatorChar);
        var direct = Path.Combine(root, normalized);
        if (File.Exists(direct))
        {
            return direct;
        }

        var directory = Path.GetDirectoryName(direct);
        var stem = Path.GetFileNameWithoutExtension(direct);
        var extension = Path.GetExtension(direct);
        if (directory is null || !Directory.Exists(directory))
        {
            return null;
        }

        return Directory.EnumerateFiles(directory, $"{stem}*{extension}")
            .OrderBy(PackageAssetPreference)
            .ThenBy(path => path.Length)
            .FirstOrDefault();
    }

    private static int PackageAssetPreference(string path)
    {
        var name = Path.GetFileName(path);
        if (name.Contains("targetsize-48_altform-unplated", StringComparison.OrdinalIgnoreCase))
        {
            return 0;
        }

        if (name.Contains("targetsize-44_altform-unplated", StringComparison.OrdinalIgnoreCase))
        {
            return 1;
        }

        if (name.Contains("targetsize-48", StringComparison.OrdinalIgnoreCase))
        {
            return 2;
        }

        if (name.Contains("scale-100", StringComparison.OrdinalIgnoreCase))
        {
            return 3;
        }

        if (name.Contains("scale-200", StringComparison.OrdinalIgnoreCase))
        {
            return 4;
        }

        return 5;
    }

    private static ImageSource? LoadImageSource(string path)
    {
        try
        {
            using var stream = File.OpenRead(path);
            var frame = BitmapFrame.Create(
                stream,
                BitmapCreateOptions.PreservePixelFormat,
                BitmapCacheOption.OnLoad);
            frame.Freeze();
            return frame;
        }
        catch
        {
            return null;
        }
    }

    private static ImageSource? ExtractShellIconSource(string path, bool useFileAttributes = true)
    {
        var icon = ExtractShellIcon(path, useFileAttributes && !File.Exists(path) && !Directory.Exists(path));
        if (icon is null)
        {
            return null;
        }

        try
        {
            using var bitmap = icon.ToBitmap();
            var bitmapHandle = bitmap.GetHbitmap();
            try
            {
                var imageSource = Imaging.CreateBitmapSourceFromHBitmap(
                    bitmapHandle,
                    IntPtr.Zero,
                    Int32Rect.Empty,
                    BitmapSizeOptions.FromWidthAndHeight(32, 32));
                imageSource.Freeze();
                return imageSource;
            }
            finally
            {
                _ = DeleteObject(bitmapHandle);
            }
        }
        finally
        {
            icon.Dispose();
        }
    }

    private static ImageSource? ExtractShellItemIconSource(string path)
    {
        IShellItemImageFactory? factory = null;
        var interfaceId = ShellItemImageFactoryId;
        try
        {
            if (SHCreateItemFromParsingName(path, IntPtr.Zero, ref interfaceId, out factory) < 0)
            {
                return null;
            }

            factory.GetImage(new ShellSize(32, 32), ShellImageFlags.IconOnly | ShellImageFlags.BiggerSizeOk, out var bitmapHandle);
            if (bitmapHandle == IntPtr.Zero)
            {
                return null;
            }

            try
            {
                var imageSource = Imaging.CreateBitmapSourceFromHBitmap(
                    bitmapHandle,
                    IntPtr.Zero,
                    Int32Rect.Empty,
                    BitmapSizeOptions.FromWidthAndHeight(32, 32));
                imageSource.Freeze();
                return imageSource;
            }
            finally
            {
                _ = DeleteObject(bitmapHandle);
            }
        }
        catch
        {
            return null;
        }
        finally
        {
            if (factory is not null)
            {
                _ = Marshal.FinalReleaseComObject(factory);
            }
        }
    }

    private static Icon? ExtractShellIcon(string path, bool useFileAttributes)
    {
        var info = new ShFileInfo();
        var flags = ShgfiIcon | ShgfiLargeIcon;
        if (useFileAttributes)
        {
            flags |= ShgfiUseFileAttributes;
        }
        var result = SHGetFileInfo(path, FileAttributes.Normal, ref info, Marshal.SizeOf(info), flags);
        if (result == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            return (Icon)Icon.FromHandle(info.Icon).Clone();
        }
        finally
        {
            if (info.Icon != IntPtr.Zero)
            {
                _ = DestroyIcon(info.Icon);
            }
        }
    }

    public static void ClearCache()
    {
        IconCache.Clear();
        PendingIconKeys.Clear();
        UnavailableIconKeys.Clear();
    }

    /// <summary>
    /// The icon caches are process-lifetime by design; keep them bounded by
    /// dropping everything once they grow past a generous ceiling. A purge only
    /// costs re-extraction on the next request, never correctness.
    /// </summary>
    private static void TrimCaches()
    {
        const int maximumEntries = 1_024;
        if (IconCache.Count <= maximumEntries && UnavailableIconKeys.Count <= maximumEntries)
        {
            return;
        }

        IconCache.Clear();
        UnavailableIconKeys.Clear();
    }

    private const uint ShgfiIcon = 0x000000100;
    private const uint ShgfiLargeIcon = 0x000000000;
    private const uint ShgfiUseFileAttributes = 0x000000010;

    [StructLayout(LayoutKind.Sequential)]
    private struct ShFileInfo
    {
        public IntPtr Icon;
        public int IconIndex;
        public uint Attributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string DisplayName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)]
        public string TypeName;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SHGetFileInfo(
        string pszPath,
        FileAttributes dwFileAttributes,
        ref ShFileInfo psfi,
        int cbFileInfo,
        uint uFlags);

    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr hIcon);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr hObject);

    private static readonly Guid ShellItemImageFactoryId = new("bcc18b79-ba16-442f-80c4-8a59ea479c3c");

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHCreateItemFromParsingName(
        string path,
        IntPtr bindContext,
        ref Guid interfaceId,
        [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory factory);

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct ShellSize
    {
        public ShellSize(int width, int height)
        {
            Width = width;
            Height = height;
        }

        public readonly int Width;
        public readonly int Height;
    }

    [Flags]
    private enum ShellImageFlags : uint
    {
        IconOnly = 0x00000004,
        BiggerSizeOk = 0x00000001
    }

    [ComImport]
    [Guid("bcc18b79-ba16-442f-80c4-8a59ea479c3c")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItemImageFactory
    {
        void GetImage(ShellSize size, ShellImageFlags flags, out IntPtr bitmap);
    }

    /// <summary>Initializes COM (STA) for shell icon extraction on the UI thread.</summary>
    public static void InitializeCom()
    {
        try
        {
            _ = CoInitializeEx(IntPtr.Zero, 0x00000002 /* COINIT_APARTMENTTHREADED */);
        }
        catch
        {
            // COM may already be initialized; icon extraction falls back to glyphs.
        }
    }

    [DllImport("ole32.dll")]
    private static extern int CoInitializeEx(IntPtr pvReserved, uint dwCoInit);
}

public sealed class ResultIconConverter : System.Windows.Data.IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, System.Globalization.CultureInfo culture)
    {
        switch (value)
        {
            case ResultIcon.System system:
                return IconService.GlyphFor(system.Name);
            case ResultIcon.Application application:
                return IconService.IconFor(application.Path) ?? (object)IconService.GlyphFor("app.dashed");
            case ResultIcon.RegisteredApplication application:
                return IconService.IconForRegisteredApplication(application.AppUserModelId)
                    ?? (object)IconService.GlyphFor("app.dashed");
            case ResultIcon.File file:
                return IconService.IconFor(file.Path) ?? (object)IconService.GlyphFor("doc.text.magnifyingglass");
            default:
                return IconService.GlyphFor("");
        }
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, System.Globalization.CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

public sealed class IsFileIconConverter : System.Windows.Data.IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, System.Globalization.CultureInfo culture)
    {
        var isFileIcon = value is ResultIcon.Application or ResultIcon.RegisteredApplication or ResultIcon.File;
        var hasCachedImage = value is ResultIcon icon && IconService.HasCachedIcon(icon);
        var invert = string.Equals(parameter as string, "invert", StringComparison.OrdinalIgnoreCase);
        return (invert ? !hasCachedImage : hasCachedImage)
            ? System.Windows.Visibility.Visible
            : System.Windows.Visibility.Collapsed;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, System.Globalization.CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}
