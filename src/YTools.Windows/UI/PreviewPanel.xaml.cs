using System.IO;
using System.Windows.Controls;
using System.Windows.Media.Imaging;

namespace YTools.UI;

public partial class PreviewPanel : UserControl
{
    private static readonly HashSet<string> ImageExtensions =
    [
        ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp", ".ico", ".tiff", ".tif"
    ];

    private static readonly HashSet<string> TextExtensions =
    [
        ".txt", ".md", ".markdown", ".log", ".json", ".xml", ".html", ".htm", ".css",
        ".js", ".ts", ".py", ".cs", ".cpp", ".h", ".c", ".java", ".rs", ".go", ".swift",
        ".ini", ".cfg", ".conf", ".yaml", ".yml", ".toml", ".csv", ".tsv", ".bat", ".ps1",
        ".sh", ".sql", ".xaml", ".csproj", ".sln", ".gitignore", ".editorconfig", ".license"
    ];

    private CancellationTokenSource? _cancellation;
    private long _previewRequest;

    public PreviewPanel()
    {
        InitializeComponent();
        Clear();
    }

    public void ShowPath(string? path)
    {
        var request = Interlocked.Increment(ref _previewRequest);
        _cancellation?.Cancel();
        _cancellation = new CancellationTokenSource();
        if (string.IsNullOrEmpty(path) || (!File.Exists(path) && !Directory.Exists(path)))
        {
            Clear();
            return;
        }

        TitleText.Text = Path.GetFileName(path);
        ImagePreview.Source = null;
        TextPreview.Clear();
        ImagePreview.Visibility = System.Windows.Visibility.Collapsed;
        TextPreview.Visibility = System.Windows.Visibility.Collapsed;
        InfoPreview.Visibility = System.Windows.Visibility.Collapsed;
        LoadingText.Visibility = System.Windows.Visibility.Visible;
        _ = LoadAsync(path, request, _cancellation.Token);
    }

    public void Clear()
    {
        Interlocked.Increment(ref _previewRequest);
        _cancellation?.Cancel();
        ImagePreview.Source = null;
        TextPreview.Clear();
        ImagePreview.Visibility = System.Windows.Visibility.Collapsed;
        TextPreview.Visibility = System.Windows.Visibility.Collapsed;
        InfoPreview.Visibility = System.Windows.Visibility.Collapsed;
        LoadingText.Visibility = System.Windows.Visibility.Collapsed;
        TitleText.Text = "";
    }

    private async Task LoadAsync(string path, long request, CancellationToken cancellationToken)
    {
        try
        {
            var extension = Path.GetExtension(path).ToLowerInvariant();
            if (ImageExtensions.Contains(extension))
            {
                var image = await Task.Run(() => DecodeImage(path), cancellationToken);
                if (!IsCurrentRequest(request, cancellationToken))
                {
                    return;
                }

                ImagePreview.Source = image;
                LoadingText.Visibility = System.Windows.Visibility.Collapsed;
                ImagePreview.Visibility = System.Windows.Visibility.Visible;
            }
            else if (TextExtensions.Contains(extension))
            {
                var info = new FileInfo(path);
                if (info.Length <= 512 * 1024)
                {
                    var text = await Task.Run(() => File.ReadAllText(path), cancellationToken);
                    if (!IsCurrentRequest(request, cancellationToken))
                    {
                        return;
                    }

                    TextPreview.Text = text;
                    LoadingText.Visibility = System.Windows.Visibility.Collapsed;
                    TextPreview.Visibility = System.Windows.Visibility.Visible;
                }
                else
                {
                    ShowInfo(path, request, cancellationToken);
                }
            }
            else
            {
                ShowInfo(path, request, cancellationToken);
            }
        }
        catch (OperationCanceledException)
        {
            // A newer selection superseded this preview.
        }
        catch
        {
            ShowInfo(path, request, cancellationToken);
        }
    }

    private bool IsCurrentRequest(long request, CancellationToken cancellationToken)
    {
        return !cancellationToken.IsCancellationRequested
            && request == Interlocked.Read(ref _previewRequest);
    }

    private void ShowInfo(string path, long request, CancellationToken cancellationToken)
    {
        if (!IsCurrentRequest(request, cancellationToken))
        {
            return;
        }

        LoadingText.Visibility = System.Windows.Visibility.Collapsed;
        InfoIconText.Text = IconService.GlyphFor("doc.text.magnifyingglass");
        InfoNameText.Text = Path.GetFileName(path);
        try
        {
            var info = new FileInfo(path);
            InfoDetailText.Text = Directory.Exists(path)
                ? "文件夹"
                : $"{FormatSize(info.Length)} · {info.LastWriteTime:yyyy-MM-dd HH:mm}";
        }
        catch
        {
            InfoDetailText.Text = "";
        }

        InfoPreview.Visibility = System.Windows.Visibility.Visible;
    }

    private static BitmapImage DecodeImage(string path)
    {
        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        bitmap.CreateOptions = BitmapCreateOptions.IgnoreImageCache;
        // Preview content is displayed in a narrow pane. Decode to its useful
        // display size so a multi-megapixel photograph cannot allocate its full
        // pixel buffer merely because the user moved the selection onto it.
        bitmap.DecodePixelWidth = 520;
        bitmap.DecodePixelHeight = 520;
        bitmap.UriSource = new Uri(path, UriKind.Absolute);
        bitmap.EndInit();
        bitmap.Freeze();
        return bitmap;
    }

    private static string FormatSize(long bytes)
    {
        if (bytes < 1024)
        {
            return $"{bytes} B";
        }

        if (bytes < 1024 * 1024)
        {
            return $"{bytes / 1024.0:F1} KB";
        }

        return $"{bytes / (1024.0 * 1024):F1} MB";
    }
}
