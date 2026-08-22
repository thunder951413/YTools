using System.IO;
using System.Text;
using YTools.Core;
using YTools.Models;
using YTools.ModuleKit;

namespace YTools.Windows.Tests;

public class ApplicationAliasMatcherTests
{
    private readonly ApplicationAliasMatcher _matcher = new();

    [Fact]
    public void Aliases_SplitsOnChineseAndLatinSeparators()
    {
        var aliases = _matcher.Aliases("微信,wechat;工作，办公\nwx");

        Assert.Equal(new[] { "微信", "wechat", "工作", "办公", "wx" }, aliases);
    }

    [Fact]
    public void Score_ExactAlias_ReturnsHighScore()
    {
        var score = _matcher.Score("weixin", new[] { "微信" });

        Assert.Equal(940, score);
    }

    [Fact]
    public void Score_EmptyQuery_ReturnsNull()
    {
        Assert.Null(_matcher.Score("", new[] { "微信" }));
    }
}

public class ClipboardTextPolicyTests
{
    [Theory]
    [InlineData(100, "hello", true)]
    [InlineData(100, "", false)]
    [InlineData(5, "hello world", false)]
    [InlineData(0, "hello", false)]
    public void ShouldStore_RespectsLimits(int maximum, string text, bool expected)
    {
        var policy = new ClipboardTextPolicy(maximum);

        Assert.Equal(expected, policy.ShouldStore(text));
    }
}

public class ClipboardHistoryItemTests
{
    [Fact]
    public void SameContent_IsIndependentFromItsLocalCopyCount()
    {
        var id = Guid.NewGuid();
        var original = new ClipboardHistoryItem(
            id,
            ClipboardItemKind.Text,
            ["same text"],
            DateTimeOffset.UtcNow,
            "test",
            ContentHash: "hash");
        var copiedAgain = original with { Id = Guid.NewGuid(), CopyCount = 2 };

        Assert.True(original.HasSameContent(copiedAgain));
        Assert.Equal(2, copiedAgain.CopyCount);
    }
}

public class RelativePanelPlacementTests
{
    [Fact]
    public void Create_FromAbsolute_ClampsFractions()
    {
        var placement = RelativePanelPlacement.Create(
            left: 10,
            top: 20,
            visibleOriginX: 0,
            visibleOriginY: 0,
            visibleWidth: 100,
            visibleHeight: 100);

        Assert.NotNull(placement);
        Assert.Equal(0.1, placement!.Value.HorizontalFraction, 6);
        Assert.Equal(0.8, placement.Value.TopFraction, 6);
    }

    [Fact]
    public void Resolve_RoundTrips()
    {
        var placement = RelativePanelPlacement.Create(0.25, 0.5, 800, 600)!;

        Assert.Equal(200, placement.Value.ResolvedLeft(0, 800), 6);
        Assert.Equal(300, placement.Value.ResolvedTop(0, 600), 6);
    }

    [Fact]
    public void Create_RejectsInvalidValues()
    {
        Assert.Null(RelativePanelPlacement.Create(1.5, 0.5, 100, 100));
        Assert.Null(RelativePanelPlacement.Create(0.5, 0.5, 0, 100));
    }
}

public class ModuleResultPolicyTests
{
    [Fact]
    public void Permits_RejectsUnknownCapabilities()
    {
        var policy = new ModuleResultPolicy();
        var descriptor = new ModuleDescriptor(
            "module",
            "模块",
            new HashSet<ModuleCapability> { ModuleCapability.LocalFileRead });

        Assert.False(policy.Permits(descriptor));
    }

    [Fact]
    public void Sanitize_RejectsFileActionWithoutCapability()
    {
        var policy = new ModuleResultPolicy();
        var descriptor = new ModuleDescriptor("module", "模块");
        var result = new LauncherResult(
            "id",
            "module",
            "title",
            "subtitle",
            new ResultIcon.File(@"C:\Windows\win.ini"),
            100,
            new ResultAction.Open(@"C:\Windows\win.ini"));

        Assert.Null(policy.Sanitize(result, descriptor));
    }

