import Foundation

/// Coalesces a burst of main-actor changes into one final operation.
/// Re-scheduling always cancels the previous task, so stale work never runs.
@MainActor
public final class DebouncedAction {
    private var task: Task<Void, Never>?

    public init() {}

    public func schedule(
        after delay: Duration,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.task = nil
            action()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}
