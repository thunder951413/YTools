using System.Runtime.InteropServices;
using YTools.Models;

namespace YTools.Services;

/// <summary>
/// Global hotkey registration via RegisterHotKey (the Windows equivalent of
/// the Carbon Event Hot Key API).
/// </summary>
public sealed class HotKeyManager : IDisposable
{
    private readonly MessageWindowService _messages;
    private readonly Dictionary<int, Action> _actions = [];
    private readonly HashSet<int> _registered = [];

    public HotKeyManager(MessageWindowService messages)
    {
        _messages = messages;
        _messages.HotKeyPressed += OnHotKeyPressed;
    }

    public bool Register(int id, HotKeyDefinition definition, Action action)
    {
        Unregister(id);
        if (!RegisterHotKey(
                _messages.Handle,
                id,
                (uint)definition.Modifiers | 0x4000 /* MOD_NOREPEAT */,
                (uint)definition.KeyCode))
        {
            return false;
        }

        _actions[id] = action;
        _registered.Add(id);
        return true;
    }

    public void Unregister(int id)
    {
        if (_registered.Remove(id))
        {
            UnregisterHotKey(_messages.Handle, id);
        }

        _actions.Remove(id);
    }

    public void RemoveAll()
    {
        foreach (var id in _registered.ToList())
        {
            UnregisterHotKey(_messages.Handle, id);
        }

        _registered.Clear();
        _actions.Clear();
    }

    public void Dispose()
    {
        _messages.HotKeyPressed -= OnHotKeyPressed;
        RemoveAll();
    }

    private void OnHotKeyPressed(int id)
    {
        if (_actions.TryGetValue(id, out var action))
        {
            action();
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
