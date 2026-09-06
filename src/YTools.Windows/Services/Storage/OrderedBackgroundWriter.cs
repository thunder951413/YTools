namespace YTools.Services.Storage;

/// <summary>Runs storage operations in submission order on the thread pool.</summary>
internal sealed class OrderedBackgroundWriter
{
    private readonly object _gate = new();
    private Task _tail = Task.CompletedTask;

    public Task<T> Enqueue<T>(Func<T> operation)
    {
        lock (_gate)
        {
            var task = _tail.ContinueWith(
                _ => operation(),
                CancellationToken.None,
                TaskContinuationOptions.None,
                TaskScheduler.Default);
            _tail = task;
            return task;
        }
    }

    public Task DrainAsync()
    {
        lock (_gate)
        {
            return _tail;
        }
    }
}
