using YTools.Core;
using YTools.Models;
using YTools.ModuleKit;
using YTools.Services;

namespace YTools.Windows.Tests;

public class SearchPresentationTests
{
    [Fact]
    public void ProvidersAndNextKeystrokeKeepHeightUntilQueryClears()
    {
        var state = new SearchPresentationState();
        state.BeginQuery();
        state.IncludeResults(1);
        Assert.Equal(3, state.ReservedRows);
        state.IncludeResults(20);
        state.UserSelected();
        Assert.Equal(6, state.ReservedRows);
        Assert.True(state.PreservesSelection);
        state.BeginQuery();
        state.IncludeResults(0);
        Assert.Equal(6, state.ReservedRows);
        Assert.False(state.PreservesSelection);
        state.Reset();
        Assert.Equal(0, state.ReservedRows);
    }

    [Fact]
    public void PagingCountsAllMatchesAndKeepsOlderRecordsReachable()
    {
        var records = Enumerable.Range(0, 251).ToArray();
        var first = HistoryPage<int>.Select(records, 100, value => value % 2 == 0);
        Assert.Equal(Enumerable.Range(0, 100).Select(value => value * 2), first.Items);
        Assert.Equal(126, first.TotalMatches);
        Assert.True(first.HasMore);
        var more = HistoryPage<int>.Select(records, 200, value => value % 2 == 0);
        Assert.Equal(first.Items, more.Items.Take(100));
        Assert.Equal(250, more.Items.Last());
        Assert.False(more.HasMore);
        Assert.Equal([250], HistoryPage<int>.Select(records, 100, value => value == 250).Items);
        Assert.Empty(HistoryPage<int>.Select(records, -1, _ => true).Items);
    }

    [Fact]
    public void LateHigherRankedBatchRetainsSelectionByIdentity()
    {
        var path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"ytools-ranking-{Guid.NewGuid():N}.json");
        var usage = new YTools.Services.Storage.UsageRankingStore(path);
        var aggregator = new ResultAggregator(usage);
        var early = new LauncherResult("early", "fixture", "Early", "", new ResultIcon.System("text"), 0, new ResultAction.None());
        var late = early with { Id = "late", Title = "Late", Score = 500 };
        var automatic = aggregator.Aggregate([early, late], [], "q", [], 0);
        Assert.Equal("late", automatic.Results[automatic.SelectedIndex].Id);
        var selected = aggregator.Aggregate([early, late], [], "q", [early], 0);
        Assert.Equal("early", selected.Results[selected.SelectedIndex].Id);
    }

    [Fact]
    public async Task FastModulePublishesSanitizedResultsBeforeBlockedModuleCompletes()
    {
        var gate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var first = new TaskCompletionSource<IReadOnlyList<LauncherResult>>(TaskCreationOptions.RunContinuationsAsynchronously);
        var coordinator = new SearchCoordinator(new SpellingService(), [new FixtureModule("fast"), new FixtureModule("slow", gate.Task)]);
        var search = coordinator.SearchAsync(Request(), results => { first.TrySetResult(results); return Task.CompletedTask; });
        try
        {
            var partial = await first.Task.WaitAsync(TimeSpan.FromSeconds(2));
            Assert.Equal("fast", Assert.Single(partial).ModuleId);
            Assert.False(search.IsCompleted);
        }
        finally { gate.TrySetResult(); }
        var complete = await search;
        Assert.Equal(["fast", "slow"], complete.Select(result => result.ModuleId).Order());
        Assert.DoesNotContain(complete, result => result.Title == "Blocked URL");
    }

    [Fact]
    public async Task CancellationDoesNotPublishLateBatch()
    {
        var gate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var first = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var cancellation = new CancellationTokenSource();
        var count = 0;
        var coordinator = new SearchCoordinator(new SpellingService(), [new FixtureModule("fast"), new FixtureModule("slow", gate.Task)]);
        var search = coordinator.SearchAsync(Request(cancellation.Token), _ =>
        { Interlocked.Increment(ref count); first.TrySetResult(); return Task.CompletedTask; });
        await first.Task.WaitAsync(TimeSpan.FromSeconds(2));
        cancellation.Cancel();
        gate.TrySetResult();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => search);
        Assert.Equal(1, Volatile.Read(ref count));
    }

    private static BackgroundSearchRequest Request(CancellationToken token = default) => new(
        "progressive-fixture", false, false, FileNavigationSort.Name, true, true,
        new HashSet<SearchContentType> { SearchContentType.TextTools }, new Dictionary<string, string>(), [], [], token);

    private sealed class FixtureModule(string id, Task? gate = null) : IYToolsModule
    {
        public ModuleDescriptor Descriptor => new(id, id);
        public async Task<IReadOnlyList<LauncherResult>> SearchAsync(ModuleSearchRequest request)
        {
            if (gate is not null) { await gate.WaitAsync(request.CancellationToken); }
            return [new(id, id, id, "", new ResultIcon.System("text"), 1, new ResultAction.Copy(id)),
                    new("blocked-" + id, id, "Blocked URL", "", new ResultIcon.System("link"), 1, new ResultAction.Open("ytools-test://blocked"))];
        }
    }
}
