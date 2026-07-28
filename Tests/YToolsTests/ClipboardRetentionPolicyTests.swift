import XCTest
import YToolsCore

final class ClipboardRetentionPolicyTests: XCTestCase {
    func testFrequentlyUsedItemIgnoresAge() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let old = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let policy = ClipboardRetentionPolicy(retentionDays: 7, maximumItems: 300)

        XCTAssertFalse(policy.shouldRetain(createdAt: old, useCount: 4, isPinned: false, now: now))
        XCTAssertTrue(policy.shouldRetain(createdAt: old, useCount: 5, isPinned: false, now: now))
    }

    func testZeroMaximumMeansUnlimited() {
        XCTAssertEqual(
            ClipboardRetentionPolicy(retentionDays: 7, maximumItems: 0).limitedCount(12_345),
            12_345
        )
        XCTAssertEqual(
            ClipboardRetentionPolicy(retentionDays: 7, maximumItems: 300).limitedCount(12_345),
            300
        )
    }
}
