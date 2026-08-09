using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using YTools.Core;
using YTools.Models;
using YTools.Services;

namespace YTools.UI;

public partial class LauncherWindow : Window
{
    private const double PreviewWidth = 280;

    public static readonly DependencyProperty ResultRowHeightProperty = DependencyProperty.Register(
        nameof(ResultRowHeight),
        typeof(double),
        typeof(LauncherWindow),
        new PropertyMetadata(DesignTokens.ComfortableRowHeight));

    private readonly PanelCommandRouter _router = new();
    private readonly DebouncedAction _positionSaveDebouncer = new();
    private DispatcherTimer? _shiftPreviewTimer;
    private LauncherModel? _model;
    private AppPreferences? _preferences;
    private bool _isApplyingPosition;

    public double ResultRowHeight
    {
        get => (double)GetValue(ResultRowHeightProperty);
        private set => SetValue(ResultRowHeightProperty, value);
    }

    public LauncherWindow()
    {
        InitializeComponent();
        SourceInitialized += (_, _) => PositionPanel();
        LocationChanged += OnLocationChanged;
        PreviewKeyUp += OnPreviewKeyUp;
        IconService.IconAvailable += OnIconAvailable;
    }

    public void Attach(LauncherModel model, AppPreferences preferences)
    {
        _model = model;
        _preferences = preferences;
        DataContext = model;
        model.PropertyChanged += OnModelPropertyChanged;
        preferences.PropertyChanged += OnPreferencePropertyChanged;
        UpdateHotKeyError(preferences.HotKeyError);
        AdjustPanelSize();
        UpdateFooter();
    }

    public void ShowLauncher()
    {
        if (_model is null)
        {
            return;
        }

        AdjustPanelSize();
        PositionPanel();
        Show();
        Activate();
        SearchBox.Focus();
        SearchBox.SelectAll();
        UpdatePreview();
    }

    public void HidePanel()
    {
        _shiftPreviewTimer?.Stop();
        _model?.EndMomentaryPreview();
        _model?.PersistLastQuery();
        Hide();
    }

    private void OnIconAvailable(object? sender, EventArgs e)
    {
        if (!IsVisible)
        {
            return;
        }

        // Converters return a glyph immediately and request this refresh only after
        // the shell icon has been decoded on a worker thread.
        ResultsList.Items.Refresh();
        ActionsList.Items.Refresh();
    }

