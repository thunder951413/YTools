namespace YTools.Core;

/// <summary>
/// Coalesces a burst of changes into one final operation. Re-scheduling always
/// cancels the previous task, so stale work never runs.
/// </summary>
public sealed class DebouncedAction
{
    private CancellationTokenSource? _cancellation;

    public void Schedule(TimeSpan delay, Action action)
    {
        Cancel();
        var cancellation = new CancellationTokenSource();
        _cancellation = cancellation;
        var context = SynchronizationContext.Current;

        _ = Task.Delay(delay, cancellation.Token).ContinueWith(
            completed =>
            {
                if (completed.IsCanceled || cancellation.IsCancellationRequested)
                {
                    return;
                }

                if (context is not null)
                {
                    context.Post(_ => action(), null);
                }
                else
                {
                    action();
                }
            },
            CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);
    }

    public void Cancel()
    {
        _cancellation?.Cancel();
        _cancellation = null;
    }
}
