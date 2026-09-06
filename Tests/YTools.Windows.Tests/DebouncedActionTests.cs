using System.Collections.Concurrent;
using YTools.Core;

namespace YTools.Windows.Tests;

public sealed class DebouncedActionTests
{
    [Fact]
    public void RescheduleCancelsCallbackAlreadyPostedToUiContext()
    {
        var originalContext = SynchronizationContext.Current;
        var context = new QueuedSynchronizationContext();
        var debouncer = new DebouncedAction();
        var staleRan = false;

        try
        {
            SynchronizationContext.SetSynchronizationContext(context);
            debouncer.Schedule(TimeSpan.Zero, () => staleRan = true);
            Assert.True(context.WaitForPost(TimeSpan.FromSeconds(2)));

            // The old delay has elapsed and its callback is queued, but a new
            // keystroke arrives before the UI dispatcher processes that queue.
            debouncer.Schedule(TimeSpan.FromMinutes(1), () => { });
            context.RunAll();

            Assert.False(staleRan);
        }
        finally
        {
            debouncer.Cancel();
            SynchronizationContext.SetSynchronizationContext(originalContext);
        }
    }

    private sealed class QueuedSynchronizationContext : SynchronizationContext
    {
        private readonly ConcurrentQueue<(SendOrPostCallback Callback, object? State)> _callbacks = new();
        private readonly ManualResetEventSlim _posted = new();

        public override void Post(SendOrPostCallback d, object? state)
        {
            _callbacks.Enqueue((d, state));
            _posted.Set();
        }

        public bool WaitForPost(TimeSpan timeout) => _posted.Wait(timeout);

        public void RunAll()
        {
            while (_callbacks.TryDequeue(out var callback))
            {
                callback.Callback(callback.State);
            }
        }
    }
}
