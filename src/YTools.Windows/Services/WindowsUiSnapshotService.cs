using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using YTools.Core;
using YTools.Models;
using YTools.Services.Storage;
using YTools.UI;

namespace YTools.Services;

/// <summary>Offline synthetic fixtures. No monitor, live clipboard, credentials or user stores.</summary>
internal static class WindowsUiSnapshotService
{
    public static async Task CaptureAsync(string output)
    {
        if (!LocalPathPolicy.TryNormalize(output, out output)) { throw new IOException("Snapshot output must be a local absolute path."); }
        Directory.CreateDirectory(output);
        var root = Path.Combine(Path.GetTempPath(), "ytools-ui-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var key = Enumerable.Repeat((byte)17, 32).ToArray();
        var preferences = new AppPreferences(Path.Combine(root, "settings.json"), () => false);
        var snippets = new SnippetManager(() => new SecureCodableStore(Path.Combine(root, "snippets.enc"), _ => key));
        var recent = new RecentDocumentsManager(() => new SecureCodableStore(Path.Combine(root, "recent.enc"), _ => key));
        try
        {
            await snippets.WaitUntilLoadedAsync();
            await snippets.SaveAsync(string.Concat(Enumerable.Repeat("合成片段正文，用于检查完整编辑内容与滚动。\n", 20)), "验收片段", "fixture");
            var item = new ClipboardHistoryItem(Guid.NewGuid(), ClipboardItemKind.Text,
                [string.Concat(Enumerable.Repeat("用于检查全文预览、换行和选择的合成文本。", 30))], DateTimeOffset.UtcNow, "Synthetic Fixture", IsPinned: true);
            foreach (var theme in new[] { AppTheme.Light, AppTheme.Dark })
            {
                preferences.Theme = theme;
                ThemeService.Apply(preferences);
                var name = theme == AppTheme.Dark ? "dark" : "light";
                var settings = new SettingsWindow();
                settings.Attach(preferences, null, snippets, recent);
                settings.Width = 980; settings.Height = 700;
                settings.SelectSnapshotSection("snippets");
                await RenderAsync(settings, Path.Combine(output, "settings-snippets-" + name), scale: 1);
                await RenderAsync(settings, Path.Combine(output, "settings-snippets-2x-" + name), scale: 2);
                settings.SearchSnapshotSetting("同步口令");
                await RenderAsync(settings, Path.Combine(output, "settings-search-" + name), scale: 1);
                settings.OpenSnapshotTarget("CloudPassphrase");
                await RenderAsync(settings, Path.Combine(output, "settings-target-" + name), scale: 1);
                settings.Close();
                var clipboard = new ClipboardWindow { DataContext = new ClipboardSnapshotPresentation(item) };
                clipboard.ShowSnapshotPreview(item);
                await RenderAsync(clipboard, Path.Combine(output, "clipboard-preview-" + name), scale: 1);
                await RenderAsync(clipboard, Path.Combine(output, "clipboard-preview-2x-" + name), scale: 2);
                clipboard.Close();
            }
            await snippets.FlushPendingChangesAsync();
            await recent.FlushPendingChangesAsync();
            await preferences.FlushPendingChangesAsync();
        }
        finally { Directory.Delete(root, recursive: true); }
    }
    private static async Task RenderAsync(Window window, string path, int scale)
    {
        window.Left = -10_000; window.Top = -10_000; window.ShowInTaskbar = false;
        if (!window.IsVisible) { window.Show(); }
        await Dispatcher.Yield(DispatcherPriority.ApplicationIdle);
        window.UpdateLayout();
        var view = (FrameworkElement)window.Content;
        if (view is System.Windows.Controls.Panel panel && panel.Background is null) { panel.Background = window.Background; }
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(view.ActualWidth * scale), (int)Math.Ceiling(view.ActualHeight * scale), 96 * scale, 96 * scale, PixelFormats.Pbgra32);
        bitmap.Render(view);
        bitmap.Freeze();
        await Task.Run(() =>
        {
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using var file = File.Create(path + ".png");
            encoder.Save(file);
        });
    }
    private sealed class ClipboardSnapshotPresentation(ClipboardHistoryItem item)
    {
        public string Query { get; set; } = "";
        public int SelectedIndex { get; set; }
        public IReadOnlyList<ClipboardHistoryItem> FilteredItems { get; } = [item];
        public string PageDescription => "已显示 1 / 匹配 1 条";
        public bool HasMore => false;
        public bool IsCopying => false;
        public string? CopyError => null;
        public string CloudSyncStatus => "";
    }
}
