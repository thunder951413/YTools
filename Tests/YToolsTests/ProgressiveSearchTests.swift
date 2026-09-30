import XCTest
import YToolsModuleKit
@testable import YTools

final class ProgressiveSearchTests: XCTestCase {
    func testPublishesFastSanitizedBatchBeforeSlowModuleCompletes() async {
        let gate = SearchGate()
        let updates = SearchUpdates()
        let first = expectation(description: "Fast provider publishes while slow provider is blocked")
        let coordinator = SearchCoordinator(personalModules: [FixtureSearchModule(id: "fast"), FixtureSearchModule(id: "slow", gate: gate)])
        let task = Task {
            await coordinator.search(request()) { results in
                await updates.record(results)
                if results.count == 1 { first.fulfill() }
            }
        }
        await fulfillment(of: [first], timeout: 2)
        let partial = await updates.batches
        XCTAssertEqual(partial.map { $0.map(\.moduleID) }, [["fast"]])
        await gate.open()
        let complete = await task.value
        XCTAssertEqual(Set(complete.map(\.moduleID)), ["fast", "slow"])
        XCTAssertFalse(complete.contains { $0.title == "Blocked URL" })
    }

    func testCanceledQueryDoesNotPublishLateBatch() async {
        let gate = SearchGate()
        let updates = SearchUpdates()
        let first = expectation(description: "First batch")
        let coordinator = SearchCoordinator(personalModules: [FixtureSearchModule(id: "fast"), FixtureSearchModule(id: "slow", gate: gate)])
        let task = Task {
            await coordinator.search(request()) { results in
                await updates.record(results)
                first.fulfill()
            }
        }
        await fulfillment(of: [first], timeout: 2)
        task.cancel()
        await gate.open()
        let complete = await task.value
        let batches = await updates.batches
        XCTAssertTrue(complete.isEmpty)
        XCTAssertEqual(batches.count, 1)
    }
}

private func request() -> BackgroundSearchRequest {
    BackgroundSearchRequest(query: "progressive-fixture", fileNavigationActive: false,
        showsHiddenFiles: false, fileNavigationSort: .name, fileNavigationSortAscending: true,
        fileNavigationFoldersFirst: true, enabledContentTypes: [.textTools],
        applicationAliases: [:], customApplicationPaths: [], maximumResults: 10, requestModules: [])
}

private actor SearchGate {
    private var opened = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        if !opened { await withCheckedContinuation { waiter = $0 } }
    }
    func open() { opened = true; waiter?.resume(); waiter = nil }
}
private actor SearchUpdates {
    private(set) var batches: [[LauncherResult]] = []
    func record(_ results: [LauncherResult]) { batches.append(results) }
}
private struct FixtureSearchModule: YToolsModule {
    let id: String
    var gate: SearchGate? = nil
    var descriptor: ModuleDescriptor { ModuleDescriptor(id: id, name: id) }
    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        await gate?.wait()
        return [
            LauncherResult(id: id, moduleID: id, title: id, subtitle: "", icon: .system("text.alignleft"), score: 1, action: .copy(id)),
            LauncherResult(id: "blocked-\(id)", moduleID: id, title: "Blocked URL", subtitle: "", icon: .system("link"), score: 1,
                           action: .open(URL(string: "ytools-test://blocked")!))
        ]
    }
}