    [Fact]
    public void Sanitize_ClampsScoreAndHostsModuleId()
    {
        var policy = new ModuleResultPolicy(
            allowedCapabilities: new HashSet<ModuleCapability> { ModuleCapability.LocalFileRead },
            scoreLowerBound: 0,
            scoreUpperBound: 1_000);
        var descriptor = new ModuleDescriptor(
            "module",
            "模块",
            new HashSet<ModuleCapability> { ModuleCapability.LocalFileRead });
        var result = new LauncherResult(
            "id",
            "other",
            "title",
            "subtitle",
            new ResultIcon.System("gearshape"),
            50_000,
            new ResultAction.Copy("text"));

        var sanitized = policy.Sanitize(result, descriptor);

        Assert.NotNull(sanitized);
        Assert.Equal("module", sanitized!.ModuleId);
        Assert.Equal(1_000, sanitized.Score);
    }

    [Fact]
    public void Sanitize_RejectsPrivilegedActionWithoutGrant()
    {
        var policy = new ModuleResultPolicy();
        var descriptor = new ModuleDescriptor("module", "模块");
        var result = new LauncherResult(
            "id",
            "module",
            "清空回收站",
            "subtitle",
            new ResultIcon.System("trash"),
            100,
            new ResultAction.EmptyTrash());

        Assert.Null(policy.Sanitize(result, descriptor));
    }

    [Theory]
    [InlineData("Contoso.Sample_123!App")]
    [InlineData("Microsoft.AutoGenerated.{12345678-1234-1234-1234-123456789ABC}")]
    public void Sanitize_AllowsValidatedRegisteredApplicationForTrustedIndexer(string appId)
    {
        var capability = new HashSet<ModuleCapability> { ModuleCapability.ApplicationLaunch };
        var policy = new ModuleResultPolicy(allowedCapabilities: capability);
        var descriptor = new ModuleDescriptor("applications", "应用程序", capability);
        var result = new LauncherResult(
            $"application:registered:{appId}",
            "applications",
            "Sample",
            "Microsoft Store 应用",
            new ResultIcon.RegisteredApplication(appId),
            900,
            new ResultAction.ActivateApplication(appId));

        Assert.NotNull(policy.Sanitize(result, descriptor));
    }

    [Theory]
    [InlineData("")]
    [InlineData("Contoso.Sample!App\n")]
    public void Sanitize_RejectsInvalidRegisteredApplicationId(string appId)
    {
        var capability = new HashSet<ModuleCapability> { ModuleCapability.ApplicationLaunch };
        var policy = new ModuleResultPolicy(allowedCapabilities: capability);
        var descriptor = new ModuleDescriptor("applications", "应用程序", capability);
        var result = new LauncherResult(
            "application:registered:test",
            "applications",
            "Sample",
            "Microsoft Store 应用",
            new ResultIcon.RegisteredApplication(appId),
            900,
            new ResultAction.ActivateApplication(appId));

        Assert.Null(policy.Sanitize(result, descriptor));
    }
}

