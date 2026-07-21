import Foundation

public struct ClipboardRetentionPolicy: Equatable, Sendable {
    public let retentionDays: Int
    public let maximumItems: Int
    public let frequentUseThreshold: Int

    public init(retentionDays: Int, maximumItems: Int, frequentUseThreshold: Int = 5) {
        self.retentionDays = max(1, retentionDays)
        self.maximumItems = max(0, maximumItems)
        self.frequentUseThreshold = max(1, frequentUseThreshold)
    }

    public func shouldRetain(
        createdAt: Date,
        useCount: Int,
        isPinned: Bool,
        now: Date
    ) -> Bool {
        if isPinned || useCount >= frequentUseThreshold { return true }
        let retentionInterval = TimeInterval(retentionDays) * 24 * 60 * 60
        return createdAt >= now.addingTimeInterval(-retentionInterval)
    }

    public func limitedCount(_ count: Int) -> Int {
        maximumItems == 0 ? count : min(count, maximumItems)
    }
}
