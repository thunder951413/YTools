import CommonCrypto
import CryptoKit
import Foundation

/// Incremental Jianguoyun synchronization shared with the Windows build.
/// Each clipboard mutation is one immutable encrypted event; small per-device
/// heads reveal only a sequence number so unchanged clients avoid downloads.
@MainActor
final class ClipboardCloudSyncService {
    struct Result {
        let success: Bool
        let items: [ClipboardHistoryItem]?
        let message: String
    }

    private static let server = URL(string: "https://dav.jianguoyun.com/dav/")!
    private let preferences: AppPreferences
    private let credentialStore = SecureCodableStore(name: "clipboard-cloud-credentials")
    private let stateStore = SecureCodableStore(name: "clipboard-cloud-state")
    private var state: State
    private var createdRemoteRoot: String?

    init(preferences: AppPreferences) {
        self.preferences = preferences
        switch stateStore.load(State.self) {
        case let .loaded(loaded):
            state = loaded
            state.nextSequence = max(1, state.nextSequence)
        default:
            state = State(deviceID: UUID())
            _ = stateStore.save(state)
        }
    }

    var hasCredentials: Bool {
        if case .loaded = credentialStore.load(Credentials.self) { return true }
        return false
    }

    func saveCredentials(username: String, appPassword: String, syncPassphrase: String) -> String? {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !appPassword.isEmpty,
              syncPassphrase.count >= 12 else {
            return "请填写坚果云用户名、应用密码和至少 12 个字符的同步口令。"
        }
        guard credentialStore.save(Credentials(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            appPassword: appPassword,
            syncPassphrase: syncPassphrase
        )) else {
            return "无法加密保存坚果云凭据。"
        }
        return nil
    }

    func publishChangedItem(_ item: ClipboardHistoryItem) async -> Result {
        guard preferences.clipboardCloudSyncEnabled else {
            return Result(success: true, items: nil, message: "")
        }
        enqueue(.upsert(sequence: nextSequence(), deviceID: state.deviceID, item: item))
        return await synchronize(localItems: [], pullRemote: false)
    }

    func publishDeleted(_ ids: [UUID]) async -> Result {
        guard preferences.clipboardCloudSyncEnabled else {
            return Result(success: true, items: nil, message: "")
        }
        let unique = Array(Set(ids))
        guard !unique.isEmpty else {
            return Result(success: true, items: nil, message: "")
        }
        enqueue(.delete(sequence: nextSequence(), deviceID: state.deviceID, ids: unique, timestamp: Date()))
        return await synchronize(localItems: [], pullRemote: false)
    }

    func synchronize(localItems: [ClipboardHistoryItem]) async -> Result {
        await synchronize(localItems: localItems, pullRemote: true)
    }

    private func synchronize(localItems: [ClipboardHistoryItem], pullRemote: Bool) async -> Result {
        guard preferences.clipboardCloudSyncEnabled else {
            return Result(success: true, items: nil, message: "")
        }
        guard case let .loaded(credentials) = credentialStore.load(Credentials.self) else {
            return Result(success: false, items: nil, message: "尚未保存坚果云同步凭据。")
        }

        do {
            let folders = try await ensureFolders(credentials: credentials)
            try await publishPending(folders: folders, credentials: credentials)
            guard pullRemote else {
                return Result(success: true, items: nil, message: "剪贴板变更已加密上传。")
            }
            let events = try await pullChangedEvents(folders: folders, credentials: credentials)
            let merged = apply(events: events, to: localItems)
            return Result(
                success: true,
                items: merged,
                message: events.isEmpty ? "坚果云无新的剪贴板变更。" : "坚果云剪贴板已合并。"
            )
        } catch {
            return Result(success: false, items: nil, message: "坚果云同步失败：\(error.localizedDescription)")
        }
    }

    private func ensureFolders(credentials: Credentials) async throws -> Folders {
        let rootParts = try validatedFolder(preferences.clipboardCloudSyncFolder)
        let root = rootParts.joined(separator: "/")
        let folders = Folders(
            root: root,
            heads: root + "/heads",
            events: root + "/events",
            deviceEvents: root + "/events/" + deviceDirectoryName(state.deviceID)
        )
        guard root != createdRemoteRoot else { return folders }

        var parent = ""
        for part in rootParts {
            try await createFolderIfMissing(parent: parent, name: part, credentials: credentials)
            parent = parent.isEmpty ? part : parent + "/" + part
        }
        try await createFolderIfMissing(parent: parent, name: "heads", credentials: credentials)
        try await createFolderIfMissing(parent: parent, name: "events", credentials: credentials)
        try await createFolderIfMissing(parent: folders.events, name: deviceDirectoryName(state.deviceID), credentials: credentials)
        createdRemoteRoot = root
        return folders
    }

