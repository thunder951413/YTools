using System.Collections.Concurrent;
using YTools.Models;

namespace YTools.Services.Storage;

/// <summary>
/// Serializes every encrypted-vault operation on a dedicated worker thread.
/// Operations run strictly in dispatch order — the UI thread dispatches them
/// synchronously in call order — so a clear dispatched after a persist can
/// never be overtaken by it. Revisions additionally prevent a late, older UI
/// snapshot from overwriting a newer mutation.
/// </summary>
public sealed class ClipboardPersistenceService : IDisposable
{
    private readonly BlockingCollection<Action> _queue = new(new ConcurrentQueue<Action>());
    private readonly Thread _worker;
    private ClipboardHistoryStore? _store;
    private int _latestRevision;

    public ClipboardPersistenceService()
    {
        _worker = new Thread(RunQueue)
        {
            IsBackground = true,
            Name = "YTools.ClipboardVault"
        };
        _worker.Start();
    }

    public Task<ClipboardStoreLoadResult> LoadAsync()
    {
        return EnqueueAsync(() => Task.FromResult(StoreInstance().Load()));
    }

    public Task<(bool Success, List<ClipboardHistoryItem>? Normalized, string? Error)> PersistAsync(
        IReadOnlyList<ClipboardHistoryItem> items,
        IReadOnlyDictionary<Guid, byte[]> originalImages,
        int revision)
    {
        return EnqueueAsync<(bool Success, List<ClipboardHistoryItem>? Normalized, string? Error)>(() =>
        {
            try
            {
                if (revision <= _latestRevision)
                {
                    return Task.FromResult((true, (List<ClipboardHistoryItem>?)null, (string?)null));
                }

                var normalized = StoreInstance().Persist(items, originalImages);
                _latestRevision = revision;
                return Task.FromResult((true, (List<ClipboardHistoryItem>?)normalized, (string?)null));
            }
            catch (Exception exception)
            {
                return Task.FromResult((false, (List<ClipboardHistoryItem>?)null, (string?)exception.Message));
            }
        });
    }

    public Task<byte[]?> ImageDataAsync(Guid id)
    {
        return EnqueueAsync(() => Task.FromResult(StoreInstance().ImageData(id)));
    }

    public Task<(bool Success, string? Error)> ClearAsync(int revision)
    {
        return EnqueueAsync<(bool Success, string? Error)>(() =>
        {
            try
            {
                if (revision <= _latestRevision)
                {
                    return Task.FromResult((true, (string?)null));
                }

                StoreInstance().RemovePersistedHistory();
                _latestRevision = revision;
                return Task.FromResult((true, (string?)null));
            }
            catch (Exception exception)
            {
                return Task.FromResult((false, (string?)exception.Message));
            }
        });
    }

    public Task<long> DiskUsageAsync()
    {
        return EnqueueAsync(() => Task.FromResult(StoreInstance().DiskUsage()));
    }

    public void Dispose()
    {
        _queue.CompleteAdding();
    }

    private async Task<T> EnqueueAsync<T>(Func<Task<T>> operation)
    {
        var completion = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        _queue.Add(() =>
        {
            try
            {
                completion.TrySetResult(operation().GetAwaiter().GetResult());
            }
            catch (Exception exception)
            {
                completion.TrySetException(exception);
            }
        });
        return await completion.Task;
    }

    private void RunQueue()
    {
        foreach (var work in _queue.GetConsumingEnumerable())
        {
            work();
        }
    }

    private ClipboardHistoryStore StoreInstance()
    {
        return _store ??= new ClipboardHistoryStore();
    }
}
