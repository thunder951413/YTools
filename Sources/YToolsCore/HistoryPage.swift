/// Scans the entire history for matches while limiting the rows published to UI.
public struct HistoryPage<Element: Sendable>: Sendable {
    public let items: [Element]
    public let totalMatches: Int
    public var hasMore: Bool { items.count < totalMatches }

    public static func select(_ source: [Element], limit: Int,
                              matching: (Element) -> Bool) -> Self {
        var visible: [Element] = []
        let capacity = min(max(limit, 0), source.count)
        visible.reserveCapacity(capacity)
        var count = 0
        for item in source where matching(item) {
            count += 1
            if visible.count < capacity { visible.append(item) }
        }
        return Self(items: visible, totalMatches: count)
    }
}
