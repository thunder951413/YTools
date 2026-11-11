using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using YTools.Core;
using YTools.Models;
using YTools.Services;

namespace YTools.UI;

/// <summary>
/// Small always-on-top window: type on top, the translation appears below once
/// typing pauses. The direction follows the configured language pair and can
/// be flipped for the current text.
/// </summary>
public partial class TranslatorWindow : Window
{
    private readonly AppPreferences _preferences;
    private readonly AITranslationService _service;
    private readonly DebouncedAction _debouncer = new();
    private readonly PropertyChangedEventHandler _preferenceChanged;
    private CancellationTokenSource? _request;
    private string _output = "";
    // The user flipped the direction for the current text.
    private TranslationLanguage? _targetOverride;
    private bool _replacingInput;

    public TranslatorWindow(AppPreferences preferences, AITranslationService? service = null)
    {
        _preferences = preferences;
        _service = service ?? AITranslationService.Shared;
        InitializeComponent();
        _preferenceChanged = (_, args) =>
        {
            if (args.PropertyName == nameof(AppPreferences.AITranslation)) { RefreshChrome(); }
        };
        _preferences.PropertyChanged += _preferenceChanged;
        Closed += (_, _) =>
        {
            _preferences.PropertyChanged -= _preferenceChanged;
            Cancel();
        };
        RefreshChrome();
    }

    public Action? OnOpenSettings { get; set; }

    /// <summary>Shown when "paste back" could not reach the previous window.</summary>
    public Action<string>? OnNotice { get; set; }

    private AITranslationSettings Settings => _preferences.AITranslation;

    /// <summary>Opens the window; non-empty text replaces the input and translates it.</summary>
    public void ShowTranslator(string text = "")
    {
        if (!string.IsNullOrEmpty(text)) { ReplaceInput(text); }
        Show();
        if (WindowState == WindowState.Minimized) { WindowState = WindowState.Normal; }
        Activate();
        InputBox.Focus();
        InputBox.CaretIndex = InputBox.Text.Length;
    }

    public void Toggle()
    {
        if (IsVisible && IsActive) { HideWindow(); }
        else { ShowTranslator(); }
    }

    public void HideWindow()
    {
        Cancel();
        Hide();
    }

    private void ReplaceInput(string text)
    {
        _targetOverride = null;
        _replacingInput = true;
        InputBox.Text = text.Length > TranslationQuery.MaximumCharacters ? text[..TranslationQuery.MaximumCharacters] : text;
        _replacingInput = false;
        TranslateNow();
    }

    private void Input_TextChanged(object sender, TextChangedEventArgs e)
    {
        RefreshChrome();
        if (_replacingInput) { return; }
        if (string.IsNullOrWhiteSpace(InputBox.Text))
        {
            Cancel();
            _targetOverride = null;
            SetOutput("", isError: false);
            return;
        }

        _debouncer.Schedule(TimeSpan.FromMilliseconds(Settings.LiveDelayMilliseconds), TranslateNow);
    }

    private async void TranslateNow()
    {
        _debouncer.Cancel();
        _request?.Cancel();
        var text = InputBox.Text;
        if (string.IsNullOrWhiteSpace(text)) { return; }
        var settings = Settings;
        var requestedTarget = _targetOverride;
        var cancellation = new CancellationTokenSource();
        _request = cancellation;
        SetBusy(true);
        try
        {
            var result = await _service.TranslateAsync(text, settings, requestedTarget, cancellation.Token);
            if (cancellation.IsCancellationRequested || InputBox.Text != text) { return; }
            SetOutput(result.Text, isError: false);
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
            return;
        }
        catch (Exception exception)
        {
            if (cancellation.IsCancellationRequested || InputBox.Text != text) { return; }
            SetOutput(exception is AITranslationException ? exception.Message : $"翻译失败：{exception.Message}", isError: true);
        }
        finally
        {
            if (_request == cancellation)
            {
                _request = null;
                SetBusy(false);
            }

            cancellation.Dispose();
        }
    }

    private void Cancel()
    {
        _debouncer.Cancel();
        _request?.Cancel();
        _request = null;
        SetBusy(false);
    }

    private void SetBusy(bool busy)
    {
        BusyText.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
    }

    private void SetOutput(string text, bool isError)
    {
        _output = isError ? "" : text;
        OutputBox.Text = isError ? "⚠ " + text : text;
        OutputBox.SetResourceReference(ForegroundProperty, isError ? "ErrorBrush" : "TextPrimaryBrush");
        CopyButton.IsEnabled = _output.Length > 0;
        PasteButton.IsEnabled = _output.Length > 0;
    }