    private func createFolderIfMissing(parent: String, name: String, credentials: Credentials) async throws {
        let response = try await request(method: "MKCOL", path: childPath(parent, name), body: nil, credentials: credentials)
        guard [200, 201, 204, 301, 302, 405].contains(response.status) else {
            throw CloudError.requestFailed(response.status)
        }
    }

    private func publishPending(folders: Folders, credentials: Credentials) async throws {
        let pending = state.pending.sorted { $0.sequence < $1.sequence }
        guard !pending.isEmpty else { return }
        for event in pending {
            let clear = try encoded(event)
            guard clear.count <= 6 * 1_024 * 1_024 else { throw CloudError.eventTooLarge }
            let encrypted = try CloudCryptography.seal(clear, passphrase: credentials.syncPassphrase)
            let response = try await request(
                method: "PUT",
                path: childPath(folders.deviceEvents, eventName(event.sequence)),
                body: encrypted,
                credentials: credentials
            )
            guard [200, 201, 204].contains(response.status) else { throw CloudError.requestFailed(response.status) }
        }

        guard let latest = pending.last?.sequence else { return }
        let head = Head(version: 2, deviceID: state.deviceID, lastSequence: latest, updatedAt: Date())
        let response = try await request(
            method: "PUT",
            path: childPath(folders.heads, headName(state.deviceID)),
            body: try encoded(head),
            credentials: credentials
        )
        guard [200, 201, 204].contains(response.status) else { throw CloudError.requestFailed(response.status) }
        state.knownSequences[state.deviceID] = latest
        state.pending.removeAll { $0.sequence <= latest }
        saveState()
    }

    private func pullChangedEvents(folders: Folders, credentials: Credentials) async throws -> [Event] {
        let listed = try await request(method: "PROPFIND", path: folders.heads, body: Data("<propfind xmlns=\"DAV:\"><propname/></propfind>".utf8), credentials: credentials, depth: "1")
        guard listed.status == 207 else { throw CloudError.requestFailed(listed.status) }
        let names = XMLHrefParser.hrefs(in: listed.data).compactMap { URL(string: $0)?.lastPathComponent ?? URL(fileURLWithPath: $0).lastPathComponent }
            .filter { $0.hasSuffix(".head") }
        var events: [Event] = []
        for name in Set(names) {
            let headData = try await download(path: childPath(folders.heads, name), credentials: credentials, limit: 4 * 1_024)
            let head = try decoded(Head.self, from: headData)
            guard head.version == 2, !isZeroDeviceID(head.deviceID), head.lastSequence >= 0 else { throw CloudError.invalidHead }
            let known = state.knownSequences[head.deviceID] ?? 0
            guard head.lastSequence > known else { continue }
            let eventFolder = childPath(folders.events, deviceDirectoryName(head.deviceID))
            for sequence in (known + 1)...head.lastSequence {
                let encrypted = try await download(path: childPath(eventFolder, eventName(sequence)), credentials: credentials, limit: 6 * 1_024 * 1_024)
                let event = try decoded(Event.self, from: CloudCryptography.open(encrypted, passphrase: credentials.syncPassphrase))
                guard event.sequence == sequence, event.deviceID == head.deviceID else { throw CloudError.invalidEvent }
                events.append(event)
            }
            state.knownSequences[head.deviceID] = head.lastSequence
        }
        if !events.isEmpty { saveState() }
        return events
    }

    private func download(path: String, credentials: Credentials, limit: Int) async throws -> Data {
        let response = try await request(method: "GET", path: path, body: nil, credentials: credentials)
        guard response.status == 200 else { throw CloudError.requestFailed(response.status) }
        guard response.data.count <= limit else { throw CloudError.responseTooLarge }
        return response.data
    }