    private void OnModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(LauncherModel.Results):
            case nameof(LauncherModel.IsSearchPending):
            case nameof(LauncherModel.Actions):
            case nameof(LauncherModel.IsShowingActions):
            case nameof(LauncherModel.Query):
            case nameof(LauncherModel.FileBuffer):
            case nameof(LauncherModel.ShowsPreview):
            case nameof(LauncherModel.DisplayedPreviewPath):
            case nameof(LauncherModel.VisibleItemCount):
            case nameof(LauncherModel.FileSearchBackendDescription):
                AdjustPanelSize();
                UpdateEmptyState();
                UpdatePreview();
                UpdateFooter();
                if (e.PropertyName == nameof(LauncherModel.Results) && _model is { } model)
                {
                    IconService.Preload(model.Results.Select(result => result.Icon));
                }
                break;
        }
    }

    private void OnPreferencePropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(AppPreferences.CompactResults):
            case nameof(AppPreferences.PanelWidth):
            case nameof(AppPreferences.LauncherAppearanceStyle):
            case nameof(AppPreferences.PanelCornerRadius):
                AdjustPanelSize();
                UpdateFooter();
                break;
            case nameof(AppPreferences.HotKeyError):
                if (_preferences is { } preferences)
                {
                    UpdateHotKeyError(preferences.HotKeyError);
                }

                break;
        }
    }

    private void UpdateHotKeyError(string? message)
    {
        if (string.IsNullOrEmpty(message))
        {
            HotKeyErrorText.Text = "";
            HotKeyErrorText.Visibility = Visibility.Collapsed;
        }
        else
        {
            HotKeyErrorText.Text = message;
            HotKeyErrorText.Visibility = Visibility.Visible;
        }
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (_model is null)
        {
            return;
        }

        if (e.Key is Key.LeftShift or Key.RightShift)
        {
            _shiftPreviewTimer?.Stop();
            _shiftPreviewTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromMilliseconds(250)
            };
            _shiftPreviewTimer.Tick += (_, _) =>
            {
                _shiftPreviewTimer?.Stop();
                _model.BeginMomentaryPreview();
            };
            _shiftPreviewTimer.Start();
            return;
        }

        if (ShouldIgnoreWhileComposing(e.Key))
        {
            return;
        }

        var keyCode = KeyInterop.VirtualKeyFromKey(e.Key);
        var modifiers = PanelModifiers(Keyboard.Modifiers);
        var command = _router.Command(
            new PanelKeyEvent(keyCode, modifiers),
            PanelInputMode.Launcher);
        if (command is { } routed)
        {
            e.Handled = Execute(routed);
        }
    }

    private void OnPreviewKeyUp(object sender, KeyEventArgs e)
    {
        if (e.Key is Key.LeftShift or Key.RightShift)
        {
            _shiftPreviewTimer?.Stop();
            _model?.EndMomentaryPreview();
        }
    }

    private bool Execute(PanelCommand command)
    {
        if (_model is null)
        {
            return false;
        }

        switch (command.Kind)
        {
            case PanelCommandKind.ActivateSelected:
                if (!_model.ActivateSelected())
                {
                    return false;
                }

                HidePanel();
                return true;
            case PanelCommandKind.ActivateResult:
                if (!_model.ActivateResult(command.Payload))
                {
                    return false;
                }

                HidePanel();
                return true;
            case PanelCommandKind.AddSelectedToBuffer:
                return _model.AddSelectedToBuffer(command.Payload != 0);
            case PanelCommandKind.RemoveLastBufferedItem:
                return _model.RemoveLastBufferedItem();
            case PanelCommandKind.ShowFileBufferActions:
                return _model.ShowFileBufferActions();
            case PanelCommandKind.ClearFileBuffer:
                _model.ClearFileBuffer();
                return true;
            case PanelCommandKind.Escape:
                if (_model.DismissSecondaryView())
                {
                    return true;
                }

                if (_model.ClearQuery())
                {
                    return true;
                }

                HidePanel();
                return true;
            case PanelCommandKind.MoveSelection:
                _model.MoveSelection(command.Payload);
                return true;
            case PanelCommandKind.ShowActions:
                return _model.ShowActionsForSelected();
            case PanelCommandKind.NavigateBack:
                return _model.DismissSecondaryView() || _model.NavigateToParent();
            case PanelCommandKind.TogglePreview:
                _model.TogglePreview();
                return true;
            case PanelCommandKind.ShowLargeType:
                if (_model.SelectedLargeTypeText is not { } text)
                {
                    return false;
                }

                HidePanel();
                OnShowLargeType?.Invoke(text);
                return true;
            case PanelCommandKind.RevealSelected:
                if (!_model.RevealSelected())
                {
                    return false;
                }

                HidePanel();
                return true;
            case PanelCommandKind.OpenSettings:
                HidePanel();
                OnOpenSettings?.Invoke();
                return true;
            default:
                return false;
        }
    }

    public Action? OnOpenSettings { get; set; }

    public Action<string>? OnShowLargeType { get; set; }

    private void OnDeactivated(object sender, EventArgs e)
    {
        if (!IsVisible)
        {
            return;
        }

        HidePanel();
    }

    private void OnHeaderMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left
            && e.ClickCount == 1
            && e.OriginalSource is DependencyObject source
            && FindAncestor<TextBox>(source) is null
            && FindAncestor<Button>(source) is null)
        {
            DragMove();
        }
    }

    private void OnClearSearchClick(object sender, RoutedEventArgs e)
    {
        _model?.ClearQuery();
        SearchBox.Focus();
    }

    private void OnResultsDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left
            && e.OriginalSource is DependencyObject source
            && FindAncestor<ListBoxItem>(source) is not null
            && _model?.ActivateSelected() == true)
        {
            HidePanel();
        }
    }

    private void OnActionsDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left
            && e.OriginalSource is DependencyObject source
            && FindAncestor<ListBoxItem>(source) is not null
            && _model?.ActivateSelected() == true)
        {
            HidePanel();
        }
    }

    private void OnLocationChanged(object? sender, EventArgs e)
    {
        if (_preferences is null || _model is null || _isApplyingPosition || !IsVisible)
        {
            return;
        }

        _positionSaveDebouncer.Schedule(TimeSpan.FromMilliseconds(250), () =>
        {
            var left = Left;
            var top = Top;
            var center = PointToScreen(new Point(Width / 2, Height / 2));
            var screen = System.Windows.Forms.Screen.FromPoint(
                new System.Drawing.Point((int)center.X, (int)center.Y));
            var area = WorkingAreaInDips(screen);
            _preferences.SavePanelPosition(
                left,
                top,
                area.Left,
                area.Top,
                area.Width,
                area.Height,
                screen.DeviceName);
        });
    }

    private void AdjustPanelSize()
    {
        if (_model is null || _preferences is null || !IsInitialized)
        {
            return;
        }

        var style = _preferences.LauncherAppearanceStyle;
        var headerHeight = DesignTokens.HeaderHeightFor(style);
        var rowHeight = _preferences.CompactResults
            ? DesignTokens.CompactRowHeight
            : DesignTokens.ComfortableRowHeight;
        ResultRowHeight = rowHeight;

        double contentHeight;
        if (_model.IsSearchPending)
        {
            // Match macOS: while the idle timer/search is pending, keep only the
            // input row visible. The result body is published and expanded once
            // for the final query instead of flashing stale intermediate results.
            contentHeight = headerHeight;
        }
        else if (string.IsNullOrWhiteSpace(_model.Query)
                 && DesignTokens.CollapsesWhenIdle(style)
                 && !_model.IsShowingActions)
        {
            contentHeight = headerHeight;
        }
        else
        {
            var count = _model.VisibleItemCount;
            var bodyHeight = count == 0
                ? DesignTokens.EmptyBodyHeightFor(style)
                : Math.Min(count, 6) * rowHeight;
            var footerHeight = DesignTokens.ShowsFooter(style) ? DesignTokens.FooterHeight : 0;
            contentHeight = Math.Min(
                DesignTokens.PanelMaximumHeight,
                Math.Max(headerHeight + bodyHeight + footerHeight, DesignTokens.PanelMinimumHeight));
        }

        var width = _preferences.PanelWidth + (_model.ShowsPreview && _model.SelectedFilePath is not null ? PreviewWidth : 0);
        var cornerRadius = _preferences.PanelCornerRadius;
        PanelBorder.CornerRadius = new CornerRadius(cornerRadius);
        SearchBox.FontSize = DesignTokens.SearchFontSizeFor(style);
        HeaderBorder.MinHeight = headerHeight;

        if (Math.Abs(Width - width) > 0.5)
        {
            Width = width;
            ClampPanelToWorkingArea();
        }

        if (Math.Abs(Height - contentHeight) > 0.5)
        {
            var duration = _preferences.ResultExpansionDuration;
            if (duration > 0 && IsVisible)
            {
                var animation = new DoubleAnimation
                {
                    To = contentHeight,
                    Duration = TimeSpan.FromSeconds(duration),
                    EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
                };
                animation.Completed += (_, _) => ClampPanelToWorkingArea();
                BeginAnimation(HeightProperty, animation);
            }
            else
            {
                BeginAnimation(HeightProperty, null);
                Height = contentHeight;
                ClampPanelToWorkingArea();
            }
        }
    }

    private void UpdateFooter()
    {
        if (_preferences is null)
        {
            return;
        }

        FooterBar.Visibility = DesignTokens.ShowsFooter(_preferences.LauncherAppearanceStyle)
            ? Visibility.Visible
            : Visibility.Collapsed;
        BackendStatusText.Text = _model?.FileSearchBackendDescription ?? "";
        BackendStatusText.ToolTip = "Everything 需要与 YTools 使用相同权限级别；若以管理员运行，请在 Everything 设置中关闭“以管理员运行”或安装 Everything Service。";
    }

    private void UpdateEmptyState()
    {
        if (_model is null)
        {
            return;
        }

        EmptyState.Visibility = !_model.IsSearchPending
            && _model.Results.Count == 0
            && !_model.IsShowingActions
            && !string.IsNullOrWhiteSpace(_model.Query)
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void UpdatePreview()
    {
        if (_model is null)
        {
            return;
        }

        var showPreview = _model.ShowsPreview && _model.SelectedFilePath is not null;
        if (showPreview)
        {
            PreviewColumn.Width = new GridLength(PreviewWidth);
            PreviewPane.Visibility = Visibility.Visible;
            PreviewPane.ShowPath(_model.DisplayedPreviewPath ?? _model.SelectedFilePath);
        }
        else
        {
            PreviewColumn.Width = new GridLength(0);
            PreviewPane.Visibility = Visibility.Collapsed;
            PreviewPane.Clear();
        }
    }

    private void PositionPanel()
    {
        if (_preferences is null)
        {
            return;
        }

        _isApplyingPosition = true;
        try
        {
            var screen = _preferences.ScreenPreference switch
            {
                ScreenPreference.Mouse => System.Windows.Forms.Screen.FromPoint(
                    System.Windows.Forms.Cursor.Position),
                _ => System.Windows.Forms.Screen.PrimaryScreen
            } ?? System.Windows.Forms.Screen.PrimaryScreen;
            if (screen is null)
            {
                return;
            }

            var area = WorkingAreaInDips(screen);
            var savedPlacement = _preferences.SavedPanelPlacement;
            var savedTopLeft = _preferences.SavedPanelTopLeft;

            double x;
            double y;
            if (savedPlacement is { } placement)
            {
                var relative = Core.RelativePanelPlacement.Create(
                    placement.HorizontalFraction,
                    placement.TopFraction,
                    placement.SourceVisibleWidth,
                    placement.SourceVisibleHeight);
                if (relative is { } resolved)
                {
                    x = resolved.ResolvedLeft(area.Left, area.Width);
                    y = resolved.ResolvedTop(area.Top, area.Height);
                }
                else
                {
                    x = area.Left + (area.Width - Width) / 2;
                    y = _preferences.PanelPosition == PanelPosition.Upper
                        ? area.Top + Math.Max(24, area.Height * 0.18)
                        : area.Top + (area.Height - Height) / 2;
                }
            }
            else if (savedTopLeft is { Length: 2 } saved)
            {
                x = saved[0];
                y = saved[1];
            }
            else
            {
                x = area.Left + (area.Width - Width) / 2;
                y = _preferences.PanelPosition == PanelPosition.Upper
                    ? area.Top + Math.Max(24, area.Height * 0.18)
                    : area.Top + (area.Height - Height) / 2;
            }

            x = Math.Clamp(x, area.Left, Math.Max(area.Left, area.Right - Width));
            y = Math.Clamp(y, area.Top, Math.Max(area.Top, area.Bottom - Height));
            Left = x;
            Top = y;
        }
        finally
        {
            _isApplyingPosition = false;
        }
    }

    private void ClampPanelToWorkingArea()
    {
        if (!IsVisible || _isApplyingPosition)
        {
            return;
        }

        var center = PointToScreen(new Point(Width / 2, Height / 2));
        var screen = System.Windows.Forms.Screen.FromPoint(
            new System.Drawing.Point((int)center.X, (int)center.Y));
        var area = WorkingAreaInDips(screen);
        _isApplyingPosition = true;
        try
        {
            Left = Math.Clamp(Left, area.Left, Math.Max(area.Left, area.Right - Width));
            Top = Math.Clamp(Top, area.Top, Math.Max(area.Top, area.Bottom - Height));
        }
        finally
        {
            _isApplyingPosition = false;
        }
    }

    private Rect WorkingAreaInDips(System.Windows.Forms.Screen screen)
    {
        var area = screen.WorkingArea;
        var transform = PresentationSource.FromVisual(this)?.CompositionTarget?.TransformFromDevice
            ?? Matrix.Identity;
        var topLeft = transform.Transform(new Point(area.Left, area.Top));
        var bottomRight = transform.Transform(new Point(area.Right, area.Bottom));
        return new Rect(topLeft, bottomRight);
    }

    private static T? FindAncestor<T>(DependencyObject source) where T : DependencyObject
    {
        var current = source;
        while (current is not null)
        {
            if (current is T match)
            {
                return match;
            }

            current = VisualTreeHelper.GetParent(current);
        }

        return null;
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

    private bool ShouldIgnoreWhileComposing(Key key)
    {
        if (key is not (Key.Enter or Key.Up or Key.Down or Key.Left or Key.Right or Key.Back))
        {
            return false;
        }

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
