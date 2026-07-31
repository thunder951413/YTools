using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace YTools.Services;

/// <summary>
/// Hidden Win32 message window on the UI thread. Receives global hotkey and
/// clipboard-update notifications without any visible window.
/// </summary>
public sealed class MessageWindowService : IDisposable
{
    private const int WmHotKey = 0x0312;
    private const int WmClipboardUpdate = 0x031D;

    private readonly HwndSource _source;

    public MessageWindowService()
    {
        var parameters = new HwndSourceParameters("YTools.MessageWindow")
        {
            Width = 0,
            Height = 0,
            WindowStyle = 0,
            ExtendedWindowStyle = 0,
            PositionX = 0,
            PositionY = 0
        };
        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);
        AddClipboardFormatListener(_source.Handle);
    }

    public event Action<int>? HotKeyPressed;

    public event Action? ClipboardUpdated;

    public IntPtr Handle => _source.Handle;

    public void Dispose()
    {
        RemoveClipboardFormatListener(_source.Handle);
        _source.RemoveHook(WndProc);
        _source.Dispose();
    }

    private IntPtr WndProc(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        switch (message)
        {
            case WmHotKey:
                HotKeyPressed?.Invoke(wParam.ToInt32());
                handled = true;
                break;
            case WmClipboardUpdate:
                ClipboardUpdated?.Invoke();
                handled = true;
                break;
        }

        return IntPtr.Zero;
    }

    [DllImport("user32.dll")]
    private static extern bool AddClipboardFormatListener(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern bool RemoveClipboardFormatListener(IntPtr hwnd);

    [DllImport("user32.dll")]
    internal static extern uint GetClipboardSequenceNumber();
}
