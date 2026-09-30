import Foundation
import XCTest
@testable import YTools

final class FileOperationTests: XCTestCase {
    func testCopyAndMoveDoNotOverwriteAndRejectDescendantThroughSymlink() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ytools-files-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let child = source.appendingPathComponent("child")
        let target = root.appendingPathComponent("target")
        let moved = root.appendingPathComponent("moved")
        for url in [child, target, moved] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        try Data("synthetic-file".utf8).write(to: source.appendingPathComponent("fixture.txt"))
        let link = root.appendingPathComponent("linked-child")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: child)
        let service = FileOperationService()
        for destination in [source, child, link] {
            do {
                try await service.perform(.copy, source: source, destinationDirectory: destination)
                XCTFail("Should reject descendant destination")
            } catch { XCTAssertEqual((error as NSError).code, CocoaError.fileWriteInvalidFileName.rawValue) }
        }
        try await service.perform(.copy, source: source, destinationDirectory: target)
        let copiedFile = target.appendingPathComponent("source/fixture.txt")
        XCTAssertEqual(try Data(contentsOf: copiedFile), Data("synthetic-file".utf8))
        do {
            try await service.perform(.copy, source: source, destinationDirectory: target)
            XCTFail("Should reject existing destination")
        } catch { XCTAssertEqual((error as NSError).code, CocoaError.fileWriteFileExists.rawValue) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        try await service.perform(.move, source: source, destinationDirectory: moved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: moved.appendingPathComponent("source/fixture.txt")), Data("synthetic-file".utf8))
    }

    @MainActor
    func testDispatcherReportsCompletionAndDrainsBeforeShutdown() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ytools-action-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("fixture.txt")
        try Data("synthetic".utf8).write(to: source)
        let dispatcher = dispatcherFixture()
        if case .backgroundStarted = dispatcher.startFileOperation(.copy, source: source, directory: target) {} else {
            XCTFail("Must keep panel open while copy runs")
        }
        XCTAssertTrue(dispatcher.isBusy)
        XCTAssertTrue(dispatcher.statusText.contains("fixture.txt"))
        if case .keepPanel = dispatcher.startFileOperation(.move, source: source, directory: target) {} else {
            XCTFail("Must reject overlapping actions")
        }
        await dispatcher.flushPendingOperations()
        XCTAssertFalse(dispatcher.isBusy)
        XCTAssertTrue(dispatcher.statusText.contains("复制完成"))
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("fixture.txt")), Data("synthetic".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testDispatcherKeepsFailureVisibleAndPreservesSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ytools-action-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("fixture.txt")
        try Data("synthetic".utf8).write(to: source)
        let dispatcher = dispatcherFixture()
        _ = dispatcher.startFileOperation(.move, source: source, directory: root)
        await dispatcher.flushPendingOperations()
        XCTAssertFalse(dispatcher.isBusy)
        XCTAssertTrue(dispatcher.statusText.contains("移动失败"))
        XCTAssertEqual(try Data(contentsOf: source), Data("synthetic".utf8))
    }
}

@MainActor
private func dispatcherFixture() -> ActionDispatcher {
    ActionDispatcher(snippets: ActionSnippetFixture(), recentDocuments: ActionRecentFixture(), onOpenSettings: {}, onShowLargeType: { _ in })
}
@MainActor
private final class ActionSnippetFixture: SnippetSaving {
    var saveError: String? { nil }
    func save(text: String, title: String?, keyword: String, collection: String) -> Bool { false }
    func savePersisted(text: String, title: String?, keyword: String, collection: String) async -> Bool { false }
}
@MainActor
private final class ActionRecentFixture: RecentDocumentsRecording {
    func record(_ url: URL) {}
}
