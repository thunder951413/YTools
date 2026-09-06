using YTools.Models;
using YTools.ModuleKit;

namespace YTools.Services;

public sealed class ActionMenuController
{
    private readonly ActionRegistry _registry = new();
    private List<LauncherAction> _actions = [];
    private LauncherResult? _subject;
    private string? _titleOverride;
    private int _selectedIndex;

    public IReadOnlyList<LauncherAction> Actions => _actions;

    public LauncherResult? Subject => _subject;

    public string Title => _titleOverride ?? _subject?.Title ?? "";

    public int SelectedIndex
    {
        get => _selectedIndex;
        set => _selectedIndex = value;
    }

    public bool IsShowing => _actions.Count > 0;

    public LauncherAction? SelectedAction =>
        _actions.Count > _selectedIndex && _selectedIndex >= 0 ? _actions[_selectedIndex] : null;

    public bool Show(LauncherResult result)
    {
        var available = _registry.ActionsFor(result);
        if (available.Count == 0)
        {
            return false;
        }

        _actions = available.ToList();
        _subject = result;
        _titleOverride = null;
        _selectedIndex = 0;
        return true;
    }

    public bool ShowForBufferedPaths(IReadOnlyList<string> paths)
    {
        var available = _registry.ActionsForBufferedPaths(paths);
        if (available.Count == 0)
        {
            return false;
        }

        _actions = available.ToList();
        _subject = null;
        _titleOverride = $"{paths.Count} 个缓冲项目";
        _selectedIndex = 0;
        return true;
    }

    public void MoveSelection(int offset)
    {
        if (_actions.Count == 0)
        {
            return;
        }

        _selectedIndex = (_selectedIndex + offset + _actions.Count) % _actions.Count;
    }

    public void Dismiss()
    {
        _actions = [];
        _subject = null;
        _titleOverride = null;
        _selectedIndex = 0;
    }
}
