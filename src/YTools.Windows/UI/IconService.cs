using System.Collections.Concurrent;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using YTools.ModuleKit;

namespace YTools.UI;

/// <summary>
/// Supplies result icons: Segoe glyphs for system icons, shell file icons for
/// files and applications, with a bounded in-memory cache.
/// </summary>
public static class IconService
{
    private static readonly ConcurrentDictionary<string, string> GlyphCache = new();
    private static readonly ConcurrentDictionary<string, ImageSource?> IconCache = new();
    private static readonly string DefaultGlyph = "\uE8A5";

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
        if (string.IsNullOrEmpty(path))
        {
            return null;
        }

        return IconCache.GetOrAdd(path, static fullPath =>
        {
            try
            {
                var icon = ExtractShellIcon(fullPath);
                if (icon is not null)
                {
                    var bitmap = icon.ToBitmap();
                    var imageSource = Imaging.CreateBitmapSourceFromHBitmap(
                        bitmap.GetHbitmap(),
                        IntPtr.Zero,
                        Int32Rect.Empty,
                        BitmapSizeOptions.FromWidthAndHeight(32, 32));
                    bitmap.Dispose();
                    icon.Dispose();
                    imageSource.Freeze();
                    return imageSource;
                }
            }
            catch
            {
                // Fall through to the generic glyph.
            }

            return null;
        });
    }

    public static void ClearCache()
    {
        IconCache.Clear();
    }

    private static Icon? ExtractShellIcon(string path)
    {
        var info = new ShFileInfo();
        var flags = ShgfiIcon | ShgfiLargeIcon | ShgfiUseFileAttributes;
        var result = SHGetFileInfo(path, FileAttributes.Normal, ref info, Marshal.SizeOf(info), flags);
        return result == IntPtr.Zero ? null : (Icon)Icon.FromHandle(info.Icon).Clone();
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
        var isFileIcon = value is ResultIcon.Application or ResultIcon.File;
        var invert = string.Equals(parameter as string, "invert", StringComparison.OrdinalIgnoreCase);
        return (invert ? !isFileIcon : isFileIcon)
            ? System.Windows.Visibility.Visible
            : System.Windows.Visibility.Collapsed;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, System.Globalization.CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}
