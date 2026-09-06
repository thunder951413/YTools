using System.IO;
using YTools.Core;
using YTools.Models;
using YTools.ModuleKit;
using YTools.Services;

namespace YTools.Windows.Tests;

public class LocalPathPolicyTests
{
    [Theory]
    [InlineData(@"C:\Tools\YTools.exe")]
    [InlineData("D:/Documents/report.txt")]
    public void IsValid_AcceptsFullyQualifiedLocalDrivePaths(string path)
    {
        Assert.True(LocalPathPolicy.IsValid(path));
    }

    [Theory]
    [InlineData(@"C:relative.txt")]
    [InlineData(@"\Windows\win.ini")]
    [InlineData(@"\\server\share\file.txt")]
    [InlineData(@"\\?\C:\Windows\win.ini")]
    [InlineData(@"\\.\PhysicalDrive0")]
    [InlineData("https://example.com/file")]
    public void IsValid_RejectsNonLocalOrNonFullyQualifiedPaths(string path)
    {
        Assert.False(LocalPathPolicy.IsValid(path));
    }

    [Fact]
    public void ModulePolicy_RejectsDriveRelativeFileAction()
    {
        var capabilities = new HashSet<ModuleCapability> { ModuleCapability.LocalFileRead };
        var policy = new ModuleResultPolicy(allowedCapabilities: capabilities);
        var descriptor = new ModuleDescriptor("files", "Files", capabilities);
        var result = new LauncherResult(
            "bad-path",
            "files",
            "bad",
            "",
            new ResultIcon.File(@"C:relative.txt"),
            1,
            new ResultAction.Open(@"C:relative.txt"));

        Assert.Null(policy.Sanitize(result, descriptor));
    }

    [Theory]
    [InlineData("~other")]
    [InlineData("~evil/path")]
    public void ModulePolicy_RejectsMalformedTildeNavigation(string path)
    {
        var capabilities = new HashSet<ModuleCapability> { ModuleCapability.LocalFileRead };
        var policy = new ModuleResultPolicy(allowedCapabilities: capabilities);
        var descriptor = new ModuleDescriptor("files", "Files", capabilities);
        var result = new LauncherResult(
            "bad-navigation",
            "files",
            "bad",
            "",
            new ResultIcon.System("folder"),
            1,
            new ResultAction.Navigate(path));

        Assert.Null(policy.Sanitize(result, descriptor));
    }
}

