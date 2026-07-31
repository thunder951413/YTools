using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using YTools.Core;
using YTools.Models;
using YTools.Services;

namespace YTools.UI;

public partial class LauncherWindow : Window
{
    private readonly PanelCommandRouter _router = new();
    private readonly DebouncedAction _positionSaveDebouncer = new();
    private DispatcherTimer? _shiftPreviewTimer;
    private LauncherModel? _model;
    private AppPreferences? _preferences;
    private bool _isApplyingPosition;

    public LauncherWindow()
    {
        InitializeComponent();
        SourceInitialized += (_, _) => PositionPanel();
        LocationChanged += OnLocationChanged;
        PreviewKeyUp += OnPreviewKeyUp;
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
        Hide();
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
                AdjustPanelSize();
                UpdateEmptyState();
                UpdatePreview();
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
        if (e.ChangedButton == MouseButton.Left && e.ClickCount == 1)
        {
            DragMove();
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
            var screen = System.Windows.Forms.Screen.FromPoint(
                new System.Drawing.Point((int)(left + Width / 2), (int)(top + Height / 2)));
            var area = screen.WorkingArea;
            _preferences.SavePanelPosition(
                left,
                top,
                area.X,
                area.Y,
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

        double contentHeight;
        if (_model.IsSearchPending)
        {
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

        var width = _preferences.PanelWidth;
        var cornerRadius = _preferences.PanelCornerRadius;
        PanelBorder.CornerRadius = new CornerRadius(cornerRadius);
        SearchBox.FontSize = DesignTokens.SearchFontSizeFor(style);
        HeaderBorder.MinHeight = headerHeight;

        if (Math.Abs(Width - width) > 0.5)
        {
            Width = width;
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
                BeginAnimation(HeightProperty, animation);
            }
            else
            {
                BeginAnimation(HeightProperty, null);
                Height = contentHeight;
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
            PreviewColumn.Width = new GridLength(280);
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

            var area = screen.WorkingArea;
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
                    x = resolved.ResolvedLeft(area.X, area.Width);
                    y = resolved.ResolvedTop(area.Y, area.Height);
                }
                else
                {
                    x = area.X + (area.Width - Width) / 2;
                    y = _preferences.PanelPosition == PanelPosition.Upper
                        ? area.Y + Math.Max(0, area.Height - Height - 110)
                        : area.Y + (area.Height - Height) / 2;
                }
            }
            else if (savedTopLeft is { Length: 2 } saved)
            {
                x = saved[0];
                y = saved[1];
            }
            else
            {
                x = area.X + (area.Width - Width) / 2;
                y = _preferences.PanelPosition == PanelPosition.Upper
                    ? area.Y + Math.Max(0, area.Height - Height - 110)
                    : area.Y + (area.Height - Height) / 2;
            }

            x = Math.Clamp(x, area.X, Math.Max(area.X, area.Right - Width));
            y = Math.Clamp(y, area.Y, Math.Max(area.Y, area.Bottom - Height));
            Left = x;
            Top = y;
        }
        finally
        {
            _isApplyingPosition = false;
        }
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
