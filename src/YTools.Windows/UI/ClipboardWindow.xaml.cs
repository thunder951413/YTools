using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using YTools.Core;
using YTools.Models;
using YTools.Services;

namespace YTools.UI;

public partial class ClipboardWindow : Window
{
    private readonly PanelCommandRouter _router = new();
    private readonly ClipboardPreviewController _preview;
    private ClipboardHistoryManager? _manager;
    private SnippetManager? _snippets;

    public ClipboardWindow()
    {
        InitializeComponent();
        _preview = new ClipboardPreviewController(id => _manager?.LoadPreviewImageAsync(id) ?? Task.FromResult<byte[]?>(null));
        ClipboardPreviewBorder.DataContext = _preview;
        _preview.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(ClipboardPreviewController.IsVisible))
            {
                ClipboardPreviewColumn.Width = new GridLength(_preview.IsVisible ? 280 : 0);
            }
        };
    }

    internal void ShowSnapshotPreview(ClipboardHistoryItem item) { _preview.Show(item); }

    public event Action? Hidden;

    public void Attach(ClipboardHistoryManager manager, SnippetManager snippets)
    {
        _manager = manager;
        _snippets = snippets;
        DataContext = manager;
        manager.PropertyChanged += OnManagerPropertyChanged;
    }

    public void ShowClipboard()
    {
        if (_manager is null)
        {
            return;
        }

        _manager.PrepareForPresentation();
        FilterAll.IsChecked = true;
        Show();
        Activate();
        SearchBox.Focus();
    }

    public void HidePanel()
    {
        _preview.Hide();
        Hide();
        Hidden?.Invoke();
    }

    private void OnManagerPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(ClipboardHistoryManager.Query) or nameof(ClipboardHistoryManager.Filter))
        { _preview.ClearContent(); }
        if (e.PropertyName is nameof(ClipboardHistoryManager.FilteredItems) or nameof(ClipboardHistoryManager.SelectedIndex))
        {
            var selected = _manager?.FilteredItems.ElementAtOrDefault(_manager.SelectedIndex);
            ClipboardList.ScrollIntoView(selected);
            _preview.Select(selected);
        }

        if (e.PropertyName == nameof(ClipboardHistoryManager.CloudSyncStatus))
        {
            SyncStatusText.ToolTip = _manager?.CloudSyncStatus;
        }
    }

    private void TogglePreview_Click(object sender, RoutedEventArgs e)
    {
        if (_preview.IsVisible) { _preview.Hide(); }
        else { _preview.Show(_manager?.FilteredItems.ElementAtOrDefault(_manager.SelectedIndex)); }
    }

    private void LoadMore_Click(object sender, RoutedEventArgs e) => _manager?.LoadMore();

    private void OnDeactivated(object sender, EventArgs e)
    {
        if (IsVisible)
        {
            HidePanel();
        }
    }

    private async void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (_manager is null)
        {
            return;
        }

        if ((e.Key is Key.Escape or Key.Enter or Key.Up or Key.Down or Key.Left or Key.Right or Key.Back)
            && IsComposingIme())
        {
            return;
        }

        if (e.OriginalSource is TextBox previewTextBox && previewTextBox != SearchBox
            && e.Key is Key.Enter or Key.Up or Key.Down or Key.Left or Key.Right or Key.Back or Key.Delete)
        { return; }

        var keyCode = KeyInterop.VirtualKeyFromKey(e.Key);
        var modifiers = PanelModifiers(Keyboard.Modifiers);
        var command = _router.Command(
            new PanelKeyEvent(keyCode, modifiers),
            PanelInputMode.Clipboard);
        if (command is not { } routed)
        {
            return;
        }

        e.Handled = true;
        switch (routed.Kind)
        {
            case PanelCommandKind.ActivateSelected:
                if (await _manager.CopySelectedAsync())
                {
                    HidePanel();
                }

                break;
            case PanelCommandKind.ToggleClipboardPreview:
                TogglePreview_Click(this, new RoutedEventArgs());
                break;
            case PanelCommandKind.Escape:
                if (_preview.IsVisible) { _preview.Hide(); break; }
                if (!_manager.ClearQuery())
                {
                    HidePanel();
                }

                break;
            case PanelCommandKind.MoveSelection:
                _manager.MoveSelection(routed.Payload);
                break;
            case PanelCommandKind.DeleteClipboardItem:
                _manager.DeleteSelected();
                break;
            case PanelCommandKind.SaveClipboardAsSnippet:
                if (_manager.SelectedText is { } text && _snippets is { } snippets)
                {
                    _ = SaveSnippetAsync(snippets, text);
                }

                break;
            case PanelCommandKind.OpenSettings:
                HidePanel();
                OnOpenSettings?.Invoke();
                break;
        }
    }

    private async Task SaveSnippetAsync(SnippetManager snippets, string text)
    {
        if (await snippets.SaveAsync(text))
        {
            System.Media.SystemSounds.Asterisk.Play();
            return;
        }

        MessageBox.Show(
            this,
            snippets.SaveError ?? "加密存储当前不可用。",
            "无法保存文本片段",
            MessageBoxButton.OK,
            MessageBoxImage.Warning);
    }

    public Action? OnOpenSettings { get; set; }

    private void Filter_Checked(object sender, RoutedEventArgs e)
    {
        if (_manager is null || sender is not RadioButton { Tag: string tag })
        {
            return;
        }

        _manager.Filter = Enum.TryParse<ClipboardFilter>(tag, out var filter)
            ? filter
            : ClipboardFilter.All;
    }

    private void ClearRecent_Click(object sender, RoutedEventArgs e)
    {
        if (_manager is not null && ConfirmClear("永久清空最近 30 分钟的剪贴板历史？"))
        { _manager.ClearRecent(30); }
    }

    private async void SyncNow_Click(object sender, RoutedEventArgs e)
    {
        if (_manager is not null)
        {
            SyncButton.IsEnabled = false;
            try
            {
                await _manager.SyncCloudNowAsync();
            }
            finally
            {
                SyncButton.IsEnabled = true;
            }
        }
    }

    private void ClearAll_Click(object sender, RoutedEventArgs e)
    {
        if (_manager is null)
        {
            return;
        }

        if (ConfirmClear("永久清空全部剪贴板历史？"))
        {
            _manager.Clear();
        }
    }

    private bool ConfirmClear(string question) => MessageBox.Show(this,
        question + "\n\n" + _manager?.DeletionScopeDescription,
        "清理剪贴板历史", MessageBoxButton.OKCancel, MessageBoxImage.Warning) == MessageBoxResult.OK;

    private void OnContextMenuOpening(object sender, ContextMenuEventArgs e)
    {
        if (ClipboardList.SelectedItem is not ClipboardHistoryItem item)
        {
            e.Handled = true;
            return;
        }

        var menu = new ContextMenu();
        var copy = new MenuItem { Header = "复制" };
        copy.Click += async (_, _) =>
        {
            if (_manager is not null && await _manager.CopyAsync(item)) { HidePanel(); }
        };
        var pin = new MenuItem { Header = item.IsPinned ? "取消固定" : "固定" };
        pin.Click += (_, _) => _manager?.TogglePinned(item);
        var delete = new MenuItem { Header = "删除" };
        delete.Click += (_, _) => _manager?.Delete(item);
        menu.Items.Add(copy);
        menu.Items.Add(pin);
        menu.Items.Add(delete);
        ClipboardList.ContextMenu = menu;
    }

    private static PanelKeyModifiers PanelModifiers(ModifierKeys modifiers)
    {
        var result = PanelKeyModifiers.None;
        if (modifiers.HasFlag(ModifierKeys.Control))
        {
            result |= PanelKeyModifiers.Command;
        }

        if (modifiers.HasFlag(ModifierKeys.Alt))
        {
            result |= PanelKeyModifiers.Option;
        }

        if (modifiers.HasFlag(ModifierKeys.Shift))
        {
            result |= PanelKeyModifiers.Shift;
        }

        return result;
    }

    private bool IsComposingIme()
    {
        var handle = new System.Windows.Interop.WindowInteropHelper(this).Handle;
        var context = NativeImports.ImmGetContext(handle);
        if (context == IntPtr.Zero)
        {
            return false;
        }

        try
        {
            return NativeImports.ImmGetCompositionString(context, 0x0008, IntPtr.Zero, 0) > 0;
        }
        finally
        {
            _ = NativeImports.ImmReleaseContext(handle, context);
        }
    }
}

public sealed class ClipboardKindToGlyphConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        return value switch
        {
            ClipboardItemKind.Text => "\uE8D4",
            ClipboardItemKind.Files => "\uE8B7",
            ClipboardItemKind.Image => "\uE91B",
            _ => "\uE8D4"
        };
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

public sealed class ClipboardThumbnailConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is not byte[] png || png.Length == 0)
        {
            return System.Windows.DependencyProperty.UnsetValue;
        }

        try
        {
            using var stream = new MemoryStream(png);
            // History rows only show a 30px thumbnail. Scaling before the image is
            // handed to WPF keeps a pasted high-resolution screenshot from holding
            // an unnecessary full-size decoded buffer in the virtualized list.
            var thumbnail = new BitmapImage();
            thumbnail.BeginInit();
            thumbnail.CacheOption = BitmapCacheOption.OnLoad;
            thumbnail.DecodePixelWidth = 72;
            thumbnail.DecodePixelHeight = 72;
            thumbnail.StreamSource = stream;
            thumbnail.EndInit();
            thumbnail.Freeze();
            return thumbnail;
        }
        catch
        {
            return System.Windows.DependencyProperty.UnsetValue;
        }
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

public sealed class ClipboardKindVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var kind = value?.ToString() ?? "";
        var expected = parameter as string ?? "";
        var visible = string.Equals(kind, expected, StringComparison.OrdinalIgnoreCase)
            || (string.Equals(expected, "notimage", StringComparison.OrdinalIgnoreCase)
                && !string.Equals(kind, "Image", StringComparison.OrdinalIgnoreCase));
        return visible ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

internal static class NativeImports
{
    [System.Runtime.InteropServices.DllImport("imm32.dll")]
    internal static extern IntPtr ImmGetContext(IntPtr hWnd);

    [System.Runtime.InteropServices.DllImport("imm32.dll")]
    internal static extern int ImmGetCompositionString(IntPtr hImc, int index, IntPtr buffer, int bufferLength);

    [System.Runtime.InteropServices.DllImport("imm32.dll")]
    internal static extern bool ImmReleaseContext(IntPtr hWnd, IntPtr hImc);
}
