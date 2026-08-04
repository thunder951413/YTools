import Dispatch
import Foundation
import XCTest
@testable import YTools
import YToolsModuleKit

final class ApplicationModuleTests: XCTestCase {
    func testFindsCustomApplicationOutsideStandardRootsAndOpensItsExactURL() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let standardRoot = directory.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: standardRoot, withIntermediateDirectories: false)
        let customApplication = try makeApplicationBundle(in: directory, name: "External Tool")
        let module = ApplicationModule(roots: [standardRoot])

        await module.prepare()
        let results = await module.results(
            for: "external",
            customApplicationPaths: [customApplication.path]
        )

        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.title, "External Tool")
        XCTAssertEqual(result.subtitle, "自定义应用 · \(canonicalPath(for: customApplication))")
        XCTAssertEqual(result.action, .open(customApplication.standardizedFileURL))
    }

    func testIgnoresMissingAndInvalidCustomApplications() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalidApplication = directory.appendingPathComponent("Invalid.app", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidApplication, withIntermediateDirectories: false)
        let missingApplication = directory.appendingPathComponent("Missing.app", isDirectory: true)
        let module = ApplicationModule(roots: [])

        let results = await module.results(
            for: "invalid",
            customApplicationPaths: [invalidApplication.path, missingApplication.path]
        )

        XCTAssertTrue(results.isEmpty)
    }

    func testMatchesCustomApplicationAliasByCanonicalPath() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let customApplication = try makeApplicationBundle(in: directory, name: "Writing Tool")
        let module = ApplicationModule(roots: [])

        let results = await module.results(
            for: "draft",
            aliases: [canonicalPath(for: customApplication): "draft"],
            customApplicationPaths: [customApplication.path]
        )

        XCTAssertEqual(results.map(\.title), ["Writing Tool"])
    }

    func testDeduplicatesStandardAndCustomApplicationAtSameCanonicalPath() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let application = try makeApplicationBundle(in: directory, name: "Shared Tool")
        let module = ApplicationModule(roots: [directory])

        await module.prepare()
        let results = await module.results(
            for: "shared",
            customApplicationPaths: [application.path]
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.subtitle, canonicalPath(for: application))
    }

    func testDirtyIndexReturnsOldSnapshotWhileBackgroundRefreshIsBlocked() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldApplication = try makeApplicationBundle(in: directory, name: "Old Tool")
        let newApplication = try makeApplicationBundle(in: directory, name: "New Tool")
        let scanner = ControlledScanner(snapshots: [[oldApplication], [oldApplication, newApplication]])
        let module = ApplicationModule(roots: [], scan: { _ in scanner.scan() })

        await module.prepare()
        await module.invalidateIndexForTesting()
        scanner.blockNextScan()

        let immediateResults = await module.results(for: "old")
        XCTAssertEqual(immediateResults.map(\.title), ["Old Tool"])
        XCTAssertEqual(scanner.waitForBlockedScan(), .success)

        scanner.releaseBlockedScan()
        await module.waitForRefreshForTesting()
        let refreshedResults = await module.results(for: "new")
        XCTAssertEqual(refreshedResults.map(\.title), ["New Tool"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func makeApplicationBundle(in directory: URL, name: String) throws -> URL {
        let application = directory.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = application.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": "com.ytools.tests.\(UUID().uuidString)"]
        let plistURL = contents.appendingPathComponent("Info.plist")
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: plistURL)
        return application
    }

    private func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

private final class ControlledScanner: @unchecked Sendable {
    private let lock = NSLock()
    private let blockedScanStarted = DispatchSemaphore(value: 0)
    private let releaseBlockedScan = DispatchSemaphore(value: 0)
    private var snapshots: [[URL]]
    private var shouldBlockNextScan = false

    init(snapshots: [[URL]]) {
        self.snapshots = snapshots
    }

    func scan() -> [URL] {
        lock.lock()
        let snapshot = snapshots.isEmpty ? [] : snapshots.removeFirst()
        let shouldBlock = shouldBlockNextScan
        shouldBlockNextScan = false
        lock.unlock()
        if shouldBlock {
            blockedScanStarted.signal()
            releaseBlockedScan.wait()
        }
        return snapshot
    }

    func blockNextScan() {
        lock.lock()
        shouldBlockNextScan = true
        lock.unlock()
    }

    func waitForBlockedScan() -> DispatchTimeoutResult {
        blockedScanStarted.wait(timeout: .now() + 1)
    }

    func releaseBlockedScan() {
        releaseBlockedScan.signal()
    }
}
