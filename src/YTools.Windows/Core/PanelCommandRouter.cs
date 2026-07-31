namespace YTools.Core;

public enum PanelInputMode
{
    Launcher,
    Clipboard
}

[Flags]
public enum PanelKeyModifiers : byte
{
    None = 0,
    Command = 1 << 0,
    Option = 1 << 1,
    Control = 1 << 2,
    Shift = 1 << 3
}

public readonly record struct PanelKeyEvent(int KeyCode, PanelKeyModifiers Modifiers);

public enum PanelCommandKind
{
    ActivateSelected,
    ActivateResult,
    AddSelectedToBuffer,
    RemoveLastBufferedItem,
    ShowFileBufferActions,
    ClearFileBuffer,
    Escape,
    MoveSelection,
    ShowActions,
    NavigateBack,
    DeleteClipboardItem,
    SaveClipboardAsSnippet,
    TogglePreview,
    ShowLargeType,
    RevealSelected,
    OpenSettings
}

public readonly record struct PanelCommand(PanelCommandKind Kind, int Payload = 0);

/// <summary>
/// Key-table port using Win32 virtual-key codes, so the router stays testable
/// without a live window. Command maps to Ctrl, Option maps to Alt.
/// </summary>
public sealed class PanelCommandRouter
{
    private const int VkReturn = 0x0D;
    private const int VkLeft = 0x25;
    private const int VkRight = 0x27;
    private const int VkUp = 0x26;
    private const int VkDown = 0x28;
    private const int VkBack = 0x08;
    private const int VkEscape = 0x1B;
    private const int VkD = 0x44;
    private const int VkS = 0x53;
    private const int VkY = 0x59;
    private const int VkL = 0x4C;
    private const int VkOemComma = 0xBC;

    private static readonly int[] NumberRow =
    {
        0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39
    };

    public PanelCommand? Command(PanelKeyEvent keyEvent, PanelInputMode mode)
    {
        if (keyEvent.Modifiers.HasFlag(PanelKeyModifiers.Command)
            && mode == PanelInputMode.Launcher
            && ResultIndexForNumberKeyCode(keyEvent.KeyCode) is { } index)
        {
            return new PanelCommand(PanelCommandKind.ActivateResult, index);
        }

        return (keyEvent.KeyCode, mode) switch
        {
            (VkReturn, _) when keyEvent.Modifiers == PanelKeyModifiers.None =>
                new PanelCommand(PanelCommandKind.ActivateSelected),
            (VkUp, PanelInputMode.Launcher) when keyEvent.Modifiers.HasFlag(PanelKeyModifiers.Option) =>
                new PanelCommand(PanelCommandKind.AddSelectedToBuffer, 0),
            (VkDown, PanelInputMode.Launcher) when keyEvent.Modifiers.HasFlag(PanelKeyModifiers.Option) =>
                new PanelCommand(PanelCommandKind.AddSelectedToBuffer, 1),
            (VkLeft, PanelInputMode.Launcher) when keyEvent.Modifiers.HasFlag(PanelKeyModifiers.Option) =>
                new PanelCommand(PanelCommandKind.RemoveLastBufferedItem),
            (VkRight, PanelInputMode.Launcher) when keyEvent.Modifiers.HasFlag(PanelKeyModifiers.Option) =>
                new PanelCommand(PanelCommandKind.ShowFileBufferActions),
            (VkBack, PanelInputMode.Launcher) when keyEvent.Modifiers.HasFlag(PanelKeyModifiers.Option) =>
                new PanelCommand(PanelCommandKind.ClearFileBuffer),
            (VkEscape, _) => new PanelCommand(PanelCommandKind.Escape),
            (VkDown, _) => new PanelCommand(PanelCommandKind.MoveSelection, 1),
            (VkUp, _) => new PanelCommand(PanelCommandKind.MoveSelection, -1),
            (VkRight, PanelInputMode.Launcher) => new PanelCommand(PanelCommandKind.ShowActions),
            (VkLeft, PanelInputMode.Launcher) => new PanelCommand(PanelCommandKind.NavigateBack),
            (VkD, PanelInputMode.Clipboard) when keyEvent.Modifiers.HasFlag(PanelKeyModifiers.Command) =>
                new PanelCommand(PanelCommandKind.DeleteClipboardItem),
            (VkS, PanelInputMode.Clipboard) when keyEvent.Modifiers.HasFlag(PanelKeyModifiers.Command) =>
                new PanelCommand(PanelCommandKind.SaveClipboardAsSnippet),
            (VkY, PanelInputMode.Launcher) when keyEvent.Modifiers.HasFlag(PanelKeyModifiers.Command) =>
                new PanelCommand(PanelCommandKind.TogglePreview),
            (VkL, PanelInputMode.Launcher) when keyEvent.Modifiers.HasFlag(PanelKeyModifiers.Command) =>
                new PanelCommand(PanelCommandKind.ShowLargeType),
            (VkReturn, PanelInputMode.Launcher) when keyEvent.Modifiers.HasFlag(PanelKeyModifiers.Command) =>
                new PanelCommand(PanelCommandKind.RevealSelected),
            (VkOemComma, _) when keyEvent.Modifiers.HasFlag(PanelKeyModifiers.Command) =>
                new PanelCommand(PanelCommandKind.OpenSettings),
            _ => null
        };
    }

    private static int? ResultIndexForNumberKeyCode(int keyCode)
    {
        var index = Array.IndexOf(NumberRow, keyCode);
        return index >= 0 ? index : null;
    }
}