    private func request(method: String, path: String, body: Data?, credentials: Credentials, depth: String? = nil) async throws -> (status: Int, data: Data) {
        let url = try remoteURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 45
        request.setValue("Basic " + Data("\(credentials.username):\(credentials.appPassword)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        request.setValue("YTools", forHTTPHeaderField: "User-Agent")
        if let depth { request.setValue(depth, forHTTPHeaderField: "Depth") }
        if method == "PROPFIND" { request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type") }
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudError.invalidResponse }
        return (http.statusCode, data)
    }

    private func remoteURL(_ path: String) throws -> URL {
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && !$0.contains("..") }) else { throw CloudError.invalidPath }
        return parts.reduce(Self.server) { $0.appendingPathComponent($1, isDirectory: false) }
    }

    private func apply(events: [Event], to local: [ClipboardHistoryItem]) -> [ClipboardHistoryItem] {
        var items = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var tombstones: [UUID: Date] = [:]
        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            if event.kind == .delete {
                event.deletedIDs.forEach { id in tombstones[id] = event.timestamp; items.removeValue(forKey: id) }
                continue
            }
            guard let item = event.item?.item else { continue }
            if let deleted = tombstones[item.id], item.effectiveUpdatedAt <= deleted { continue }
            if let prior = items[item.id], prior.effectiveUpdatedAt >= item.effectiveUpdatedAt { continue }
            items[item.id] = item
        }
        return items.values.sorted { $0.pinned != $1.pinned ? $0.pinned : $0.createdAt > $1.createdAt }
    }

    private func nextSequence() -> Int64 {
        defer { state.nextSequence += 1 }
        return state.nextSequence
    }

    private func enqueue(_ event: Event) {
        state.pending.append(event)
        saveState()
    }

    private func saveState() { _ = stateStore.save(state) }

    private func validatedFolder(_ value: String) throws -> [String] {
        let parts = value.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
        guard !parts.isEmpty, parts.count <= 4, parts.allSatisfy({ part in
            !part.isEmpty && part.count <= 64 && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") }
        }) else { throw CloudError.invalidPath }
        return parts
    }

    private func childPath(_ parent: String, _ child: String) -> String { parent.isEmpty ? child : parent + "/" + child }
    private func eventName(_ sequence: Int64) -> String { String(format: "%020lld.enc", sequence) }
    private func deviceDirectoryName(_ deviceID: UUID) -> String { deviceID.uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
    private func headName(_ deviceID: UUID) -> String { deviceDirectoryName(deviceID) + ".head" }
    private func isZeroDeviceID(_ deviceID: UUID) -> Bool { deviceID.uuidString == "00000000-0000-0000-0000-000000000000" }
    private func encoded<Value: Encodable>(_ value: Value) throws -> Data { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return try encoder.encode(value) }
    private func decoded<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let string = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            if let date = fractional.date(from: string) ?? plain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date.")
        }
        return try decoder.decode(type, from: data)
    }

    private struct Credentials: Codable { let username: String; let appPassword: String; let syncPassphrase: String }
    private struct State: Codable { let deviceID: UUID; var nextSequence: Int64 = 1; var knownSequences: [UUID: Int64] = [:]; var pending: [Event] = [] }
    private struct Folders { let root: String; let heads: String; let events: String; let deviceEvents: String }
    private struct Head: Codable { let version: Int; let deviceID: UUID; let lastSequence: Int64; let updatedAt: Date
        enum CodingKeys: String, CodingKey { case version = "Version", deviceID = "DeviceId", lastSequence = "LastSequence", updatedAt = "UpdatedAt" }
    }
    private enum EventKind: Int, Codable { case upsert, delete }
    private struct Event: Codable {
        let sequence: Int64; let deviceID: UUID; let kind: EventKind; let timestamp: Date; let item: Record?; let deletedIDs: [UUID]
        enum CodingKeys: String, CodingKey { case sequence = "Sequence", deviceID = "DeviceId", kind = "Kind", timestamp = "Timestamp", item = "Item", deletedIDs = "DeletedIds" }
        static func upsert(sequence: Int64, deviceID: UUID, item: ClipboardHistoryItem) -> Event { Event(sequence: sequence, deviceID: deviceID, kind: .upsert, timestamp: item.effectiveUpdatedAt, item: Record(item), deletedIDs: []) }
        static func delete(sequence: Int64, deviceID: UUID, ids: [UUID], timestamp: Date) -> Event { Event(sequence: sequence, deviceID: deviceID, kind: .delete, timestamp: timestamp, item: nil, deletedIDs: ids) }
    }
    private struct Record: Codable {
        let id: UUID; let kind: Int; let payload: [String]; let createdAt: Date; let updatedAt: Date; let sourceApplication: String?; let binaryData: Data?; let contentHash: String?; let isPinned: Bool
        enum CodingKeys: String, CodingKey { case id = "Id", kind = "Kind", payload = "Payload", createdAt = "CreatedAt", updatedAt = "UpdatedAt", sourceApplication = "SourceApplication", binaryData = "BinaryData", contentHash = "ContentHash", isPinned = "IsPinned" }
        init(_ item: ClipboardHistoryItem) { id = item.id; kind = item.kind == .text ? 0 : item.kind == .files ? 1 : 2; payload = item.payload; createdAt = item.createdAt; updatedAt = item.effectiveUpdatedAt; sourceApplication = item.sourceApplication; binaryData = item.binaryData; contentHash = item.contentHash; isPinned = item.pinned }
        var item: ClipboardHistoryItem? { guard let type = [ClipboardHistoryItem.Kind.text, .files, .image][safe: kind] else { return nil }; return ClipboardHistoryItem(id: id, kind: type, payload: payload, createdAt: createdAt, sourceApplication: sourceApplication, binaryData: binaryData, contentHash: contentHash, isPinned: isPinned, updatedAt: updatedAt) }
    }
    private enum CloudError: LocalizedError { case invalidPath, invalidResponse, invalidHead, invalidEvent, requestFailed(Int), responseTooLarge, eventTooLarge
        var errorDescription: String? { switch self { case .invalidPath: "坚果云同步目录不安全。"; case .invalidResponse: "坚果云返回了无效响应。"; case .invalidHead: "坚果云同步标记格式不正确。"; case .invalidEvent: "坚果云同步记录与标记不一致。"; case let .requestFailed(status): "坚果云返回 HTTP \(status)。"; case .responseTooLarge: "坚果云同步数据超过允许大小。"; case .eventTooLarge: "单条剪贴板同步记录超过 6 MB 上限。" } }
    }
}

