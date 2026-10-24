/// Decides whether a keystroke may search at once or must join the debounce
/// window. The first keystroke after a quiet period is the leading edge:
/// in-memory providers answer in a few milliseconds, so waiting would only add
/// latency. Keystrokes that follow within the window are coalesced.
public struct SearchInputTiming: Sendable {
    private var lastInput: ContinuousClock.Instant?

    public init() {}

    public mutating func isLeadingEdge(at now: ContinuousClock.Instant, quietPeriod: Duration) -> Bool {
        defer { lastInput = now }
        guard let lastInput else { return true }
        return now - lastInput >= quietPeriod
    }
}
