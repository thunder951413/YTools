import CryptoKit
import Foundation
import ImageIO

enum ClipboardStoreLoadResult: Sendable {
    case missing
    case loaded([ClipboardHistoryItem], warning: String?)
    case unavailable(String)
    case corrupted(String)
}

enum ClipboardStoreError: Error, LocalizedError, Sendable {
    case keyUnavailable(String)
    case readFailed(String)
    case corrupted(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case let .keyUnavailable(message), let .readFailed(message),
             let .corrupted(message), let .writeFailed(message): message
        }
    }
}

/// Incremental encrypted clipboard vault.
///
/// The small manifest is rewritten atomically, while immutable record payloads
/// and image thumbnails are encrypted independently. This avoids re-encoding
/// every historical image for each clipboard change.
final class ClipboardHistoryStore {
    private struct Manifest: Codable {
        var version = 2
        var entries: [Entry]
    }

    private struct Entry: Codable {
        let id: UUID
        let kind: ClipboardHistoryItem.Kind
        let displayText: String
        let createdAt: Date
        let sourceApplication: String?
        let contentHash: String
        let encryptedByteCount: Int
        var isPinned: Bool
    }

    private struct Record: Codable {
        let payload: [String]
        let imageData: Data?
    }

    private let keyAccessor = KeychainKeyAccessor(
        service: "com.ztools.native.clipboard-history",
        account: "encryption-key-v1",
        missingKeyMessage: "剪贴板密文存在，但钥匙串密钥缺失；存储保持只读。",
        randomGenerationMessage: "无法生成剪贴板加密密钥。"
    )
    private let legacyFileURL: URL
    private let vaultURL: URL
    private let manifestURL: URL
    private let recordsURL: URL
    private let thumbnailsURL: URL
    private let maximumEncryptedBytes = 200 * 1_024 * 1_024

