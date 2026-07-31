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

    public PreviewPanel()
    {
        InitializeComponent();
        Clear();
    }

    public void ShowPath(string? path)
    {
        _cancellation?.Cancel();
        _cancellation = new CancellationTokenSource();
        if (string.IsNullOrEmpty(path) || (!File.Exists(path) && !Directory.Exists(path)))
        {
            Clear();
            return;
        }

        TitleText.Text = Path.GetFileName(path);
        LoadingText.Visibility = System.Windows.Visibility.Visible;
        _ = LoadAsync(path, _cancellation.Token);
    }

    public void Clear()
    {
        _cancellation?.Cancel();
        ImagePreview.Visibility = System.Windows.Visibility.Collapsed;
        TextPreview.Visibility = System.Windows.Visibility.Collapsed;
        InfoPreview.Visibility = System.Windows.Visibility.Collapsed;
        LoadingText.Visibility = System.Windows.Visibility.Collapsed;
        TitleText.Text = "";
    }

    private async Task LoadAsync(string path, CancellationToken cancellationToken)
    {
        try
        {
            var extension = Path.GetExtension(path).ToLowerInvariant();
            if (ImageExtensions.Contains(extension))
            {
                var image = await Task.Run(() => DecodeImage(path), cancellationToken);
                if (cancellationToken.IsCancellationRequested)
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
                    if (cancellationToken.IsCancellationRequested)
                    {
                        return;
                    }

                    TextPreview.Text = text;
                    LoadingText.Visibility = System.Windows.Visibility.Collapsed;
                    TextPreview.Visibility = System.Windows.Visibility.Visible;
                }
                else
                {
                    ShowInfo(path);
                }
            }
            else
            {
                ShowInfo(path);
            }
        }
        catch (OperationCanceledException)
        {
            // A newer selection superseded this preview.
        }
        catch
        {
            ShowInfo(path);
        }
    }

    private void ShowInfo(string path)
    {
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
