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
        Assert.Throws<CryptographicException>(() => ClipboardCloudCryptography.Open(encrypted, "another-sync-passphrase"));
    }

    [Fact]
    public void EncryptedEvent_RejectsUnknownEnvelope()
    {
        Assert.Throws<CryptographicException>(() =>
            ClipboardCloudCryptography.Open(Encoding.UTF8.GetBytes("not a sync envelope"), "a-long-enough-sync-passphrase"));
    }
}
