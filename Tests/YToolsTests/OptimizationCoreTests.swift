import XCTest
import YToolsCore

final class OptimizationCoreTests: XCTestCase {
    func testBatchBudgetHonorsCountAndBytesWithoutOverflow() {
        XCTAssertTrue(CloudBatchBudget.canInclude(count: 49, bytes: CloudBatchBudget.maximumBytes - 100, nextBytes: 100))
        XCTAssertFalse(CloudBatchBudget.canInclude(count: 50, bytes: 0, nextBytes: 1))
        XCTAssertFalse(CloudBatchBudget.canInclude(count: 49, bytes: CloudBatchBudget.maximumBytes - 100, nextBytes: 101))
        XCTAssertFalse(CloudBatchBudget.canInclude(count: 0, bytes: Int.max, nextBytes: Int.max))
    }
    func testDiagnosticsContainsOnlyFixedStateAndRejectsVersionContent() {
        let report = LocalDiagnosticReport.text(version: "secret-user-content", platform: .macOS, backend: .spotlight,
            historyCount: -1, pinnedCount: 2, snippetCount: 3, preferencesHealthy: true, clipboardHealthy: false,
            snippetsHealthy: true, recentDocumentsHealthy: true, cloudEnabled: false)
        XCTAssertFalse(report.contains("secret-user-content"))
        XCTAssertTrue(report.contains("剪贴板记录：0"))
        XCTAssertTrue(report.contains("剪贴板存储：需处理"))
        XCTAssertFalse(report.contains("http"))
    }
    func testTransferProgressClampsAndAccountsForEmptyDirectories() {
        XCTAssertEqual(FileTransferProgress(completedBytes: 20, totalBytes: 40, phase: .copying).percentage, 50)
        XCTAssertEqual(FileTransferProgress(completedBytes: 50, totalBytes: 40, phase: .copying).percentage, 100)
        XCTAssertEqual(FileTransferProgress(completedBytes: 0, totalBytes: 0, phase: .completed).percentage, 100)
    }
}
