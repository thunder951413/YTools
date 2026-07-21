/// Tracks the first key press after a launcher panel is presented.
public struct FirstKeyBackspacePolicy: Sendable {
    private var isAwaitingFirstKey = false

    public init() {}

    public mutating func beginPresentation() {
        isAwaitingFirstKey = true
    }

    public mutating func shouldClearQuery(
        for event: PanelKeyEvent,
        isEditingText: Bool,
        hasMarkedText: Bool
    ) -> Bool {
        guard isAwaitingFirstKey else { return false }
        isAwaitingFirstKey = false
        return event.keyCode == 51
            && event.modifiers.isEmpty
            && isEditingText
            && !hasMarkedText
    }
}
