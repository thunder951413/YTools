import Foundation
import Darwin
import XCTest
@testable import YTools
import YToolsCore

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

    func testCancellationCleansStageAndPreservesSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ytools-cancel-\(UUID())")
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("fixture.dat")
        try Data(repeating: 42, count: 2 * 1024 * 1024).write(to: source)
        let gate = TransferProgressGate()
        let task = Task { try await FileOperationService().perform(.copy, source: source, destinationDirectory: target) { await gate.report($0) } }
        await gate.waitUntilCopying()
        task.cancel()
        await gate.release()
        do { try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        XCTAssertEqual(try Data(contentsOf: source).count, 2 * 1024 * 1024)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }

    func testDestinationCreatedDuringCopyIsNotOverwritten() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ytools-collision-\(UUID())")
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("fixture.txt")
        let destination = target.appendingPathComponent("fixture.txt")
        try Data("source".utf8).write(to: source)
        do {
            try await FileOperationService().perform(.copy, source: source, destinationDirectory: target) { progress in
                if progress.phase == .committing { try? Data("competing-file".utf8).write(to: destination) }
            }
            XCTFail("Must not overwrite")
        } catch { XCTAssertEqual((error as NSError).code, CocoaError.fileWriteFileExists.rawValue) }
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "source")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "competing-file")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path).count, 1)
    }

    func testCopyPreservesExtendedAttributes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ytools-metadata-\(UUID())")
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("fixture.txt")
        try Data("file".utf8).write(to: source)
        let attribute = Data("synthetic metadata".utf8)
        let written = attribute.withUnsafeBytes { setxattr(source.path, "com.ytools.fixture", $0.baseAddress, $0.count, 0, 0) }
        XCTAssertEqual(written, 0)
        try await FileOperationService().perform(.copy, source: source, destinationDirectory: target)
        var actual = Data(count: attribute.count)
        let count = actual.withUnsafeMutableBytes { getxattr(target.appendingPathComponent("fixture.txt").path, "com.ytools.fixture", $0.baseAddress, $0.count, 0, 0) }
        XCTAssertEqual(count, attribute.count)
        XCTAssertEqual(actual, attribute)
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

private actor TransferProgressGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func report(_ progress: FileTransferProgress) async {
        if progress.phase == .copying && progress.completedBytes > 0 && continuation == nil {
            await withCheckedContinuation { continuation = $0 }
        }
    }
    func waitUntilCopying() async { while continuation == nil { await Task.yield() } }
    func release() { continuation?.resume(); continuation = nil }
}
