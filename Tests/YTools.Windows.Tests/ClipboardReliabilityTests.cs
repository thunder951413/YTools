using System.IO;
using System.Security.Cryptography;
using YTools.Models;
using YTools.Services;
using YTools.Services.Storage;
using static YTools.Services.ClipboardCloudSyncService;

namespace YTools.Windows.Tests;

public sealed class ClipboardReliabilityTests
{
    private static ClipboardHistoryItem Item(Guid id, int updated, bool pinned = false) =>
        new(id, ClipboardItemKind.Text, ["fixture"], DateTimeOffset.FromUnixTimeSeconds(100), null,
            IsPinned: pinned, UpdatedAt: DateTimeOffset.FromUnixTimeSeconds(updated));

    [Fact]
    public void PersistedTombstoneRejectsDelayedUpsert()
    {
        var id = Guid.NewGuid();
        var entry = ClipboardCloudEvent.Upsert(1, Guid.NewGuid(), Item(id, 150));
        var deleted = new Dictionary<Guid, DateTimeOffset> { [id] = DateTimeOffset.FromUnixTimeSeconds(200) };
        Assert.Empty(ApplyEvents([], [entry], deleted));
    }

    [Fact]
    public void OlderDeletionCannotEraseNewerLocalEdit()
    {
        var id = Guid.NewGuid();
        var current = Item(id, 300);
        var entry = ClipboardCloudEvent.Delete(1, Guid.NewGuid(), [id], DateTimeOffset.FromUnixTimeSeconds(200));
        Assert.Equal(current, Assert.Single(ApplyEvents([current], [entry])));
    }

    [Fact]
    public void EqualTimestampUpdatesConvergeAndCurrentLocalAdditionSurvives()
    {
        var id = Guid.NewGuid();
        var extra = Item(Guid.NewGuid(), 400);
        var plain = Item(id, 300);
        var pinned = Item(id, 300, pinned: true);
        var device = Guid.NewGuid();
        var forward = ApplyEvents([plain, extra], [ClipboardCloudEvent.Upsert(1, device, pinned)]);
        var reverse = ApplyEvents([pinned, extra], [ClipboardCloudEvent.Upsert(2, device, plain)]);
        Assert.Equal(forward, reverse);
        Assert.Contains(extra, forward);
    }

    [Fact]
    public async Task DownloadStopsAtBoundRatherThanBufferingEntireResponse()
    {
        using var stream = new MemoryStream(new byte[100_000]);
        await Assert.ThrowsAsync<InvalidDataException>(() => ReadBoundedAsync(stream, 4096, CancellationToken.None));
        Assert.Equal(4097, stream.Position);
    }

    [Fact]
    public void UnreadableArchiveNeverRequestsReplacementKeyOrOverwritesCiphertext()
    {
        var path = Path.Combine(Path.GetTempPath(), $"ytools-reliability-{Guid.NewGuid():N}.enc");
        var bytes = new byte[] { 1, 2, 3, 4 };
        File.WriteAllBytes(path, bytes);
        try
        {
            var store = new SecureCodableStore(path, create =>
            {
                Assert.False(create);
                throw new CryptographicException("missing key fixture");
            });
            Assert.Equal(SecureStoreLoadResultKind.Unavailable, store.Load<List<string>>().Kind);
            Assert.False(store.Save(new[] { "replacement" }));
            Assert.Equal(bytes, File.ReadAllBytes(path));
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void ValidEncryptionWithInvalidSchemaLocksExistingArchive()
    {
        var path = Path.Combine(Path.GetTempPath(), $"ytools-reliability-{Guid.NewGuid():N}.enc");
        var key = RandomNumberGenerator.GetBytes(32);
        var bytes = AesGcmBox.Seal("{\"wrong\":true}"u8.ToArray(), key);
        File.WriteAllBytes(path, bytes);
        try
        {
            var store = new SecureCodableStore(path, _ => key);
            Assert.Equal(SecureStoreLoadResultKind.Corrupted, store.Load<List<string>>().Kind);
            Assert.False(store.Save(new[] { "replacement" }));
            Assert.Equal(bytes, File.ReadAllBytes(path));
        }
        finally { File.Delete(path); }
    }
}
