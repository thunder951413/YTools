using System.IO;
using System.Windows.Media.Imaging;
using YTools.Infrastructure;
using YTools.Models;

namespace YTools.Services;

public sealed class ClipboardPreviewController(Func<Guid, Task<byte[]?>> loadImage) : ObservableObject
{
    private bool _isVisible;
    private ClipboardHistoryItem? _item;
    private BitmapSource? _image;
    private bool _isLoading;
    private string? _error;
    private long _generation;
    public string ImageDimensions { get; private set; } = "";
    private CancellationTokenSource? _cancellation;
    private Task _loading = Task.CompletedTask;
    public bool IsVisible { get => _isVisible; private set => SetField(ref _isVisible, value); }
    public ClipboardHistoryItem? Item { get => _item; private set => SetField(ref _item, value); }
    public BitmapSource? Image { get => _image; private set => SetField(ref _image, value); }
    public bool IsLoading { get => _isLoading; private set => SetField(ref _isLoading, value); }
    public string? Error { get => _error; private set => SetField(ref _error, value); }
    public string Text => Item is { Kind: not ClipboardItemKind.Image } item ? string.Join(item.Kind == ClipboardItemKind.Files ? "\n\n" : "\n", item.Payload) : "";
    public string Detail => Item?.SourceApplication ?? "未知来源";
    public void Show(ClipboardHistoryItem? selected) { IsVisible = true; Select(selected); }
    public void Hide() { IsVisible = false; ClearContent(); }
    public void ClearContent()
    {
        _generation++;
        _cancellation?.Cancel();
        _cancellation?.Dispose();
        _cancellation = null;
        Item = null; Image = null; Error = null; IsLoading = false;
        ImageDimensions = ""; RaisePropertyChanged(nameof(ImageDimensions));
        RaisePropertyChanged(nameof(Text)); RaisePropertyChanged(nameof(Detail));
    }
    public void Select(ClipboardHistoryItem? selected)
    {
        if (!IsVisible || Item == selected) { return; }
        ClearContent();
        Item = selected;
        RaisePropertyChanged(nameof(Text)); RaisePropertyChanged(nameof(Detail));
        if (selected?.Kind != ClipboardItemKind.Image) { return; }
        IsLoading = true;
        var cancellation = new CancellationTokenSource();
        _cancellation = cancellation;
        _loading = LoadAsync(selected.Id, _generation, cancellation.Token);
    }
    public Task WaitUntilLoadedAsync() => _loading;
    private async Task LoadAsync(Guid id, long generation, CancellationToken token)
    {
        try
        {
            var data = await loadImage(id).WaitAsync(token);
            var image = data is { Length: > 0 and <= 5_000_000 }
                ? await Task.Run(() => Decode(data), token) : null;
            if (token.IsCancellationRequested || generation != _generation || !IsVisible || Item?.Id != id) { return; }
            Image = image?.Bitmap;
            ImageDimensions = image is { } decoded ? $"原件 {decoded.Width} × {decoded.Height} 像素" : "";
            RaisePropertyChanged(nameof(ImageDimensions));
            IsLoading = false;
            Error = image is null ? "无法读取图片原件；未使用缩略图替代。" : null;
        }
        catch (OperationCanceledException) { }
        catch (Exception)
        {
            if (token.IsCancellationRequested || generation != _generation || !IsVisible) { return; }
            IsLoading = false;
            Error = "无法读取或解码图片原件；未使用缩略图替代。";
        }
    }
    private sealed record DecodedImage(BitmapSource Bitmap, int Width, int Height);
    private static DecodedImage Decode(byte[] data)
    {
        using var stream = new MemoryStream(data, writable: false);
        var source = BitmapDecoder.Create(stream, BitmapCreateOptions.DelayCreation, BitmapCacheOption.OnDemand);
        var width = source.Frames[0].PixelWidth;
        var height = source.Frames[0].PixelHeight;
        stream.Position = 0;
        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        if (width >= height && width > 1024) { bitmap.DecodePixelWidth = 1024; }
        else if (height > 1024) { bitmap.DecodePixelHeight = 1024; }
        bitmap.StreamSource = stream;
        bitmap.EndInit();
        bitmap.Freeze();
        return new DecodedImage(bitmap, width, height);
    }
}
