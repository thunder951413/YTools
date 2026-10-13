using System.Security.Cryptography;
using System.Text;
using YTools.Services;

namespace YTools.Windows.Tests;

public sealed class ClipboardCloudSyncTests
{
    [Fact]
    public void EncryptedEvent_RoundTripsOnlyWithItsSyncPassphrase()
    {
        var clear = Encoding.UTF8.GetBytes("clipboard content must not reach WebDAV in plaintext");

        var encrypted = ClipboardCloudCryptography.Seal(clear, "a-long-enough-sync-passphrase");

        Assert.NotEqual(clear, encrypted);
        Assert.Equal(clear, ClipboardCloudCryptography.Open(encrypted, "a-long-enough-sync-passphrase"));
        Assert.ThrowsAny<CryptographicException>(() => ClipboardCloudCryptography.Open(encrypted, "another-sync-passphrase"));
    }

    [Fact]
    public void EncryptedEvent_RejectsUnknownEnvelope()
    {
        Assert.Throws<CryptographicException>(() =>
            ClipboardCloudCryptography.Open(Encoding.UTF8.GetBytes("not a sync envelope"), "a-long-enough-sync-passphrase"));
    }

    [Fact]
    public void Envelopes_ShareSaltButUseFreshNoncesAndStayDecryptable()
    {
        var clear = Encoding.UTF8.GetBytes("same clear text");
        var first = ClipboardCloudCryptography.Seal(clear, "a-long-enough-sync-passphrase");
        var second = ClipboardCloudCryptography.Seal(clear, "a-long-enough-sync-passphrase");

        Assert.Equal(first[5..21], second[5..21]);
        Assert.NotEqual(first[21..33], second[21..33]);
        Assert.Equal(clear, ClipboardCloudCryptography.Open(first, "a-long-enough-sync-passphrase"));
        Assert.Equal(clear, ClipboardCloudCryptography.Open(second, "a-long-enough-sync-passphrase"));
    }

    [Fact]
    public void DerivedKeyCache_DerivesOncePerSaltAndReusesSealingSalt()
    {
        var cache = new DerivedKeyCache();
        var derivations = 0;
        byte[] Derive(string passphrase, byte[] salt)
        {
            derivations += 1;
            return [.. salt, .. salt];
        }

        var first = cache.SealingKey("passphrase-one", 16, Derive);
        var second = cache.SealingKey("passphrase-one", 16, Derive);
        Assert.Equal(first.Salt, second.Salt);
        Assert.Equal(1, derivations);

        var other = cache.SealingKey("passphrase-two", 16, Derive);
        Assert.NotEqual(first.Salt, other.Salt);
        Assert.Equal(2, derivations);

        _ = cache.Key("passphrase-one", first.Salt, Derive);
        Assert.Equal(2, derivations);
        _ = cache.Key("passphrase-one", new byte[16], Derive);
        Assert.Equal(3, derivations);
    }
}
