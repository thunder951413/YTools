using System.IO;

namespace YTools.Models;

public sealed record ClipboardHistoryItem(
    Guid Id,
    ClipboardItemKind Kind,
    IReadOnlyList<string> Payload,
    DateTimeOffset CreatedAt,
    string? SourceApplication,
    byte[]? BinaryData = null,
    string? ContentHash = null,
    bool IsPinned = false,
    DateTimeOffset? UpdatedAt = null,
    int CopyCount = 1)
{
    public DateTimeOffset EffectiveUpdatedAt => UpdatedAt ?? CreatedAt;

    public string DisplayText => Kind switch
    {
        ClipboardItemKind.Text => Payload.FirstOrDefault() ?? "",
        ClipboardItemKind.Files => string.Join(", ", Payload.Select(path => Path.GetFileName(path))),
        ClipboardItemKind.Image => Payload.FirstOrDefault() ?? "图片",
        _ => ""
    };

    public bool HasSameContent(ClipboardHistoryItem other)
    {
        if (ContentHash is not null && other.ContentHash is not null)
        {
            return ContentHash == other.ContentHash;
        }

        return Kind == other.Kind && Payload.SequenceEqual(other.Payload) && (BinaryData ?? []).SequenceEqual(other.BinaryData ?? []);
    }
}

public enum ClipboardItemKind
{
    Text,
    Files,
    Image
}

public sealed record SnippetItem(
    Guid Id,
    string Title,
    string Keyword,
    string Content,
    string Collection,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public sealed record RecentDocumentItem(Guid Id, string Path, DateTimeOffset LastOpenedAt);

public enum LauncherActionKind
{
    Perform,
    CopyPath,
    CopyText,
    LargeType,
    SaveSnippet,
    Preview,
    OpenWith,
    CopyFile,
    MoveFile,
    Trash,
    OpenMany,
    RevealMany,
    CopyPaths
}

public sealed record LauncherAction(
    string Id,
    string Title,
    string Subtitle,
    string SystemIcon,
    LauncherActionKind Kind,
    object? Payload);

public sealed class FileBufferStore
{
    private readonly List<string> _paths = [];

    public IReadOnlyList<string> Paths => _paths;

    public bool Contains(string path)
    {
        return _paths.Contains(path);
    }

    public void Add(string path)
    {
        if (!_paths.Contains(path))
        {
            _paths.Add(path);
        }
    }

    public bool RemoveLast()
    {
        if (_paths.Count == 0)
        {
            return false;
        }

        _paths.RemoveAt(_paths.Count - 1);
        return true;
    }

    public void Clear()
    {
        _paths.Clear();
    }
}

public sealed record SavedPanelPlacement(
    double HorizontalFraction,
    double TopFraction,
    double SourceVisibleWidth,
    double SourceVisibleHeight,
    string? ScreenIdentifier);
