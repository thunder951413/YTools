import AppKit
import CryptoKit
import Foundation
import XCTest
@testable import YTools

@MainActor
final class ClipboardReliabilityTests: XCTestCase {
    private let device = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    func testExplicitClearCanRecoverUnreadableHistoryAndDrainBeforeExit() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 2, count: 32)
        let store = ClipboardHistoryStore(rootURL: directory, keyProvider: { _ in key })
        let manifest = directory.appendingPathComponent("clipboard-vault-v2/manifest.enc")
        try Data("corrupt fixture".utf8).write(to: manifest)
        let suite = "ytools-clipboard-clear-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults, launchAtLoginService: FixtureLoginService())
        let pasteboard = NSPasteboard(name: .init("ytools-test-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let service = ClipboardCloudSyncService(
            credentialStore: SecureCodableStore(fileURL: directory.appendingPathComponent("credentials.enc")) { _ in key },
            stateStore: SecureCodableStore(fileURL: directory.appendingPathComponent("state.enc")) { _ in key }, transport: PausedCloudTransport())
        let manager = ClipboardHistoryManager(preferences: preferences,
            persistence: ClipboardPersistenceService { ClipboardHistoryStore(rootURL: directory, keyProvider: { _ in key }) },
            cloudSync: service, pasteboard: pasteboard, monitorsClipboard: false)
        await manager.waitUntilLoaded()
        XCTAssertNotNil(manager.storageError)
        XCTAssertEqual(try Data(contentsOf: manifest), Data("corrupt fixture".utf8))
        manager.clear()
        manager.clear() // Repeated request while clearing must not replace the first job.
        await manager.flushPendingChanges()
        XCTAssertFalse(manager.isClearing)
        XCTAssertNil(manager.storageError)
        if case .missing = store.load() {} else { XCTFail("Explicit clear should remove the unreadable ciphertext") }
    }

    func testClipboardShutdownDrainsHistoryAndDeletionOutbox() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 5, count: 32)
        let now = Date()
        let entry = ClipboardHistoryItem(id: UUID(), kind: .text, payload: ["synthetic"], createdAt: now, sourceApplication: nil)
        _ = try ClipboardHistoryStore(rootURL: directory, keyProvider: { _ in key }).persist([entry])
        let suite = "ytools-clipboard-shutdown-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults, launchAtLoginService: FixtureLoginService())
        preferences.clipboardCloudSyncEnabled = true
        let stateURL = directory.appendingPathComponent("state.enc")
        let service = ClipboardCloudSyncService(
            credentialStore: SecureCodableStore(fileURL: directory.appendingPathComponent("credentials.enc")) { _ in key },
            stateStore: SecureCodableStore(fileURL: stateURL) { _ in key }, transport: PausedCloudTransport())
        _ = await service.saveCredentials(username: "fixture", appPassword: "fixture", syncPassphrase: "fixture-secret-long")
        let pasteboard = NSPasteboard(name: .init("ytools-test-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardHistoryManager(preferences: preferences,
            persistence: ClipboardPersistenceService { ClipboardHistoryStore(rootURL: directory, keyProvider: { _ in key }) },
            cloudSync: service, pasteboard: pasteboard, monitorsClipboard: false)
        await manager.waitUntilLoaded()
        manager.togglePinned(entry)
        manager.delete(entry)
        await manager.flushPendingChanges()
        let reopened = ClipboardHistoryStore(rootURL: directory, keyProvider: { _ in key })
        guard case let .loaded(items, _) = reopened.load() else { return XCTFail("Expected encrypted empty history") }
        XCTAssertTrue(items.isEmpty)
        if case let .loaded(snapshot) = SecureCodableStore(fileURL: stateURL, keyProvider: { _ in key }).load(OutboxSnapshot.self) {
            XCTAssertEqual(snapshot.pending.count, 2)
            XCTAssertEqual(snapshot.pending.last?.deletedIDs, [entry.id])
        } else { XCTFail("Shutdown must drain the deletion outbox") }
    }

    func testHistoryCopyPromotesOnlyAfterSuccessfulWriteAndMissingImageReportsFailure() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 4, count: 32)
        let originalDate = Date().addingTimeInterval(-60)
        let entry = ClipboardHistoryItem(id: UUID(), kind: .text, payload: ["synthetic-copy"], createdAt: originalDate, sourceApplication: nil)
        _ = try ClipboardHistoryStore(rootURL: directory, keyProvider: { _ in key }).persist([entry])
        let suite = "ytools-clipboard-copy-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults, launchAtLoginService: FixtureLoginService())
        let pasteboard = NSPasteboard(name: .init("ytools-test-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let service = ClipboardCloudSyncService(
            credentialStore: SecureCodableStore(fileURL: directory.appendingPathComponent("credentials.enc")) { _ in key },
            stateStore: SecureCodableStore(fileURL: directory.appendingPathComponent("state.enc")) { _ in key }, transport: PausedCloudTransport())
        let manager = ClipboardHistoryManager(preferences: preferences,
            persistence: ClipboardPersistenceService { ClipboardHistoryStore(rootURL: directory, keyProvider: { _ in key }) },
            cloudSync: service, pasteboard: pasteboard, monitorsClipboard: false)
        await manager.waitUntilLoaded()
        let copied = await manager.copySelected()
        XCTAssertTrue(copied)
        XCTAssertEqual(pasteboard.string(forType: .string), "synthetic-copy")
        XCTAssertGreaterThan(try XCTUnwrap(manager.items.first?.createdAt), originalDate)
        let missing = ClipboardHistoryItem(id: UUID(), kind: .image, payload: ["missing"], createdAt: Date(), sourceApplication: nil,
            binaryData: Data([1, 2, 3]))
        let failed = await manager.copy(missing)
        XCTAssertFalse(failed, "A thumbnail must never substitute for a missing original")
        XCTAssertNotNil(manager.copyError)
        XCTAssertEqual(pasteboard.string(forType: .string), "synthetic-copy")
        await manager.flushPendingChanges()
        guard case let .loaded(items, _) = ClipboardHistoryStore(rootURL: directory, keyProvider: { _ in key }).load() else {
            return XCTFail("Expected promoted ciphertext history")
        }
        XCTAssertGreaterThan(try XCTUnwrap(items.first?.createdAt), originalDate)
    }

    func testPagingPinnedFilterAndOlderQueriesUseCompleteHistory() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 6, count: 32)
        let now = Date()
        let entries = (0..<251).map { index in
            ClipboardHistoryItem(id: UUID(), kind: .text, payload: ["fixture-record-\(index)"],
                createdAt: now.addingTimeInterval(-Double(index)), sourceApplication: index == 250 ? "Older Fixture App" : nil,
                isPinned: index == 250)
        }
        _ = try ClipboardHistoryStore(rootURL: directory, keyProvider: { _ in key }).persist(entries)
        let suite = "ytools-paging-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults, launchAtLoginService: FixtureLoginService())
        let pasteboard = NSPasteboard(name: .init("ytools-test-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardHistoryManager(preferences: preferences,
            persistence: ClipboardPersistenceService { ClipboardHistoryStore(rootURL: directory, keyProvider: { _ in key }) },
            cloudSync: ClipboardCloudSyncService(
                credentialStore: SecureCodableStore(fileURL: directory.appendingPathComponent("credentials.enc")) { _ in key },
                stateStore: SecureCodableStore(fileURL: directory.appendingPathComponent("state.enc")) { _ in key },
                transport: PausedCloudTransport()), pasteboard: pasteboard, monitorsClipboard: false)
        await manager.waitUntilLoaded()
        XCTAssertEqual(manager.filteredItems.count, 100)
        XCTAssertEqual(manager.totalMatches, 251)
        manager.selectedIndex = 70
        let selectedID = manager.filteredItems[70].id
        manager.loadMore()
        XCTAssertEqual(manager.filteredItems.count, 200)
        XCTAssertEqual(manager.filteredItems[manager.selectedIndex].id, selectedID)
        manager.loadMore()
        XCTAssertEqual(manager.filteredItems.count, 251)
        XCTAssertFalse(manager.hasMore)
        manager.filter = .pinned
        XCTAssertEqual(manager.filteredItems.map(\.id), [entries[250].id])
        manager.filter = .all
        XCTAssertEqual(manager.filteredItems.count, 100, "Changing filters resets the page")
        manager.loadMore() // Keep selectedIndex at 0 to catch a page-reset regression.
        manager.query = "fixture-record-249"
        XCTAssertEqual(manager.selectedText, "fixture-record-249")
        XCTAssertEqual(manager.totalMatches, 1)
        manager.query = "Older Fixture App"
        XCTAssertEqual(manager.selectedText, "fixture-record-250", "Search includes sources outside the first page")
        manager.query = ""
        XCTAssertEqual(manager.filteredItems.count, 100)
        await manager.flushPendingChanges()
    }

    func testWebDAVHrefsSupportNamespacesWhitespaceAndEscapes() throws {
        for xml in [
            "<multistatus><response><href> /dav/Review/a&amp;b.head </href></response></multistatus>",
            "<multistatus xmlns=\"DAV:\"><response><href> /dav/Review/a&amp;b.head </href></response></multistatus>",
            "<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href> /dav/Review/a&amp;b.head </d:href></d:response></d:multistatus>",
            "<server:multistatus xmlns:server=\"DAV:\"><server:response><server:href> /dav/Review/a&amp;b.head </server:href></server:response></server:multistatus>"
        ] {
            XCTAssertEqual(try XMLHrefParser.hrefs(in: Data(xml.utf8)), ["/dav/Review/a&b.head"])
        }
        XCTAssertEqual(try XMLHrefParser.hrefs(in: Data("<multistatus xmlns:x=\"urn:other\"><x:href>unrelated.head</x:href></multistatus>".utf8)), [])
    }

    func testMalformedWebDAVXMLIsReportedRatherThanAnEmptyDirectory() {
        XCTAssertThrowsError(try XMLHrefParser.hrefs(in: Data("<d:multistatus xmlns:d=\"DAV:\"><d:href>truncated".utf8)))
    }

    func testOutboxRemainsDurableWhileUploadIsSuspended() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 6, count: 32)
        let stateURL = directory.appendingPathComponent("state.enc")
        let transport = PausedCloudTransport()
        let service = ClipboardCloudSyncService(
            credentialStore: SecureCodableStore(fileURL: directory.appendingPathComponent("credentials.enc")) { _ in key },
            stateStore: SecureCodableStore(fileURL: stateURL) { _ in key }, transport: transport)
        _ = await service.saveCredentials(username: "test", appPassword: "test", syncPassphrase: "fixture-secret-long")
        let config = ClipboardCloudSyncService.Configuration(enabled: true, folder: "Review")
        let first = item(id: UUID(), updated: 100)
        let firstQueued = await service.enqueueChangedItem(first, configuration: config)
        XCTAssertTrue(firstQueued.success, firstQueued.message)
        let upload = Task { await service.uploadPending(configuration: config) }
        await transport.waitUntilPaused()
        let second = item(id: UUID(), updated: 200)
        let secondQueued = await service.enqueueChangedItem(second, configuration: config)
        let deleted = await service.enqueueDeleted([first.id], timestamp: Date(timeIntervalSince1970: 300), configuration: config)
        XCTAssertTrue(secondQueued.success, secondQueued.message)
        XCTAssertTrue(deleted.success, deleted.message)
        let reopened = SecureCodableStore(fileURL: stateURL) { _ in key }
        if case let .loaded(snapshot) = reopened.load(OutboxSnapshot.self) {
            XCTAssertEqual(snapshot.nextSequence, 4)
            XCTAssertEqual(snapshot.pending.map(\.sequence), [1, 2, 3])
            XCTAssertEqual(snapshot.pending.last?.deletedIDs, [first.id])
        } else { XCTFail("Outbox must be durable before the network resumes") }
        await transport.resume()
        let result = await upload.value
        XCTAssertTrue(result.success, result.message)
        if case let .loaded(snapshot) = reopened.load(OutboxSnapshot.self) {
            XCTAssertEqual(snapshot.pending.map(\.sequence), [2, 3], "Finishing the older upload must preserve newly queued changes")
        } else { XCTFail("Expected saved remaining outbox") }
    }

    private func item(id: UUID, updated: TimeInterval, pinned: Bool = false) -> ClipboardHistoryItem {
        ClipboardHistoryItem(id: id, kind: .text, payload: ["fixture"], createdAt: Date(timeIntervalSince1970: 100),
            sourceApplication: nil, isPinned: pinned, updatedAt: Date(timeIntervalSince1970: updated))
    }

    func testPersistedDeletionRejectsDelayedUpsertAcrossPulls() {
        let id = UUID()
        let deleted = [id: Date(timeIntervalSince1970: 200)]
        let event = ClipboardCloudSyncService.Event.upsert(sequence: 1, deviceID: device, item: item(id: id, updated: 150))
        XCTAssertTrue(ClipboardCloudSyncService.apply(events: [event], to: [], deleted: deleted).isEmpty)
    }

    func testOldDeleteCannotRemoveNewerLocalEdit() {
        let id = UUID()
        let event = ClipboardCloudSyncService.Event.delete(sequence: 1, deviceID: device, ids: [id], timestamp: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(ClipboardCloudSyncService.apply(events: [event], to: [item(id: id, updated: 300)]).count, 1)
    }

    func testMergeUsesCurrentItemsAndConvergesAtEqualTimestamp() {
        let id = UUID()
        let extra = item(id: UUID(), updated: 400)
        let plain = item(id: id, updated: 300)
        let pinned = item(id: id, updated: 300, pinned: true)
        let event = ClipboardCloudSyncService.Event.upsert(sequence: 1, deviceID: device, item: pinned)
        let forward = ClipboardCloudSyncService.apply(events: [event], to: [plain, extra])
        let reverse = ClipboardCloudSyncService.apply(events: [.upsert(sequence: 2, deviceID: device, item: plain)], to: [pinned, extra])
        XCTAssertEqual(forward, reverse)
        XCTAssertTrue(forward.contains(extra))
    }

    func testUnreadableArchiveCannotBeOverwrittenOrRekeyed() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("locked.enc")
        let bytes = Data("unreadable encrypted archive".utf8)
        try bytes.write(to: url)
        let store = SecureCodableStore(fileURL: url) { create in
            if create { XCTFail("Existing ciphertext must never request a new key") }
            throw CocoaError(.fileReadNoPermission)
        }
        if case .unavailable = store.load([String].self) {} else { XCTFail("Expected unavailable") }
        XCTAssertFalse(store.save(["replacement"]))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testAuthenticatedButUndecodableArchiveStaysLocked() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("schema.enc")
        let key = Data(repeating: 7, count: 32)
        let box = try AES.GCM.seal(Data("{\"wrong\":true}".utf8), using: SymmetricKey(data: key))
        let bytes = try XCTUnwrap(box.combined)
        try bytes.write(to: url)
        let store = SecureCodableStore(fileURL: url) { _ in key }
        if case .corrupted = store.load([String].self) {} else { XCTFail("Expected corrupted") }
        XCTAssertFalse(store.save(["replacement"]))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testFailedPullDoesNotAdvanceCursorAndInboxSurvivesRestartUntilAcknowledged() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 9, count: 32)
        let credentials = SecureCodableStore(fileURL: directory.appendingPathComponent("credentials.enc")) { _ in key }
        let stateURL = directory.appendingPathComponent("state.enc")
        let state = SecureCodableStore(fileURL: stateURL) { _ in key }
        let transport = try CloudFixtureTransport()
        let service = ClipboardCloudSyncService(credentialStore: credentials, stateStore: state, transport: transport)
        let error = await service.saveCredentials(username: "test", appPassword: "test", syncPassphrase: "fixture-secret-long")
        XCTAssertNil(error)
        let configuration = ClipboardCloudSyncService.Configuration(enabled: true, folder: "Review")
        let failed = await service.synchronize(configuration: configuration)
        XCTAssertFalse(failed.success)
        let pendingAfterFailure = await service.pendingEvents()
        XCTAssertTrue(pendingAfterFailure.isEmpty)
        await transport.allowSecondDevice()
        let success = await service.synchronize(configuration: configuration)
        XCTAssertTrue(success.success, success.message)
        XCTAssertEqual(success.events?.count, 2)
        let downloads = await transport.firstDownloads
        XCTAssertEqual(downloads, 2, "First device must be retried after the second device failed")
        let reopened = ClipboardCloudSyncService(credentialStore: credentials,
            stateStore: SecureCodableStore(fileURL: stateURL) { _ in key }, transport: transport)
        let pending = await reopened.pendingEvents()
        XCTAssertEqual(pending.count, 2, "Receiving a batch must not acknowledge history persistence")
        try await reopened.acknowledge(pending)
        let empty = await reopened.pendingEvents()
        XCTAssertTrue(empty.isEmpty)
    }

    func testConcurrentPublishesKeepHeadMonotonic() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 8, count: 32)
        let transport = try CloudFixtureTransport()
        let service = ClipboardCloudSyncService(
            credentialStore: SecureCodableStore(fileURL: directory.appendingPathComponent("credentials.enc")) { _ in key },
            stateStore: SecureCodableStore(fileURL: directory.appendingPathComponent("state.enc")) { _ in key }, transport: transport)
        _ = await service.saveCredentials(username: "test", appPassword: "test", syncPassphrase: "fixture-secret-long")
        let first = item(id: UUID(), updated: 100)
        let second = item(id: UUID(), updated: 200)
        let config = ClipboardCloudSyncService.Configuration(enabled: true, folder: "Review")
        async let a = service.publishChangedItem(first, configuration: config)
        async let b = service.publishChangedItem(second, configuration: config)
        let results = await [a, b]
        XCTAssertTrue(results.allSatisfy(\.success))
        let heads = await transport.publishedHeads
        XCTAssertEqual(heads, [1, 2])
    }

    func testPartiallyCorruptedClipboardVaultPreservesEveryOriginalFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 3, count: 32)
        let first = item(id: UUID(), updated: 100)
        let second = item(id: UUID(), updated: 200)
        let initial = ClipboardHistoryStore(rootURL: directory, keyProvider: { _ in key })
        _ = try initial.persist([first, second])
        let vault = directory.appendingPathComponent("clipboard-vault-v2")
        let record = vault.appendingPathComponent("records/\(first.id.uuidString).enc")
        let corrupt = Data("corrupt fixture record".utf8)
        try corrupt.write(to: record)
        let manifest = try Data(contentsOf: vault.appendingPathComponent("manifest.enc"))
        let reopened = ClipboardHistoryStore(rootURL: directory, keyProvider: { _ in key })
        guard case let .loaded(healthy, warning) = reopened.load() else { return XCTFail("Expected partial readable history") }
        XCTAssertEqual(healthy.count, 1)
        XCTAssertNotNil(warning)
        XCTAssertThrowsError(try reopened.persist(healthy))
        XCTAssertEqual(try Data(contentsOf: record), corrupt)
        XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent("manifest.enc")), manifest)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ytools-reliability-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private actor CloudFixtureTransport: ClipboardCloudTransport {
    private let first = "11111111111111111111111111111111"
    private let second = "22222222222222222222222222222222"
    private var failsSecond = true
    private let events: [String: Data]
    private(set) var firstDownloads = 0
    private(set) var publishedHeads: [Int] = []

    init() throws {
        var values: [String: Data] = [:]
        for device in ["11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"] {
            let id = UUID(uuidString: device)!
            let item = ClipboardHistoryItem(id: UUID(), kind: .text, payload: ["synthetic"], createdAt: Date(), sourceApplication: nil)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            values[device.replacingOccurrences(of: "-", with: "")] = try CloudCryptography.seal(
                encoder.encode(ClipboardCloudSyncService.Event.upsert(sequence: 1, deviceID: id, item: item)), passphrase: "fixture-secret-long")
        }
        events = values
    }
    func allowSecondDevice() { failsSecond = false }
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> (status: Int, data: Data) {
        let url = request.url!
        switch request.httpMethod {
        case "MKCOL": return (201, Data())
        case "PUT":
            // Force an actor reentrancy opportunity while a publish is active.
            await Task.yield()
            if url.path.hasSuffix(".head"), let data = request.httpBody,
               let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sequence = object["LastSequence"] as? Int { publishedHeads.append(sequence) }
            return (201, Data())
        case "PROPFIND":
            return (207, Data("<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href>/dav/Review/heads/\(first).head</d:href></d:response><d:response><d:href>/dav/Review/heads/\(second).head</d:href></d:response></d:multistatus>".utf8))
        case "GET":
            if url.path.hasSuffix(".head") {
                let raw = url.lastPathComponent.replacingOccurrences(of: ".head", with: "")
                let id = raw == first ? "11111111-1111-1111-1111-111111111111" : "22222222-2222-2222-2222-222222222222"
                return (200, Data("{\"Version\":2,\"DeviceId\":\"\(id)\",\"LastSequence\":1,\"UpdatedAt\":\"2026-09-06T12:00:00Z\"}".utf8))
            }
            let device = url.deletingLastPathComponent().lastPathComponent
            if device == first { firstDownloads += 1 }
            if device == second && failsSecond { throw URLError(.timedOut) }
            return (200, events[device]!)
        default: throw URLError(.unsupportedURL)
        }
    }
}

private struct OutboxSnapshot: Codable {
    let nextSequence: Int64
    let pending: [ClipboardCloudSyncService.Event]
}

@MainActor
private struct FixtureLoginService: LaunchAtLoginManaging {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}

private actor PausedCloudTransport: ClipboardCloudTransport {
    private var paused = false
    private var pauseWaiter: CheckedContinuation<Void, Never>?
    private var resumeWaiter: CheckedContinuation<Void, Never>?
    func waitUntilPaused() async {
        if !paused { await withCheckedContinuation { pauseWaiter = $0 } }
    }
    func resume() { resumeWaiter?.resume(); resumeWaiter = nil }
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> (status: Int, data: Data) {
        if request.httpMethod == "PUT", !paused {
            paused = true
            await withCheckedContinuation { continuation in
                resumeWaiter = continuation
                pauseWaiter?.resume()
                pauseWaiter = nil
            }
        }
        return (201, Data())
    }
}
