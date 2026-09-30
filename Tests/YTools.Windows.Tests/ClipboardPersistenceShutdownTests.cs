using YTools.Services.Storage;

namespace YTools.Windows.Tests;

public sealed class ClipboardPersistenceShutdownTests
{
    [Fact]
    public async Task DisposeWaitsForAlreadyDispatchedVaultWork()
    {
        using var entered = new ManualResetEventSlim();
        using var release = new ManualResetEventSlim();
        // The factory is blocked before constructing any real vault or key.
        using var service = new ClipboardPersistenceService(() =>
        {
            entered.Set();
            Assert.True(release.Wait(TimeSpan.FromSeconds(5)));
            throw new InvalidOperationException("synthetic vault failure");
        });
        var load = service.LoadAsync();
        Assert.True(entered.Wait(TimeSpan.FromSeconds(5)));
        var dispose = Task.Run(service.Dispose);
        try { Assert.NotSame(dispose, await Task.WhenAny(dispose, Task.Delay(100))); }
        finally { release.Set(); }
        await dispose.WaitAsync(TimeSpan.FromSeconds(5));
        await Assert.ThrowsAsync<InvalidOperationException>(() => load);
        service.Dispose(); // Idempotent after the worker has drained.
    }
}
