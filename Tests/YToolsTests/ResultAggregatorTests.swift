import XCTest
@testable import YTools
import YToolsModuleKit

final class ResultAggregatorTests: XCTestCase {
    @MainActor
    func testApplicationsUseRawUsageCountWhenBoostsTie() {
        let temporaryFile = temporaryRankingFile()
        let store = UsageRankingStore(fileURL: temporaryFile.fileURL)
        defer { removeTemporaryRankingFile(temporaryFile, afterFlushing: store) }
        let frequentlyUsed = application(id: "application:frequent", title: "Zulu")
        let lessUsed = application(id: "application:less", title: "Alpha")

        record(frequentlyUsed, count: 37, in: store)
        record(lessUsed, count: 36, in: store)

        let results = ResultAggregator(usage: store).aggregate(
            background: [lessUsed, frequentlyUsed],
            spotlight: [],
            query: "",
            previousResults: [],
            selectedIndex: 0
        ).results

        XCTAssertEqual(store.boost(for: frequentlyUsed.id, query: ""), store.boost(for: lessUsed.id, query: ""))
        XCTAssertEqual(results.map(\.id), [frequentlyUsed.id, lessUsed.id])
    }

    @MainActor
    func testNonApplicationsUseTitleWhenBoostsTie() {
        let temporaryFile = temporaryRankingFile()
        let store = UsageRankingStore(fileURL: temporaryFile.fileURL)
        defer { removeTemporaryRankingFile(temporaryFile, afterFlushing: store) }
        let frequentlyUsed = result(id: "file:frequent", moduleID: "files", title: "Zulu")
        let lessUsed = result(id: "file:less", moduleID: "files", title: "Alpha")

        record(frequentlyUsed, count: 37, in: store)
        record(lessUsed, count: 36, in: store)

        let results = ResultAggregator(usage: store).aggregate(
            background: [frequentlyUsed, lessUsed],
            spotlight: [],
            query: "",
            previousResults: [],
            selectedIndex: 0
        ).results

        XCTAssertEqual(store.boost(for: frequentlyUsed.id, query: ""), store.boost(for: lessUsed.id, query: ""))
        XCTAssertEqual(results.map(\.id), [lessUsed.id, frequentlyUsed.id])
    }

    @MainActor
    func testApplicationsOutrankNonApplicationsWithTheSameScore() {
        let temporaryFile = temporaryRankingFile()
        let store = UsageRankingStore(fileURL: temporaryFile.fileURL)
        defer { removeTemporaryRankingFile(temporaryFile, afterFlushing: store) }
        let applicationResult = application(id: "application:frequent", title: "Zulu")
        let fileResult = result(id: "file:frequent", moduleID: "files", title: "Alpha")

        record(applicationResult, count: 37, in: store)
        record(fileResult, count: 37, in: store)

        let results = ResultAggregator(usage: store).aggregate(
            background: [fileResult, applicationResult],
            spotlight: [],
            query: "",
            previousResults: [],
            selectedIndex: 0
        ).results

        XCTAssertEqual(store.boost(for: applicationResult.id, query: ""), store.boost(for: fileResult.id, query: ""))
        XCTAssertEqual(results.map(\.id), [applicationResult.id, fileResult.id])
    }

    @MainActor
    func testTitlesUseLocalizedStandardComparison() {
        let temporaryFile = temporaryRankingFile()
        let store = UsageRankingStore(fileURL: temporaryFile.fileURL)
        defer { removeTemporaryRankingFile(temporaryFile, afterFlushing: store) }
        let ten = result(id: "ten", moduleID: "files", title: "Item 10")
        let two = result(id: "two", moduleID: "files", title: "Item 2")

        let results = ResultAggregator(usage: store).aggregate(
            background: [ten, two],
            spotlight: [],
            query: "",
            previousResults: [],
            selectedIndex: 0
        ).results

        XCTAssertEqual(results.map(\.id), [two.id, ten.id])
    }

    @MainActor
    func testConsecutiveRecordsPersistTheLatestSnapshot() {
        let temporaryFile = temporaryRankingFile()
        let store = UsageRankingStore(fileURL: temporaryFile.fileURL)
        defer { removeTemporaryRankingFile(temporaryFile, afterFlushing: store) }
        let identifier = "application:recorded"

        for _ in 0..<20 {
            store.record(identifier, query: "")
        }

        store.waitForPendingPersistence()
        let reloaded = UsageRankingStore(fileURL: temporaryFile.fileURL)
        XCTAssertEqual(reloaded.count(for: identifier), 20)
    }

    @MainActor
    private func record(_ result: LauncherResult, count: Int, in store: UsageRankingStore) {
        for _ in 0..<count {
            store.record(result.id, query: "")
        }
    }

    @MainActor
    private func application(id: String, title: String) -> LauncherResult {
        LauncherResult(
            id: id,
            moduleID: "applications",
            title: title,
            subtitle: "",
            icon: .application(URL(fileURLWithPath: "/Applications/\(title).app")),
            score: 0,
            action: .none
        )
    }

    @MainActor
    private func result(id: String, moduleID: String, title: String) -> LauncherResult {
        LauncherResult(
            id: id,
            moduleID: moduleID,
            title: title,
            subtitle: "",
            icon: .system("doc"),
            score: 0,
            action: .none
        )
    }

    @MainActor
    private struct TemporaryRankingFile {
        let directoryURL: URL
        let fileURL: URL
    }

    @MainActor
    private func temporaryRankingFile() -> TemporaryRankingFile {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return TemporaryRankingFile(
            directoryURL: directory,
            fileURL: directory.appendingPathComponent("usage-ranking.json")
        )
    }

    @MainActor
    private func removeTemporaryRankingFile(
        _ temporaryFile: TemporaryRankingFile,
        afterFlushing store: UsageRankingStore
    ) {
        store.waitForPendingPersistence()
        try? FileManager.default.removeItem(at: temporaryFile.directoryURL)
    }
}
