/// Keeps the panel steady across provider batches and consecutive keystrokes.
public struct SearchPresentationState: Sendable {
    public private(set) var reservedRows = 0
    public private(set) var preservesSelection = false

    public init() {}
    public mutating func beginQuery() {
        reservedRows = max(reservedRows, 3)
        preservesSelection = false
    }
    public mutating func includeResults(count: Int) {
        reservedRows = max(reservedRows, min(max(count, 0), 6))
    }
    public mutating func userSelected() { preservesSelection = true }
    public mutating func reset() { self = SearchPresentationState() }
}
