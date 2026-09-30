namespace YTools.Core;

/// <summary>Counts every matching record while limiting the rows published to UI.</summary>
public sealed record HistoryPage<T>(IReadOnlyList<T> Items, int TotalMatches)
{
    public bool HasMore => Items.Count < TotalMatches;

    public static HistoryPage<T> Select(IReadOnlyList<T> source, int limit, Func<T, bool> matching)
    {
        var capacity = Math.Min(Math.Max(limit, 0), source.Count);
        var visible = new List<T>(capacity);
        var count = 0;
        foreach (var item in source.Where(matching))
        {
            count++;
            if (visible.Count < capacity) { visible.Add(item); }
        }
        return new HistoryPage<T>(visible, count);
    }
}