enum CloudCryptography {
    private static let magic = Data("YTCE2".utf8)
    static func seal(_ clear: Data, passphrase: String) throws -> Data {
        let salt = randomData(count: 16)
        let key = try deriveKey(passphrase: passphrase, salt: salt)
        let box = try AES.GCM.seal(clear, using: SymmetricKey(data: key))
        guard let combined = box.combined else { throw CryptoError.invalidEnvelope }
        return magic + salt + combined
    }
    static func open(_ encrypted: Data, passphrase: String) throws -> Data {
        guard encrypted.count >= magic.count + 16 + 28, encrypted.prefix(magic.count) == magic else { throw CryptoError.invalidEnvelope }
        let salt = encrypted.subdata(in: magic.count..<(magic.count + 16))
        let key = try deriveKey(passphrase: passphrase, salt: salt)
        let box = try AES.GCM.SealedBox(combined: encrypted.dropFirst(magic.count + 16))
        return try AES.GCM.open(box, using: SymmetricKey(data: key))
    }
    private static func deriveKey(passphrase: String, salt: Data) throws -> Data {
        var key = [UInt8](repeating: 0, count: 32)
        let password = Array(passphrase.utf8)
        let status = password.withUnsafeBytes { passwordBytes in salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self), password.count, saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000, &key, key.count)
        } }
        guard status == kCCSuccess else { throw CryptoError.keyDerivationFailed }
        return Data(key)
    }
    private static func randomData(count: Int) -> Data { Data((0..<count).map { _ in UInt8.random(in: .min ... .max) }) }
    private enum CryptoError: LocalizedError { case invalidEnvelope, keyDerivationFailed
        var errorDescription: String? { self == .invalidEnvelope ? "同步密文格式无效。" : "同步密钥派生失败。" }
    }
}

private final class XMLHrefParser: NSObject, XMLParserDelegate {
    private var values: [String] = []; private var reading = false; private var current = ""
    static func hrefs(in data: Data) -> [String] { let parser = XMLParser(data: data); let delegate = XMLHrefParser(); parser.delegate = delegate; return parser.parse() ? delegate.values : [] }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) { if elementName == "href" { reading = true; current = "" } }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if reading { current += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { if elementName == "href" { values.append(current); reading = false } }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
