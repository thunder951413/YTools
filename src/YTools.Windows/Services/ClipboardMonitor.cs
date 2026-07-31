using System.Windows.Threading;

namespace YTools.Services;

/// <summary>
/// Listens for clipboard changes through WM_CLIPBOARDUPDATE with a sequence
/// polling fallback, mirroring the macOS poller's robustness.
/// </summary>
public sealed class ClipboardMonitor : IDisposable
{
    private readonly MessageWindowService _messages;
    private readonly DispatcherTimer _pollTimer;
    private uint _lastSequence;

    public ClipboardMonitor(MessageWindowService messages)
    {
        _messages = messages;
        _messages.ClipboardUpdated += OnClipboardUpdated;
        _lastSequence = MessageWindowService.GetClipboardSequenceNumber();
        _pollTimer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromMilliseconds(500)
        };
        _pollTimer.Tick += (_, _) => Poll();
        _pollTimer.Start();
    }

    public event Action? Changed;

    public void Dispose()
    {
        _messages.ClipboardUpdated -= OnClipboardUpdated;
        _pollTimer.Stop();
    }

    private void OnClipboardUpdated()
    {
        _lastSequence = MessageWindowService.GetClipboardSequenceNumber();
        Changed?.Invoke();
    }

    private void Poll()
    {
        var sequence = MessageWindowService.GetClipboardSequenceNumber();
        if (sequence != _lastSequence)
        {
            _lastSequence = sequence;
            Changed?.Invoke();
        }
    }
}