public class ApplicationActionIdentityTests
{
    [Fact]
    public void ActionsFor_UnresolvedShortcutDoesNotOfferProcessActions()
    {
        var root = Path.Combine(Path.GetTempPath(), $"ytools-runtime-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        var shortcut = Path.Combine(root, "Different Name.lnk");
        File.WriteAllBytes(shortcut, []);
        try
        {
            var result = ApplicationResult(shortcut);
            var actions = new ActionRegistry().ActionsFor(result);

            Assert.DoesNotContain(actions, action => action.Payload is ResultAction.HideApplication);
            Assert.DoesNotContain(actions, action => action.Payload is ResultAction.QuitApplication);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void ActionsFor_ExecutableUsesValidatedFullPathAsIdentity()
    {
        var root = Path.Combine(Path.GetTempPath(), $"ytools-runtime-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        var executable = Path.Combine(root, "Actual.exe");
        File.WriteAllBytes(executable, []);
        try
        {
            var actions = new ActionRegistry().ActionsFor(ApplicationResult(executable));

            var quit = Assert.IsType<ResultAction.QuitApplication>(
                Assert.Single(actions, action => action.Id == "quit-application").Payload);
            Assert.Equal(Path.GetFullPath(executable), quit.ExecutablePath, ignoreCase: true);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private static LauncherResult ApplicationResult(string iconPath)
    {
        return new LauncherResult(
            "application:test",
            "applications",
            "Test",
            "",
            new ResultIcon.Application(iconPath),
            100,
            new ResultAction.Open(iconPath));
    }
}

public class FallbackFileIndexTests
{
    [Fact]
    public async Task CompletedBuildPublishesEventAndRefreshMakesNewSnapshotVisible()
    {
        var root = CreateRoot(out var first);
        var snapshots = new Queue<IReadOnlyList<string>>();
        snapshots.Enqueue([first]);
        var second = Path.Combine(root, "second.txt");
        File.WriteAllText(second, "second");
        snapshots.Enqueue([first, second]);
        using var service = new FileSearchService(
            enableEverything: false,
            (_, _) => snapshots.Dequeue());
        try
        {
            await WaitForRefresh(service, () => service.SearchAsync("first", FileSearchMode.Default, [root], 20, CancellationToken.None));
            Assert.Single(await service.SearchAsync("first", FileSearchMode.Default, [root], 20, CancellationToken.None));

            await WaitForRefresh(service, () =>
            {
                service.RefreshFallbackIndexes();
                return Task.CompletedTask;
            });

            Assert.Single(await service.SearchAsync("second", FileSearchMode.Default, [root], 20, CancellationToken.None));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task FailedRefreshRetainsLastSuccessfulSnapshot()
    {
        var root = CreateRoot(out var first);
        var calls = 0;
        var failed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var service = new FileSearchService(
            enableEverything: false,
            (_, _) =>
            {
                if (Interlocked.Increment(ref calls) == 1)
                {
                    return [first];
                }

                failed.TrySetResult();
                throw new IOException("simulated refresh failure");
            });
        try
        {
            await WaitForRefresh(service, () => service.SearchAsync("first", FileSearchMode.Default, [root], 20, CancellationToken.None));
            service.RefreshFallbackIndexes();
            await failed.Task.WaitAsync(TimeSpan.FromSeconds(2));

            Assert.Single(await service.SearchAsync("first", FileSearchMode.Default, [root], 20, CancellationToken.None));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private static string CreateRoot(out string first)
    {
        var root = Path.Combine(Path.GetTempPath(), $"ytools-index-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        first = Path.Combine(root, "first.txt");
        File.WriteAllText(first, "first");
        return root;
    }

    private static async Task WaitForRefresh(FileSearchService service, Func<Task> start)
    {
        var refreshed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        EventHandler handler = (_, _) => refreshed.TrySetResult();
        service.FallbackIndexRefreshed += handler;
        try
        {
            await start();
            await refreshed.Task.WaitAsync(TimeSpan.FromSeconds(2));
        }
        finally
        {
            service.FallbackIndexRefreshed -= handler;
        }
    }
}

public class SearchRuntimeIsolationTests
{
    [Fact]
    public void PublicationPolicyRequiresMatchingGenerationQueryAndLiveToken()
    {
        using var canceled = new CancellationTokenSource();
        canceled.Cancel();

        Assert.True(SearchPublicationPolicy.CanPublish("abc", "abc", 4, 4, CancellationToken.None));
        Assert.False(SearchPublicationPolicy.CanPublish("abcd", "abc", 4, 4, CancellationToken.None));
        Assert.False(SearchPublicationPolicy.CanPublish("abc", "abc", 5, 4, CancellationToken.None));
        Assert.False(SearchPublicationPolicy.CanPublish("abc", "abc", 4, 4, canceled.Token));
    }

    [Fact]
    public async Task SearchAsync_PassesCancellationTokenAndDoesNotPublishCanceledModule()
    {
        var module = new BlockingModule();
        var coordinator = new SearchCoordinator(new SpellingService(), [module]);
        using var cancellation = new CancellationTokenSource();
        var request = new BackgroundSearchRequest(
            "blocked",
            false,
            false,
            FileNavigationSort.Name,
            true,
            true,
            new HashSet<SearchContentType> { SearchContentType.TextTools },
            new Dictionary<string, string>(),
            [],
            [],
            cancellation.Token,
            7);

        var search = coordinator.SearchAsync(request);
        await module.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => search);
        Assert.True(module.ObservedToken.CanBeCanceled);
    }

    private sealed class BlockingModule : IYToolsModule
    {
        public TaskCompletionSource Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public CancellationToken ObservedToken { get; private set; }

        public ModuleDescriptor Descriptor { get; } = new("blocking", "Blocking");

        public async Task<IReadOnlyList<LauncherResult>> SearchAsync(ModuleSearchRequest request)
        {
            ObservedToken = request.CancellationToken;
            Started.TrySetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, request.CancellationToken);
            return [];
        }
    }
}