public class ApplicationIndexServiceTests
{
    [Fact]
    public void Search_KeepsStartMenuShortcutWhenTargetCannotBeResolved()
    {
        var root = Path.Combine(Path.GetTempPath(), $"ytools-app-index-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        var shortcut = Path.Combine(root, "Contoso Designer.lnk");
        File.WriteAllBytes(shortcut, []);
        try
        {
            var service = new YTools.Services.ApplicationIndexService(
                [root],
                Path.Combine(root, "missing-windows-apps"),
                includesRegisteredApplications: false);

            service.Prepare();
            var result = Assert.Single(service.Search("contoso", new Dictionary<string, string>(), []));

            Assert.Equal("Contoso Designer", result.Title);
            Assert.Equal(new ResultAction.Open(shortcut), result.Action);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void Search_DoesNotMergeShortcutsThatShareAnUnresolvedTarget()
    {
        var root = Path.Combine(Path.GetTempPath(), $"ytools-app-index-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        File.WriteAllBytes(Path.Combine(root, "Alpha Tool.lnk"), []);
        File.WriteAllBytes(Path.Combine(root, "Beta Tool.lnk"), []);
        try
        {
            var service = new YTools.Services.ApplicationIndexService(
                [root],
                Path.Combine(root, "missing-windows-apps"),
                includesRegisteredApplications: false);

            service.Prepare();
            var results = service.Search("tool", new Dictionary<string, string>(), []);

            Assert.Equal(2, results.Count);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void Search_CustomExecutableOutsideStartMenu_IsSearchableAndLaunchesSelectedPath()
    {
        var root = Path.Combine(Path.GetTempPath(), $"ytools-custom-app-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        var executable = Path.Combine(root, "Outside Scanner.exe");
        File.WriteAllBytes(executable, []);
        try
        {
            var service = new YTools.Services.ApplicationIndexService(
                [Path.Combine(root, "empty-start-menu")],
                Path.Combine(root, "missing-windows-apps"),
                includesRegisteredApplications: false);

            var result = Assert.Single(service.Search("scanner", new Dictionary<string, string>(), [executable]));

            Assert.Equal("Outside Scanner", result.Title);
            Assert.Equal("自定义应用", result.Subtitle);
            Assert.Equal(new ResultAction.Open(executable), result.Action);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void Search_CustomApplication_MatchesAliasForLaunchPath()
    {
        var root = Path.Combine(Path.GetTempPath(), $"ytools-custom-app-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        var executable = Path.Combine(root, "Design Studio.exe");
        File.WriteAllBytes(executable, []);
        try
        {
            var service = new YTools.Services.ApplicationIndexService(
                [Path.Combine(root, "empty-start-menu")],
                Path.Combine(root, "missing-windows-apps"),
                includesRegisteredApplications: false);

            var result = Assert.Single(service.Search(
                "启动我",
                new Dictionary<string, string> { [executable] = "启动我" },
                [executable]));

            Assert.Equal(new ResultAction.Open(executable), result.Action);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void Search_CustomApplications_IgnoresMissingAndUnsupportedPaths()
    {
        var root = Path.Combine(Path.GetTempPath(), $"ytools-custom-app-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        var unsupported = Path.Combine(root, "Not An App.txt");
        File.WriteAllText(unsupported, "ignored");
        try
        {
            var service = new YTools.Services.ApplicationIndexService(
                [Path.Combine(root, "empty-start-menu")],
                Path.Combine(root, "missing-windows-apps"),
                includesRegisteredApplications: false);

            var results = service.Search(
                "app",
                new Dictionary<string, string>(),
                [unsupported, Path.Combine(root, "Missing.exe")]);

            Assert.Empty(results);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }
}

public class EverythingIpcTests
{
    [Fact]
    public void ParseResultBuffer_ReadsValidatedUnicodePath()
    {
        var expected = @"C:\Tools\YTools.exe";
        var text = Encoding.Unicode.GetBytes(expected + '\0');
        var buffer = new byte[28 + sizeof(uint) + text.Length];
        BitConverter.GetBytes(1u).CopyTo(buffer, 0); // total items
        BitConverter.GetBytes(1u).CopyTo(buffer, 4); // available items
        BitConverter.GetBytes(4u).CopyTo(buffer, 12); // full path request
        BitConverter.GetBytes(1u).CopyTo(buffer, 16); // name sort
        BitConverter.GetBytes(28u).CopyTo(buffer, 24); // item data offset
        BitConverter.GetBytes((uint)expected.Length).CopyTo(buffer, 28);
        text.CopyTo(buffer, 32);

        var result = YTools.Services.EverythingClient.ParseResultBuffer(buffer);

        Assert.Equal(new[] { expected }, result);
    }

    [Fact]
    public void ParseResultBuffer_RejectsOutOfRangeItemOffset()
    {
        var buffer = new byte[28];
        BitConverter.GetBytes(1u).CopyTo(buffer, 4);
        BitConverter.GetBytes(4_096u).CopyTo(buffer, 24);

        Assert.Empty(YTools.Services.EverythingClient.ParseResultBuffer(buffer));
    }
}

public class SearchCoordinatorTests
{
    [Fact]
    public async Task SearchAsync_DefaultModules_ReturnsTextStatistics()
    {
        var coordinator = new YTools.Services.SearchCoordinator(new YTools.Services.SpellingService());
        var request = new YTools.Services.BackgroundSearchRequest(
            "统计 hello",
            false,
            false,
            FileNavigationSort.Name,
            true,
            true,
            new HashSet<SearchContentType> { SearchContentType.TextTools },
            new Dictionary<string, string>(),
            [],
            [],
            CancellationToken.None);

        var results = await coordinator.SearchAsync(request);

        Assert.Contains(results, result =>
            result.ModuleId == "text-statistics" && result.Title.StartsWith("5 字符", StringComparison.Ordinal));
    }

    [Fact]
    public async Task SearchAsync_CalculatorContinuation_SurvivesResultPolicy()
    {
        // Regression: the "=" continuation used ResultAction.Navigate with a
        // bare number, which the result policy rejected as a non-rooted path
        // and silently dropped the whole result.
        var coordinator = new YTools.Services.SearchCoordinator(new YTools.Services.SpellingService());
        var request = new YTools.Services.BackgroundSearchRequest(
            "1+2=",
            false,
            false,
            FileNavigationSort.Name,
            true,
            true,
            new HashSet<SearchContentType> { SearchContentType.Calculations },
            new Dictionary<string, string>(),
            [],
            [],
            CancellationToken.None);

        var results = await coordinator.SearchAsync(request);

        var continuation = Assert.Single(results);
        Assert.Equal("3", continuation.Title);
        Assert.IsType<YTools.ModuleKit.ResultAction.EditQuery>(continuation.Action);
    }
}

public class DictionaryModuleTests
{
    [Fact]
    public async Task SearchAsync_AutomaticQuery_DoesNotWaitForColdDictionary()
    {
        var dictionary = new YTools.Services.DictionaryService();
        var module = new YTools.Services.Modules.DictionaryModule(dictionary, includeAutomaticResults: true);

        var results = await module.SearchAsync(new ModuleSearchRequest("we", 8));

        Assert.Empty(results);
    }
}

public class ResultAggregatorTests
{
    [Fact]
    public void Aggregate_UsesApplicationLaunchCountAsTieBreaker()
    {
        var path = Path.Combine(Path.GetTempPath(), $"ytools-usage-{Guid.NewGuid():N}.json");
        try
        {
            var usage = new YTools.Services.Storage.UsageRankingStore(path);
            var frequent = new LauncherResult(
                "application:file:frequent",
                "applications",
                "Frequent",
                "",
                new ResultIcon.Application("C:\\frequent.exe"),
                500,
                new ResultAction.Open("C:\\frequent.exe"));
            var rare = frequent with
            {
                Id = "application:file:rare",
                Title = "Rare",
                Icon = new ResultIcon.Application("C:\\rare.exe"),
                Action = new ResultAction.Open("C:\\rare.exe")
            };
            usage.Record(frequent.Id, "");
            usage.Record(frequent.Id, "");
            usage.Record(rare.Id, "");

            var results = new YTools.Services.ResultAggregator(usage).Aggregate(
                [frequent, rare],
                [],
                "app",
                [],
                0);

            Assert.Equal(frequent.Id, results.Results[0].Id);
            Assert.Equal(2, usage.Count(frequent.Id));
        }
        finally
        {
            File.Delete(path);
        }
    }
}

public class FileSearchQueryTests
{
    [Theory]
    [InlineData("open report")]
    [InlineData("打开 report")]
    [InlineData("find report")]
    [InlineData("内容 report")]
    [InlineData("tag important")]
    public void HasExplicitMode_RecognizesFileSearchPrefixes(string query)
    {
        Assert.True(YTools.Services.FileSearchService.HasExplicitMode(query));
    }

    [Theory]
    [InlineData("report")]
    [InlineData("we")]
    public void HasExplicitMode_LeavesDefaultApplicationQueriesUnmarked(string query)
    {
        Assert.False(YTools.Services.FileSearchService.HasExplicitMode(query));
    }
}
