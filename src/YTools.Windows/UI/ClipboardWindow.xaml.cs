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
    private ClipboardHistoryManager? _manager;
    private SnippetManager? _snippets;

    public ClipboardWindow()
    {
        InitializeComponent();
    }

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
        Show();
        Activate();
        SearchBox.Focus();
    }

    public void HidePanel()
    {
        Hide();
        Hidden?.Invoke();
    }

    private void OnManagerPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(ClipboardHistoryManager.FilteredItems))
        {
            ClipboardList.ScrollIntoView(_manager?.FilteredItems.FirstOrDefault());
        }
    }

    private void OnDeactivated(object sender, EventArgs e)
    {
        if (IsVisible)
        {
            HidePanel();
        }
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (_manager is null)
        {
            return;
        }

        if ((e.Key is Key.Enter or Key.Up or Key.Down or Key.Left or Key.Right or Key.Back)
            && IsComposingIme())
        {
            return;
        }

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
                if (_manager.CopySelected())
                {
                    HidePanel();
                }

                break;
            case PanelCommandKind.Escape:
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
                if (_manager.SelectedText is { } text && _snippets?.Save(text) == true)
                {
                    System.Media.SystemSounds.Asterisk.Play();
                }

                break;
            case PanelCommandKind.OpenSettings:
                HidePanel();
                OnOpenSettings?.Invoke();
                break;
        }
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
        _manager?.ClearRecent(30);
    }

    private void ClearAll_Click(object sender, RoutedEventArgs e)
    {
        if (_manager is null)
        {
            return;
        }

        var confirmation = MessageBox.Show(
            this,
            "永久清空全部剪贴板历史？加密密文将被删除，此操作无法撤销。",
            "清空剪贴板历史",
            MessageBoxButton.OKCancel,
            MessageBoxImage.Warning);
        if (confirmation == MessageBoxResult.OK)
        {
            _manager.Clear();
        }
    }

    private void OnContextMenuOpening(object sender, ContextMenuEventArgs e)
    {
        if (ClipboardList.SelectedItem is not ClipboardHistoryItem item)
        {
            e.Handled = true;
            return;
        }

        var menu = new ContextMenu();
        var copy = new MenuItem { Header = "复制" };
        copy.Click += (_, _) => _manager?.Copy(item);
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
            var decoder = new PngBitmapDecoder(
                stream,
                BitmapCreateOptions.PreservePixelFormat,
                BitmapCacheOption.OnLoad);
            return decoder.Frames[0];
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
