using YTools.Core;
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
}