    private void RefreshChrome()
    {
        var settings = Settings;
        var text = InputBox.Text;
        var destination = _targetOverride
            ?? (string.IsNullOrWhiteSpace(text) ? settings.SecondaryLanguage : settings.Target(text));
        var source = destination == settings.PrimaryLanguage ? settings.SecondaryLanguage : settings.PrimaryLanguage;
        DirectionText.Text = $"{source.Title()} → {destination.Title()}";
        SwapButton.IsEnabled = !string.IsNullOrWhiteSpace(text);
        DisabledNotice.Visibility = settings.Enabled ? Visibility.Collapsed : Visibility.Visible;
        HintText.Text = $"停顿 {settings.LiveDelayMilliseconds} ms 后自动翻译 · Esc 关闭";
    }

    private void Swap_Click(object sender, RoutedEventArgs e) => SwapDirection();

    private void SwapDirection()
    {
        if (string.IsNullOrWhiteSpace(InputBox.Text)) { return; }
        var settings = Settings;
        var current = _targetOverride ?? settings.Target(InputBox.Text);
        _targetOverride = current == settings.PrimaryLanguage ? settings.SecondaryLanguage : settings.PrimaryLanguage;
        RefreshChrome();
        TranslateNow();
    }

    private void Clear_Click(object sender, RoutedEventArgs e) => ClearAll();

    private void ClearAll()
    {
        Cancel();
        _targetOverride = null;
        InputBox.Clear();
        SetOutput("", isError: false);
        InputBox.Focus();
    }

    private void Copy_Click(object sender, RoutedEventArgs e) => CopyOutput();

    private bool CopyOutput()
    {
        if (_output.Length == 0) { return false; }
        try
        {
            Clipboard.SetText(_output);
            return true;
        }
        catch (Exception exception) when (exception is System.Runtime.InteropServices.COMException or System.Runtime.InteropServices.ExternalException)
        {
            // Another process may hold the clipboard open.
            OnNotice?.Invoke("无法写入剪贴板，请稍后重试。");
            return false;
        }
    }

    private async void Paste_Click(object sender, RoutedEventArgs e) => await PasteOutputAsync();

    private async Task PasteOutputAsync()
    {
        if (!CopyOutput()) { return; }
        HideWindow();
        if (!await PasteService.Shared.PasteIntoPreviousWindowAsync())
        {
            OnNotice?.Invoke("译文已复制；无法切换回之前的窗口自动粘贴，请手动按 Ctrl+V。");
        }
    }

    private void Settings_Click(object sender, RoutedEventArgs e)
    {
        HideWindow();
        OnOpenSettings?.Invoke();
    }

    private void Close_Click(object sender, RoutedEventArgs e) => HideWindow();

    private void OnHeaderMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left
            && e.ButtonState == MouseButtonState.Pressed
            && (e.OriginalSource is not DependencyObject source || !HasButtonAncestor(source)))
        {
            DragMove();
        }
    }

    private static bool HasButtonAncestor(DependencyObject? current)
    {
        while (current is not null)
        {
            if (current is ButtonBase)
            {
                return true;
            }

            current = current is Visual or System.Windows.Media.Media3D.Visual3D
                ? VisualTreeHelper.GetParent(current)
                : LogicalTreeHelper.GetParent(current);
        }

        return false;
    }

    private async void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.ImeProcessed || IsComposingIme())
        {
            return;
        }

        var modifiers = Keyboard.Modifiers;
        switch (e.Key)
        {
            case Key.Escape:
                e.Handled = true;
                HideWindow();
                break;
            case Key.Enter when modifiers == (ModifierKeys.Control | ModifierKeys.Shift):
                e.Handled = true;
                await PasteOutputAsync();
                break;
            case Key.Enter when modifiers == ModifierKeys.Control:
                e.Handled = true;
                CopyOutput();
                break;
            case Key.K when modifiers == ModifierKeys.Control:
                e.Handled = true;
                ClearAll();
                break;
            case Key.R when modifiers == ModifierKeys.Control:
                e.Handled = true;
                SwapDirection();
                break;
        }
    }

    private bool IsComposingIme()
    {
        var handle = new WindowInteropHelper(this).Handle;
        var context = ImmGetContext(handle);
        if (context == IntPtr.Zero)
        {
            return false;
        }

        try
        {
            return ImmGetCompositionString(context, GcsCompStr, IntPtr.Zero, 0) > 0;
        }
        finally
        {
            _ = ImmReleaseContext(handle, context);
        }
    }

    private const int GcsCompStr = 0x0008;

    [DllImport("imm32.dll")]
    private static extern IntPtr ImmGetContext(IntPtr hWnd);

    [DllImport("imm32.dll")]
    private static extern int ImmGetCompositionString(IntPtr hImc, int index, IntPtr buffer, int bufferLength);

    [DllImport("imm32.dll")]
    private static extern bool ImmReleaseContext(IntPtr hWnd, IntPtr hImc);
}
