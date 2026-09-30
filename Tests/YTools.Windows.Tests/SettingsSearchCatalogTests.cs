using YTools.Core;

namespace YTools.Windows.Tests;

public sealed class SettingsSearchCatalogTests
{
    [Theory]
    [InlineData("坚果云")]
    [InlineData("webdav")]
    [InlineData("SYNC")]
    [InlineData("应用密码")]
    [InlineData("同步口令")]
    [InlineData("  WEBDAV\n同步口令  ")]
    public void SyncSettingsAreDiscoverable(string query)
    {
        Assert.True(SettingsSearchCatalog.Matches("clipboard", query));
        Assert.False(SettingsSearchCatalog.Matches("appearance", query));
    }

    [Fact]
    public void SpecificTargetsHaveUniqueIDsAndMatchAllTerms()
    {
        Assert.Equal(SettingsSearchCatalog.Targets.Count, SettingsSearchCatalog.Targets.Select(target => target.Id).Distinct().Count());
        Assert.Equal(new[] { "CloudPassphrase" }, SettingsSearchCatalog.SearchTargets("  WEBDAV\n同步口令  ").Select(target => target.Id));
        Assert.Equal(new[] { "ClipboardRetentionDays" }, SettingsSearchCatalog.SearchTargets("保留 天数").Select(target => target.Id));
        Assert.Empty(SettingsSearchCatalog.SearchTargets("主题 坚果云"));
        Assert.Empty(SettingsSearchCatalog.SearchTargets(" "));
    }

    [Fact]
    public void EveryTermMustMatchTheSameCategory()
    {
        Assert.True(SettingsSearchCatalog.Matches("appearance", "主题 深色"));
        Assert.False(SettingsSearchCatalog.Matches("appearance", "主题 坚果云"));
        Assert.False(SettingsSearchCatalog.Matches("missing", "主题"));
        Assert.True(SettingsSearchCatalog.Matches("general", " \n "));
    }
}