    init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        // Retain the original storage namespace so the product rename does not
        // orphan an existing encrypted clipboard archive.
        let root = applicationSupport.appendingPathComponent("ZToolsNative", isDirectory: true)
        legacyFileURL = root.appendingPathComponent("clipboard-history.v1.enc")
        vaultURL = root.appendingPathComponent("clipboard-vault-v2", isDirectory: true)
        manifestURL = vaultURL.appendingPathComponent("manifest.enc")
        recordsURL = vaultURL.appendingPathComponent("records", isDirectory: true)
        thumbnailsURL = vaultURL.appendingPathComponent("thumbnails", isDirectory: true)
        try? createVaultDirectories(fileManager: fileManager, root: root)
    }

    func load() -> ClipboardStoreLoadResult {
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            return loadVersion2()
        }
        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else { return .missing }
        switch loadLegacy() {
        case let .loaded(items, _):
            do {
                let migrated = try persist(items, originalImages: Dictionary(
                    uniqueKeysWithValues: items.compactMap { item in
                        item.kind == .image ? item.binaryData.map { (item.id, $0) } : nil
                    }
                ))
                let migratedURL = legacyFileURL.appendingPathExtension("migrated")
                try? FileManager.default.moveItem(at: legacyFileURL, to: migratedURL)
                return .loaded(migrated, warning: "剪贴板历史已迁移到增量加密存储。")
            } catch {
                return .unavailable("旧剪贴板历史读取成功，但迁移失败：\(error.localizedDescription)")
            }
        case .missing:
            return .missing
        case let .unavailable(message):
            return .unavailable(message)
        case let .corrupted(message):
            return .corrupted(message)
        }
    }

    /// Persists order/metadata and writes payload files only for new records.
    /// The returned items contain thumbnails rather than full image data.
    func persist(
        _ requestedItems: [ClipboardHistoryItem],
        originalImages: [UUID: Data] = [:]
    ) throws -> [ClipboardHistoryItem] {
        let key = try encryptionKey(createIfMissing: true)
        let existing = try currentManifest(key: key)
        let existingByID = Dictionary(uniqueKeysWithValues: existing.entries.map { ($0.id, $0) })
        var candidateEntries: [Entry] = []
        var normalizedByID: [UUID: ClipboardHistoryItem] = [:]
        var newlyWrittenIDs: Set<UUID> = []

        do {
            for item in requestedItems {
                if let old = existingByID[item.id] {
                    candidateEntries.append(Entry(
                        id: old.id,
                        kind: old.kind,
                        displayText: item.displayText,
                        createdAt: old.createdAt,
                        sourceApplication: item.sourceApplication,
                        contentHash: item.contentHash ?? old.contentHash,
                        encryptedByteCount: old.encryptedByteCount,
                        isPinned: item.pinned
                    ))
                    normalizedByID[item.id] = item
                    continue
                }

                let originalImage = item.kind == .image ? (originalImages[item.id] ?? item.binaryData) : nil
                let record = Record(payload: item.payload, imageData: originalImage)
                let clear = try JSONEncoder().encode(record)
                let encrypted = try seal(clear, key: key)
                try writeProtected(encrypted, to: recordURL(item.id))
                newlyWrittenIDs.insert(item.id)

                var normalized = item
                if item.kind == .image, let originalImage {
                    let thumbnail = makeThumbnail(from: originalImage) ?? Data()
                    if !thumbnail.isEmpty {
                        try writeProtected(try seal(thumbnail, key: key), to: thumbnailURL(item.id))
                    }
                    normalized = ClipboardHistoryItem(
                        id: item.id,
                        kind: item.kind,
                        payload: item.payload,
                        createdAt: item.createdAt,
                        sourceApplication: item.sourceApplication,
                        binaryData: thumbnail.isEmpty ? nil : thumbnail,
                        contentHash: item.contentHash ?? hash(clear),
                        isPinned: item.pinned
                    )
                }
                normalizedByID[item.id] = normalized
                candidateEntries.append(Entry(
                    id: item.id,
                    kind: item.kind,
                    displayText: item.displayText,
                    createdAt: item.createdAt,
                    sourceApplication: item.sourceApplication,
                    contentHash: item.contentHash ?? hash(clear),
                    encryptedByteCount: encrypted.count,
                    isPinned: item.pinned
                ))
            }

            var retainedEntries: [Entry] = []
            var totalBytes = 0
            for entry in candidateEntries {
                guard totalBytes + entry.encryptedByteCount <= maximumEncryptedBytes else { continue }
                retainedEntries.append(entry)
                totalBytes += entry.encryptedByteCount
            }
            let retainedIDs = Set(retainedEntries.map(\.id))
            let manifest = Manifest(entries: retainedEntries)
            let manifestData = try JSONEncoder().encode(manifest)
            try writeProtected(try seal(manifestData, key: key), to: manifestURL)

            let obsoleteIDs = Set(existing.entries.map(\.id)).union(newlyWrittenIDs).subtracting(retainedIDs)
            obsoleteIDs.forEach(removePayloadFiles)
            return retainedEntries.compactMap { normalizedByID[$0.id] }
        } catch {
            newlyWrittenIDs.forEach(removePayloadFiles)
            throw error
        }
    }

    func imageData(for id: UUID) -> Data? {
        guard let key = try? encryptionKey(createIfMissing: false),
              let encrypted = try? Data(contentsOf: recordURL(id)),
              let clear = try? open(encrypted, key: key),
              let record = try? JSONDecoder().decode(Record.self, from: clear) else { return nil }
        return record.imageData
    }

    func removePersistedHistory() throws {
        if FileManager.default.fileExists(atPath: vaultURL.path) {
            try FileManager.default.removeItem(at: vaultURL)
        }
        if FileManager.default.fileExists(atPath: legacyFileURL.path) {
            try FileManager.default.removeItem(at: legacyFileURL)
        }
        let migratedLegacy = legacyFileURL.appendingPathExtension("migrated")
        if FileManager.default.fileExists(atPath: migratedLegacy.path) {
            try FileManager.default.removeItem(at: migratedLegacy)
        }
        let root = vaultURL.deletingLastPathComponent()
        try createVaultDirectories(fileManager: .default, root: root)
    }

    func diskUsage() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func loadVersion2() -> ClipboardStoreLoadResult {
        let key: Data
        do {
            key = try encryptionKey(createIfMissing: false)
        } catch {
            return .unavailable(error.localizedDescription)
        }
        let manifest: Manifest
        do {
            let encrypted = try Data(contentsOf: manifestURL)
            let clear = try open(encrypted, key: key)
            manifest = try JSONDecoder().decode(Manifest.self, from: clear)
            guard manifest.version == 2 else {
                return .corrupted("不支持的剪贴板存储版本：\(manifest.version)")
            }
        } catch {
            return .corrupted("剪贴板清单验证失败；原文件未被覆盖：\(error.localizedDescription)")
        }

        var items: [ClipboardHistoryItem] = []
        var skipped = 0
        for entry in manifest.entries {
            do {
                let payload: [String]
                let thumbnail: Data?
                switch entry.kind {
                case .image:
                    payload = [entry.displayText]
                    thumbnail = try loadThumbnail(entry.id, key: key)
                case .text, .files:
                    let encrypted = try Data(contentsOf: recordURL(entry.id))
                    let clear = try open(encrypted, key: key)
                    payload = try JSONDecoder().decode(Record.self, from: clear).payload
                    thumbnail = nil
                }
                items.append(ClipboardHistoryItem(
                    id: entry.id,
                    kind: entry.kind,
                    payload: payload,
                    createdAt: entry.createdAt,
                    sourceApplication: entry.sourceApplication,
                    binaryData: thumbnail,
                    contentHash: entry.contentHash,
                    isPinned: entry.isPinned
                ))
            } catch {
                skipped += 1
            }
        }
        let warning = skipped == 0 ? nil : "有 \(skipped) 条剪贴板记录损坏，已跳过但未覆盖原密文。"
        return .loaded(items, warning: warning)
    }

    private func loadLegacy() -> ClipboardStoreLoadResult {
        let key: Data
        do {
            key = try encryptionKey(createIfMissing: false)
        } catch {
            return .unavailable(error.localizedDescription)
        }
        do {
            let encrypted = try Data(contentsOf: legacyFileURL)
            let clear = try open(encrypted, key: key)
            let items = try JSONDecoder().decode([ClipboardHistoryItem].self, from: clear)
            return .loaded(items.map(addingHashIfNeeded), warning: nil)
        } catch {
            return .corrupted("旧剪贴板历史验证失败；原文件未被覆盖：\(error.localizedDescription)")
        }
    }

    private func currentManifest(key: Data) throws -> Manifest {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return Manifest(entries: []) }
        let clear = try open(Data(contentsOf: manifestURL), key: key)
        return try JSONDecoder().decode(Manifest.self, from: clear)
    }

    private func addingHashIfNeeded(_ item: ClipboardHistoryItem) -> ClipboardHistoryItem {
        guard item.contentHash == nil else { return item }
        let data: Data
        switch item.kind {
        case .text, .files: data = Data(item.payload.joined(separator: "\0").utf8)
        case .image: data = item.binaryData ?? Data()
        }
        return ClipboardHistoryItem(
            id: item.id,
            kind: item.kind,
            payload: item.payload,
            createdAt: item.createdAt,
            sourceApplication: item.sourceApplication,
            binaryData: item.binaryData,
            contentHash: hash(data),
            isPinned: item.pinned
        )
    }

    private func encryptionKey(createIfMissing: Bool) throws -> Data {
        do {
            return try keyAccessor.key(createIfMissing: createIfMissing)
        } catch {
            throw ClipboardStoreError.keyUnavailable(error.localizedDescription)
        }
    }

    private func seal(_ clear: Data, key: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(clear, using: SymmetricKey(data: key)).combined else {
            throw ClipboardStoreError.writeFailed("AES-GCM 未生成组合密文。")
        }
        return combined
    }

    private func open(_ encrypted: Data, key: Data) throws -> Data {
        do {
            return try AES.GCM.open(
                AES.GCM.SealedBox(combined: encrypted),
                using: SymmetricKey(data: key)
            )
        } catch {
            throw ClipboardStoreError.corrupted("AES-GCM 验证失败：\(error.localizedDescription)")
        }
    }

    private func writeProtected(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw ClipboardStoreError.writeFailed("无法写入 \(url.lastPathComponent)：\(error.localizedDescription)")
        }
    }

    private func createVaultDirectories(fileManager: FileManager, root: URL) throws {
        for directory in [root, vaultURL, recordsURL, thumbnailsURL] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
    }

    private func recordURL(_ id: UUID) -> URL { recordsURL.appendingPathComponent("\(id.uuidString).enc") }
    private func thumbnailURL(_ id: UUID) -> URL { thumbnailsURL.appendingPathComponent("\(id.uuidString).enc") }

    private func removePayloadFiles(_ id: UUID) {
        try? FileManager.default.removeItem(at: recordURL(id))
        try? FileManager.default.removeItem(at: thumbnailURL(id))
    }

    private func loadThumbnail(_ id: UUID, key: Data) throws -> Data? {
        let url = thumbnailURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try open(Data(contentsOf: url), key: key)
    }

    private func makeThumbnail(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 192
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.png" as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

}
