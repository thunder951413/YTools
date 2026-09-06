import Foundation
import XCTest
@testable import YTools

@MainActor
final class BackgroundManagerPersistenceTests: XCTestCase {
    func testSnippetSaveDuringLoadMergesAndFlushesLatestRevision() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("snippets.enc")
        let key = Data(repeating: 9, count: 32)
        let store = SecureCodableStore(fileURL: url) { _ in key }
        let now = Date()
        XCTAssertTrue(store.save([
            SnippetItem(id: UUID(), title: "existing", keyword: "", content: "old", collection: "默认", createdAt: now, updatedAt: now)
        ]))

        let manager = SnippetManager { store }
        XCTAssertTrue(manager.save(text: "first", title: "first"))
        XCTAssertTrue(manager.save(text: "second", title: "second"))
        await manager.flushPendingChanges()

        guard case let .loaded(items) = store.load([SnippetItem].self) else {
            return XCTFail("Expected encrypted snippet snapshot")
        }
        XCTAssertEqual(Set(items.map(\.title)), Set(["existing", "first", "second"]))
        XCTAssertEqual(items.first?.title, "second")
    }

    func testFailedSnippetSaveKeepsNewestMemoryValue() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("snippets.enc")
        try Data([1, 2, 3]).write(to: url)
        let store = SecureCodableStore(fileURL: url) { _ in Data(repeating: 4, count: 32) }
        let manager = SnippetManager { store }
        await manager.waitUntilLoaded()

        let saved = await manager.savePersisted(text: "newest", title: "newest")
        XCTAssertFalse(saved)
        XCTAssertTrue(manager.items.contains { $0.title == "newest" })
    }

    func testRecentDocumentRecordedDuringLoadSurvivesFlush() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = root.appendingPathComponent("recent.enc")
        let old = root.appendingPathComponent("old.txt")
        let new = root.appendingPathComponent("new.txt")
        try Data("old".utf8).write(to: old)
        try Data("new".utf8).write(to: new)
        let store = SecureCodableStore(fileURL: vault) { _ in Data(repeating: 5, count: 32) }
        XCTAssertTrue(store.save([RecentDocumentItem(id: UUID(), path: old.path, lastOpenedAt: Date())]))

        let manager = RecentDocumentsManager { store }
        manager.record(new)
        await manager.flushPendingChanges()

        guard case let .loaded(items) = store.load([RecentDocumentItem].self) else {
            return XCTFail("Expected encrypted recent-document snapshot")
        }
        XCTAssertEqual(items.map(\.path), [new.path, old.path])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytools-manager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
