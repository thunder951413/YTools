using System.Runtime.InteropServices;

namespace YTools.Services;

/// <summary>
/// Remembers the window that was in front before a YTools panel opened and
/// pastes into it later: re-activate it, wait until it owns the keyboard, then
/// send Ctrl+V with SendInput. Only fixed keystrokes are ever synthesized.
/// </summary>
public sealed class PasteService
{
    private const int InputKeyboard = 1;
    private const uint KeyEventKeyUp = 0x0002;
    private const ushort VkShift = 0x10;
    private const ushort VkControl = 0x11;
    private const ushort VkMenu = 0x12;
    private const ushort VkLeftWindows = 0x5B;
    private const ushort VkRightWindows = 0x5C;
    private const ushort VkV = 0x56;
    private const int SwRestore = 9;

    public static PasteService Shared { get; } = new();

    private IntPtr _previousWindow;

    private PasteService()
    {
    }

    /// <summary>
    /// Call before showing a YTools window. YTools' own windows are ignored so
    /// that switching from the launcher to the clipboard keeps the real target.
    /// </summary>
    public void RememberForegroundWindow()
    {
        var window = GetForegroundWindow();
        if (window == IntPtr.Zero || BelongsToThisProcess(window)) { return; }
        _previousWindow = window;
    }

    public bool HasPreviousWindow => _previousWindow != IntPtr.Zero && IsWindow(_previousWindow);

    /// <summary>
    /// Re-activates the remembered window and sends Ctrl+V. Returns false when
    /// there is no target, it could not be brought to the front, or Windows
    /// rejected the input (for example an elevated target window).
    /// </summary>
    public async Task<bool> PasteIntoPreviousWindowAsync()
    {
        var target = _previousWindow;
        if (target == IntPtr.Zero || !IsWindow(target)) { return false; }

        await Task.Delay(40);
        if (IsIconic(target)) { _ = ShowWindow(target, SwRestore); }
        BringToFront(target);
        // Send Ctrl+V only once the target owns the keyboard, otherwise the
        // keystroke lands in YTools or nowhere.
        for (var attempt = 0; attempt < 40 && GetForegroundWindow() != target; attempt++)
        {
            await Task.Delay(15);
            if (attempt == 10) { BringToFront(target); }
        }

        if (GetForegroundWindow() != target) { return false; }
        // Wait briefly for Shift/Alt/Win from the choosing shortcut to be released;
        // a held modifier would turn Ctrl+V into a different command.
        for (var attempt = 0; attempt < 20 && AnyModifierHeld(); attempt++) { await Task.Delay(15); }
        await Task.Delay(40);
        return SendCtrlV();
    }

    private static void BringToFront(IntPtr target)
    {
        if (SetForegroundWindow(target)) { return; }
        // The foreground lock only lets the foreground thread hand activation
        // over; attach to it briefly so the request is honoured.
        var foreground = GetForegroundWindow();
        var foregroundThread = GetWindowThreadProcessId(foreground, out _);
        var currentThread = GetCurrentThreadId();
        if (foregroundThread == 0 || foregroundThread == currentThread)
        {
            _ = SetForegroundWindow(target);
            return;
        }

        if (!AttachThreadInput(currentThread, foregroundThread, true)) { return; }
        try
        {
            _ = BringWindowToTop(target);
            _ = SetForegroundWindow(target);
        }
        finally
        {
            _ = AttachThreadInput(currentThread, foregroundThread, false);
        }
    }

    private static bool AnyModifierHeld()
    {
        return IsDown(VkShift) || IsDown(VkMenu) || IsDown(VkLeftWindows) || IsDown(VkRightWindows);
    }

    private static bool IsDown(ushort key) => (GetAsyncKeyState(key) & 0x8000) != 0;

    private static bool SendCtrlV()
    {
        // Ctrl may still be physically held after Ctrl+1…9; pressing it again
        // and releasing it afterwards leaves the keyboard state consistent.
        Input[] inputs =
        [
            Key(VkControl, keyUp: false),
            Key(VkV, keyUp: false),
            Key(VkV, keyUp: true),
            Key(VkControl, keyUp: true)
        ];
        return SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>()) == inputs.Length;
    }

    private static Input Key(ushort virtualKey, bool keyUp) => new()
    {
        Type = InputKeyboard,
        Union = new InputUnion
        {
            Keyboard = new KeyboardInput
            {
                VirtualKey = virtualKey,
                Flags = keyUp ? KeyEventKeyUp : 0
            }
        }
    };

    private static bool BelongsToThisProcess(IntPtr window)
    {
        _ = GetWindowThreadProcessId(window, out var processId);
        return processId == (uint)Environment.ProcessId;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public int Type;
        public InputUnion Union;
    }

    // The union must be as large as MOUSEINPUT so Marshal.SizeOf matches the
    // native INPUT size; SendInput rejects a mismatched cbSize.
    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MouseInput Mouse;
        [FieldOffset(0)] public KeyboardInput Keyboard;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput
    {
        public int X;
        public int Y;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput
    {
        public ushort VirtualKey;
        public ushort ScanCode;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, Input[] pInputs, int cbSize);
}
