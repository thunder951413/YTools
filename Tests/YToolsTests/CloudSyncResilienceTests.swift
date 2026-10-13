import Foundation
import XCTest
@testable import YTools

final class CloudSyncResilienceTests: XCTestCase {
    func testDerivedKeyCacheDerivesOncePerSaltAndReusesSealingSalt() throws {
        let cache = DerivedKeyCache()
        var derivations = 0
        let derive: (String, Data) throws -> Data = { _, salt in
            derivations += 1
            return salt + salt
        }

        let first = try cache.sealingKey(passphrase: "passphrase-one", derive: derive)
        let second = try cache.sealingKey(passphrase: "passphrase-one", derive: derive)
        XCTAssertEqual(first.salt, second.salt)
        XCTAssertEqual(first.salt.count, 16)
        XCTAssertEqual(derivations, 1)

        let other = try cache.sealingKey(passphrase: "passphrase-two", derive: derive)
        XCTAssertNotEqual(other.salt, first.salt)
        XCTAssertEqual(derivations, 2)

        _ = try cache.key(passphrase: "passphrase-one", salt: first.salt, derive: derive)
        XCTAssertEqual(derivations, 2, "Opening an envelope sealed in this process must not re-run PBKDF2")
        _ = try cache.key(passphrase: "passphrase-one", salt: Data(repeating: 1, count: 16), derive: derive)
        XCTAssertEqual(derivations, 3)
    }

    func testEnvelopesShareSaltButUseFreshNoncesAndStayDecryptable() throws {
        let clear = Data("same clear text".utf8)
        let first = try CloudCryptography.seal(clear, passphrase: "shared-sync-secret")
        let second = try CloudCryptography.seal(clear, passphrase: "shared-sync-secret")
        XCTAssertEqual(first.subdata(in: 5..<21), second.subdata(in: 5..<21), "One sealing salt per process")
        XCTAssertNotEqual(first.subdata(in: 21..<33), second.subdata(in: 21..<33), "Every envelope needs its own nonce")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try CloudCryptography.open(first, passphrase: "shared-sync-secret"), clear)
        XCTAssertEqual(try CloudCryptography.open(second, passphrase: "shared-sync-secret"), clear)
    }

    func testOneBrokenDeviceDoesNotBlockOthersAndPoisonEventIsEventuallySkipped() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ytools-resilience-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 7, count: 32)
        let transport = try ResilienceFixtureTransport()
        let service = ClipboardCloudSyncService(
            credentialStore: SecureCodableStore(fileURL: directory.appendingPathComponent("credentials.enc")) { _ in key },
            stateStore: SecureCodableStore(fileURL: directory.appendingPathComponent("state.enc")) { _ in key },
            transport: transport)
        let credentialError = await service.saveCredentials(username: "test", appPassword: "test", syncPassphrase: "fixture-secret-long")
        XCTAssertNil(credentialError)
        let configuration = ClipboardCloudSyncService.Configuration(enabled: true, folder: "Review")

        // Round 1: the healthy device arrives even though one device has a
        // missing event and another uses a different passphrase.
        let first = await service.synchronize(configuration: configuration)
        XCTAssertTrue(first.success, first.message)
        XCTAssertEqual(first.events?.map(\.deviceID), [ResilienceFixtureTransport.healthy])
        XCTAssertTrue(first.message.contains("无法解密"), first.message)
        try await service.acknowledge(first.events ?? [])

        // Rounds 2-3: the missing event is retried, then quarantined so the
        // next event from the same device is delivered.
        let second = await service.synchronize(configuration: configuration)
        XCTAssertTrue(second.success, second.message)
        XCTAssertNil(second.events)
        let third = await service.synchronize(configuration: configuration)
        XCTAssertTrue(third.success, third.message)
        XCTAssertEqual(third.events?.map(\.sequence), [2])
        XCTAssertEqual(third.events?.map(\.deviceID), [ResilienceFixtureTransport.poisoned])
        let undecryptableAttempts = await transport.undecryptableDownloads
        XCTAssertEqual(undecryptableAttempts, 3, "Undecryptable devices are retried, never skipped")
    }

    func testTransientSaveFailureDoesNotLockStoreForTheSession() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ytools-store-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 3, count: 32)
        let keychain = FlakyKeychain()
        let store = SecureCodableStore(fileURL: directory.appendingPathComponent("store.enc")) { _ in
            if keychain.failing { throw CocoaError(.fileReadUnknown) }
            return key
        }
        XCTAssertTrue(store.save(["one"]))
        keychain.failing = true
        XCTAssertFalse(store.save(["two"]))
        keychain.failing = false
        XCTAssertTrue(store.save(["three"]), "A transient failure must allow a later retry")
        guard case let .loaded(value) = store.load([String].self) else { return XCTFail("Expected loaded store") }
        XCTAssertEqual(value, ["three"])
    }
}

