using System.Globalization;
using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using YTools.ModuleKit;
using YTools.UI;

namespace YTools.Windows.Tests;

public sealed class IconRenderingTests
{
    [Fact]
    public void SystemGlyphIsNeverAssignedToImageSource()
    {
        var converter = new ResultIconConverter();
        var icon = new ResultIcon.System("gearshape");

        Assert.Null(converter.Convert(icon, typeof(ImageSource), null, CultureInfo.InvariantCulture));
        Assert.Equal(IconService.GlyphFor("gearshape"),
            converter.Convert(icon, typeof(string), null, CultureInfo.InvariantCulture));
    }

    [Fact]
    public async Task DesktopApplicationIconRemainsAnImageWhenTheCacheCompletes()
    {
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe");
        var icon = new ResultIcon.Application(path);
        var converter = new ResultIconConverter();
        object? image = null;
        for (var attempt = 0; attempt < 100; ++attempt)
        {
            image = converter.Convert(icon, typeof(ImageSource), null, CultureInfo.InvariantCulture);
            if (image is BitmapSource) break;
            await Task.Delay(50);
        }

        var bitmap = Assert.IsAssignableFrom<BitmapSource>(image);
        Assert.True(bitmap.IsFrozen);
        Assert.True(bitmap.PixelWidth > 0 && bitmap.PixelHeight > 0);
        Assert.Equal(IconService.GlyphFor("app.dashed"),
            converter.Convert(icon, typeof(string), null, CultureInfo.InvariantCulture));
    }
}
