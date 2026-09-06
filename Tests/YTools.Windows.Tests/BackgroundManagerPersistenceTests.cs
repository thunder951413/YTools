using System.IO;
using YTools.Models;
using YTools.Services;
using YTools.Services.Storage;

namespace YTools.Windows.Tests;

public class BackgroundManagerPersistenceTests
{
    [Fact]
    public async Task SnippetSaveDuringLoadMergesWithEncryptedSnapshotAndFlushesInOrder()
    {
        var root = CreateRoot();
        var path = Path.Combine(root, "snippets.enc");
        var key = Enumerable.Range(1, 32).Select(value => (byte)value).ToArray();
        var store = new SecureCodableStore(path, _ => key);
        var now = DateTimeOffset.UtcNow;
        Assert.True(store.Save(new List<SnippetItem>
        {
            new(Guid.NewGuid(), "existing", "", "old", "默认", now, now)
        }));

        try
        {
            var manager = new SnippetManager(() => store);
            var first = manager.SaveAsync("first", title: "first");
            var second = manager.SaveAsync("second", title: "second");

            Assert.True(await first);
            Assert.True(await second);
            await manager.FlushPendingChangesAsync();

            var loaded = store.Load<List<SnippetItem>>();
            Assert.Equal(SecureStoreLoadResultKind.Loaded, loaded.Kind);
            Assert.Equal(new[] { "second", "first", "existing" }, loaded.Value!.Select(item => item.Title));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task FailedSnippetSaveKeepsNewestInMemoryRevision()
    {
        var root = CreateRoot();
        var path = Path.Combine(root, "snippets.enc");
        File.WriteAllBytes(path, [1, 2, 3]);
        var store = new SecureCodableStore(path, _ => new byte[32]);
        try
        {
            var manager = new SnippetManager(() => store);
            await manager.WaitUntilLoadedAsync();

            Assert.False(await manager.SaveAsync("newest", title: "newest"));
            Assert.Contains(manager.Items, item => item.Title == "newest");
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task RecentDocumentRecordedDuringLoadIsIncludedAtFlush()
    {
        var root = CreateRoot();
        var vault = Path.Combine(root, "recent.enc");
        var oldFile = Path.Combine(root, "old.txt");
        var newFile = Path.Combine(root, "new.txt");
        File.WriteAllText(oldFile, "old");
        File.WriteAllText(newFile, "new");
        var key = Enumerable.Repeat((byte)7, 32).ToArray();
        var store = new SecureCodableStore(vault, _ => key);
        Assert.True(store.Save(new List<RecentDocumentItem>
        {
            new(Guid.NewGuid(), oldFile, DateTimeOffset.UtcNow)
        }));

        try
        {
            var manager = new RecentDocumentsManager(() => store);
            manager.Record(newFile);
            await manager.FlushPendingChangesAsync();

            var loaded = store.Load<List<RecentDocumentItem>>();
            Assert.Equal(SecureStoreLoadResultKind.Loaded, loaded.Kind);
            Assert.Equal(new[] { newFile, oldFile }, loaded.Value!.Select(item => item.Path));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private static string CreateRoot()
    {
        var root = Path.Combine(Path.GetTempPath(), $"ytools-manager-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        return root;
    }
}
