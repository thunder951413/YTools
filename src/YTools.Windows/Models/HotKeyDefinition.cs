using System.Globalization;
using System.Windows.Input;

namespace YTools.Models;

[Flags]
public enum HotKeyModifiers : uint
{
    None = 0,
    Alt = 0x0001,
    Control = 0x0002,
    Shift = 0x0004,
    Windows = 0x0008
}

public readonly record struct HotKeyDefinition(int KeyCode, HotKeyModifiers Modifiers)
{
    public static readonly HotKeyDefinition LauncherDefault = new(0x20, HotKeyModifiers.Alt);

    public static readonly HotKeyDefinition ClipboardDefault =
        new(0x43, HotKeyModifiers.Alt | HotKeyModifiers.Control);

    public static readonly HotKeyDefinition LauncherFallback =
        new(0x20, HotKeyModifiers.Control | HotKeyModifiers.Alt);

    public static readonly HotKeyDefinition ClipboardFallback =
        new(0x43, HotKeyModifiers.Control | HotKeyModifiers.Shift);

    public string DisplayString
    {
        get
        {
            var parts = new List<string>();
            if (Modifiers.HasFlag(HotKeyModifiers.Control))
            {
                parts.Add("Ctrl");
            }

            if (Modifiers.HasFlag(HotKeyModifiers.Alt))
            {
                parts.Add("Alt");
            }

            if (Modifiers.HasFlag(HotKeyModifiers.Shift))
            {
                parts.Add("Shift");
            }

            if (Modifiers.HasFlag(HotKeyModifiers.Windows))
            {
                parts.Add("Win");
            }

            parts.Add(KeyName(KeyCode));
            return string.Join("+", parts);
        }
    }

    public static string KeyName(int keyCode)
    {
        var key = KeyInterop.KeyFromVirtualKey(keyCode);
        return key switch
        {
            Key.Space => "Space",
            Key.Enter => "Enter",
            Key.Tab => "Tab",
            Key.Escape => "Esc",
            Key.Back => "Backspace",
            Key.Delete => "Delete",
            Key.Up => "↑",
            Key.Down => "↓",
            Key.Left => "←",
            Key.Right => "→",
            Key.Home => "Home",
            Key.End => "End",
            Key.PageUp => "PageUp",
            Key.PageDown => "PageDown",
            _ => key >= Key.D0 && key <= Key.D9
                ? ((char)('0' + (key - Key.D0))).ToString(CultureInfo.InvariantCulture)
                : key.ToString()
        };
    }
}
