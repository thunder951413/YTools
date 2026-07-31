using YTools.Models;

namespace YTools.Services.Storage;

/// <summary>
/// Serializes every encrypted-vault operation. Revisions prevent a late, older
/// UI snapshot from overwriting a newer mutation.
/// </summary>
public sealed class ClipboardPersistenceService
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private ClipboardHistoryStore? _store;
    private int _latestRevision;

    public async Task<ClipboardStoreLoadResult> LoadAsync()
    {
        await _gate.WaitAsync();
        try
        {
            return StoreInstance().Load();
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<(bool Success, List<ClipboardHistoryItem>? Normalized, string? Error)> PersistAsync(
        IReadOnlyList<ClipboardHistoryItem> items,
        IReadOnlyDictionary<Guid, byte[]> originalImages,
        int revision)
    {
        await _gate.WaitAsync();
        try
        {
            if (revision <= _latestRevision)
            {
                return (true, null, null);
            }

            var normalized = StoreInstance().Persist(items, originalImages);
            _latestRevision = revision;
            return (true, normalized, null);
        }
        catch (Exception exception)
        {
            return (false, null, exception.Message);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<byte[]?> ImageDataAsync(Guid id)
    {
        await _gate.WaitAsync();
        try
        {
            return StoreInstance().ImageData(id);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<(bool Success, string? Error)> ClearAsync(int revision)
    {
        await _gate.WaitAsync();
        try
        {
            if (revision <= _latestRevision)
            {
                return (true, null);
            }

            StoreInstance().RemovePersistedHistory();
            _latestRevision = revision;
            return (true, null);
        }
        catch (Exception exception)
        {
            return (false, exception.Message);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<long> DiskUsageAsync()
    {
        await _gate.WaitAsync();
        try
        {
            return StoreInstance().DiskUsage();
        }
        finally
        {
            _gate.Release();
        }
    }

    private ClipboardHistoryStore StoreInstance()
    {
        return _store ??= new ClipboardHistoryStore();
    }
}
