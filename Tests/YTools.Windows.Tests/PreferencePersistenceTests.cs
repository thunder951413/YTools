using System.IO;
using System.Text.Json;
using YTools.Models;

namespace YTools.Windows.Tests;

public sealed class PreferencePersistenceTests
{
    [Fact]
    public async Task BurstAndShutdownFlushPersistOnlyTheNewestSnapshot()
    {
        var root = Root();
        try
        {
            var path = Path.Combine(root, "settings.json");
            var preferences = new AppPreferences(path, () => false);
            for (var index = 0; index < 100; index++) { preferences.PanelWidth = 640 + index; }
            preferences.SearchInputDelay = 0.275;
            await preferences.FlushPendingChangesAsync();
            using var json = JsonDocument.Parse(File.ReadAllText(path));
            Assert.Equal(739, json.RootElement.GetProperty("PanelWidth").GetDouble());
            Assert.Equal(0.275, json.RootElement.GetProperty("SearchInputDelay").GetDouble());
            Assert.False(preferences.HasPendingSave);
            Assert.Null(preferences.StorageError);
            Assert.Empty(Directory.GetFiles(root, "*.tmp"));
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public async Task CorruptedPreferencesRemainUntouchedUntilExplicitRestore()
    {
        var root = Root();
        try
        {
            var path = Path.Combine(root, "settings.json");
            const string original = "{broken preferences";
            File.WriteAllText(path, original);
            var preferences = new AppPreferences(path, () => false);
            preferences.PanelWidth = 900;
            await preferences.FlushPendingChangesAsync();
            Assert.Equal(original, File.ReadAllText(path));
            Assert.NotNull(preferences.StorageError);
            preferences.RestoreDefaults();
            await preferences.FlushPendingChangesAsync();
            Assert.Null(preferences.StorageError);
            Assert.Equal(original, File.ReadAllText(Assert.Single(Directory.GetFiles(root, "*.bak"))));
            using var json = JsonDocument.Parse(File.ReadAllText(path));
            Assert.Equal(720, json.RootElement.GetProperty("PanelWidth").GetDouble());
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public async Task MinimalOlderPreferencesKeepValuesAndDefaultMissingRetention()
    {
        var root = Root();
        try
        {
            var path = Path.Combine(root, "settings.json");
            File.WriteAllText(path, "{\"SchemaVersion\":8,\"PanelWidth\":800}");
            var preferences = new AppPreferences(path, () => false);
            Assert.Equal(800, preferences.PanelWidth);
            Assert.Equal(7, preferences.ClipboardRetentionDays);
            Assert.Null(preferences.StorageError);
            await preferences.FlushPendingChangesAsync();
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public async Task NewerSchemaIsNotRewrittenByThisVersion()
    {
        var root = Root();
        try
        {
            var path = Path.Combine(root, "settings.json");
            const string original = "{\"SchemaVersion\":999,\"FutureSetting\":\"preserve\"}";
            File.WriteAllText(path, original);
            var preferences = new AppPreferences(path, () => false);
            preferences.PanelWidth = 880;
            await preferences.FlushPendingChangesAsync();
            Assert.Equal(original, File.ReadAllText(path));
            Assert.NotNull(preferences.StorageError);
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public async Task WriteFailureIsVisibleAndDoesNotClaimSaved()
    {
        var root = Root();
        try
        {
            var blocked = Path.Combine(root, "blocked");
            File.WriteAllText(blocked, "keep");
            var preferences = new AppPreferences(Path.Combine(blocked, "settings.json"), () => false);
            preferences.PanelWidth = 850;
            await preferences.FlushPendingChangesAsync();
            Assert.True(preferences.HasPendingSave);
            Assert.NotNull(preferences.StorageError);
            Assert.Equal("keep", File.ReadAllText(blocked));
        }
        finally { Directory.Delete(root, recursive: true); }
    }
    private static string Root()
    {
        var path = Path.Combine(Path.GetTempPath(), "ytools-preferences-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }
}
