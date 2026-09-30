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
    public void EveryTermMustMatchTheSameCategory()
    {
        Assert.True(SettingsSearchCatalog.Matches("appearance", "主题 深色"));
        Assert.False(SettingsSearchCatalog.Matches("appearance", "主题 坚果云"));
        Assert.False(SettingsSearchCatalog.Matches("missing", "主题"));
        Assert.True(SettingsSearchCatalog.Matches("general", " \n "));
    }
}
