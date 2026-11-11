using YTools.Models;
using YTools.ModuleKit;
using YTools.Services.Storage;

namespace YTools.Services;

public sealed record AggregatedResults(IReadOnlyList<LauncherResult> Results, int SelectedIndex);

/// <summary>Owns result ranking and privacy-preserving usage learning.</summary>
public sealed class ResultAggregator
{
    private readonly UsageRankingStore _usage;

    public ResultAggregator(UsageRankingStore? usage = null)
    {
        _usage = usage ?? new UsageRankingStore();
    }

    public AggregatedResults Aggregate(
        IReadOnlyList<LauncherResult> background,
        IReadOnlyList<LauncherResult> fileResults,
        string query,
        IReadOnlyList<LauncherResult> previousResults,
        int selectedIndex,
        bool preserveOrder = false)
    {
        var selectedId = previousResults.Count > selectedIndex && selectedIndex >= 0
            ? previousResults[selectedIndex].Id
            : null;
        List<LauncherResult> results;
        if (preserveOrder)
        {
            results = new List<LauncherResult>(background.Count + fileResults.Count);
            results.AddRange(background);
            results.AddRange(fileResults);
        }
        else
        {
            var queryHash = _usage.NormalizedQueryHash(query);
            results = background.Concat(fileResults)
                .Select(result =>
                {
                    var (boost, count) = _usage.BoostAndCount(result.Id, queryHash);
                    return (
                        Result: result.WithScore(result.Score + boost),
                        TieCount: result.ModuleId == "applications" ? count : 0);
                })
                .OrderByDescending(entry => entry.Result.Score)
                .ThenByDescending(entry => entry.TieCount)
                .ThenBy(entry => entry.Result.Title, StringComparer.OrdinalIgnoreCase)
                .Select(entry => entry.Result)
                .ToList();
        }

        int nextIndex;
        if (selectedId is not null
            && results.FindIndex(result => result.Id == selectedId) is { } retained
            && retained >= 0)
        {
            nextIndex = retained;
        }
        else
        {
            nextIndex = results.Count == 0 ? 0 : Math.Min(selectedIndex, results.Count - 1);
        }

        return new AggregatedResults(results, nextIndex);
    }

    public void Record(LauncherResult result, string query)
    {
        _usage.Record(result.Id, query);
    }

    public void ClearLearning()
    {
        _usage.Clear();
    }
}