private final class FlakyKeychain: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var failing: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

private actor ResilienceFixtureTransport: ClipboardCloudTransport {
    static let healthy = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let poisoned = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    static let foreign = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!

    private var files: [String: Data] = [:]
    private var heads: [String: Int64] = [:]
    private(set) var undecryptableDownloads = 0

    init() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        func event(_ device: UUID, _ sequence: Int64, passphrase: String) throws -> Data {
            let item = ClipboardHistoryItem(id: UUID(), kind: .text, payload: ["synthetic \(sequence)"], createdAt: Date(), sourceApplication: nil)
            return try CloudCryptography.seal(
                encoder.encode(ClipboardCloudSyncService.Event.upsert(sequence: sequence, deviceID: device, item: item)),
                passphrase: passphrase)
        }
        files[Self.name(Self.healthy, 1)] = try event(Self.healthy, 1, passphrase: "fixture-secret-long")
        // Sequence 1 of the poisoned device is missing (404); sequence 2 is fine.
        files[Self.name(Self.poisoned, 2)] = try event(Self.poisoned, 2, passphrase: "fixture-secret-long")
        files[Self.name(Self.foreign, 1)] = try event(Self.foreign, 1, passphrase: "a-different-passphrase")
        heads = [Self.directory(Self.healthy): 1, Self.directory(Self.poisoned): 2, Self.directory(Self.foreign): 1]
    }

    private static func directory(_ id: UUID) -> String { id.uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
    private static func name(_ id: UUID, _ sequence: Int64) -> String { directory(id) + "/" + String(format: "%020lld.enc", sequence) }

    func send(_ request: URLRequest, maximumBytes: Int) async throws -> (status: Int, data: Data) {
        let url = request.url!
        switch request.httpMethod {
        case "MKCOL", "PUT":
            return (201, Data())
        case "PROPFIND":
            let hrefs = heads.keys.sorted().map { "<d:response><d:href>/dav/Review/heads/\($0).head</d:href></d:response>" }.joined()
            return (207, Data("<d:multistatus xmlns:d=\"DAV:\">\(hrefs)</d:multistatus>".utf8))
        case "GET":
            if url.path.hasSuffix(".head") {
                let raw = url.lastPathComponent.replacingOccurrences(of: ".head", with: "")
                guard let sequence = heads[raw] else { return (404, Data()) }
                let id = [Self.healthy, Self.poisoned, Self.foreign].first { Self.directory($0) == raw }!
                return (200, Data("{\"Version\":2,\"DeviceId\":\"\(id.uuidString)\",\"LastSequence\":\(sequence),\"UpdatedAt\":\"2026-10-13T12:00:00Z\"}".utf8))
            }
            let key = url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent
            if url.deletingLastPathComponent().lastPathComponent == Self.directory(Self.foreign) { undecryptableDownloads += 1 }
            guard let data = files[key] else { return (404, Data()) }
            return (200, data)
        default:
            throw URLError(.unsupportedURL)
        }
    }
}
