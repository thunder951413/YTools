using YTools.Models;
using YTools.Services;

namespace YTools.Windows.Tests;

public sealed class ClipboardPreviewTests
{
    [Fact]
    public async Task SwitchAndHideInvalidateDelayedImage()
    {
        var gate = new TaskCompletionSource<byte[]?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var controller = new ClipboardPreviewController(_ => gate.Task);
        controller.Show(Item(ClipboardItemKind.Image, ["image"]));
        var text = Item(ClipboardItemKind.Text, [new string('文', 5000)]);
        controller.Select(text);
        gate.SetResult(null);
        await controller.WaitUntilLoadedAsync();
        Assert.Same(text, controller.Item);
        Assert.Equal(text.Payload[0], controller.Text);
        Assert.Null(controller.Image);
        Assert.Null(controller.Error);
        Assert.False(controller.IsLoading);
        controller.Hide();
        Assert.Null(controller.Item);
        Assert.False(controller.IsVisible);
    }

    [Fact]
    public async Task MissingOriginalNeverUsesStoredThumbnail()
    {
        var controller = new ClipboardPreviewController(_ => Task.FromResult<byte[]?>(null));
        controller.Show(Item(ClipboardItemKind.Image, ["image"]) with { BinaryData = [1, 2, 3] });
        await controller.WaitUntilLoadedAsync();
        Assert.Null(controller.Image);
        Assert.NotNull(controller.Error);
        Assert.False(controller.IsLoading);
    }

    [Fact]
    public async Task OriginalImageKeepsDimensionsAndCanCrossThreadBoundary()
    {
        var bytes = Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ1kAAAAASUVORK5CYII=");
        var controller = new ClipboardPreviewController(_ => Task.FromResult<byte[]?>(bytes));
        controller.Show(Item(ClipboardItemKind.Image, ["image"]));
        await controller.WaitUntilLoadedAsync();
        Assert.NotNull(controller.Image);
        Assert.True(controller.Image.IsFrozen);
        Assert.Equal(1, controller.Image.PixelWidth);
        Assert.Equal(1, controller.Image.PixelHeight);
        Assert.Contains("1 × 1", controller.ImageDimensions);
    }

    [Fact]
    public void FilesPreviewKeepsCompletePaths()
    {
        var controller = new ClipboardPreviewController(_ => Task.FromResult<byte[]?>(null));
        controller.Show(Item(ClipboardItemKind.Files, [@"C:\full\path\first.txt", @"D:\second\another.txt"]));
        Assert.Contains(@"C:\full\path\first.txt", controller.Text);
        Assert.Contains(@"D:\second\another.txt", controller.Text);
    }

    private static ClipboardHistoryItem Item(ClipboardItemKind kind, string[] payload) =>
        new(Guid.NewGuid(), kind, payload, DateTimeOffset.UtcNow, null);
}
