import CryptoKit
import Foundation

enum SecureStoreLoadResult<Value> {
    case missing
    case loaded(Value)
    case unavailable(String)
    case corrupted(String)
}

final class SecureCodableStore: @unchecked Sendable {
    private let fileURL: URL
    private let keyProvider: @Sendable (Bool) throws -> Data
    private let lock = NSRecursiveLock()
    private var locked = false

    init(name: String, fileManager: FileManager = .default) {
        let keyAccessor = KeychainKeyAccessor(
            service: "com.ztools.native.secure-store",
            account: "\(name)-key-v1",
            missingKeyMessage: "加密文件存在，但钥匙串密钥缺失；为防止覆盖，存储已锁定。",
            randomGenerationMessage: "无法生成安全随机密钥。"
        )
        keyProvider = { try keyAccessor.key(createIfMissing: $0) }
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        // Compatibility namespace retained across the product rename.
        let directory = support.appendingPathComponent("ZToolsNative", isDirectory: true)
        fileURL = directory.appendingPathComponent("\(name).v1.enc")
    }

    init(fileURL: URL, keyProvider: @escaping @Sendable (Bool) throws -> Data) {
        self.fileURL = fileURL
        self.keyProvider = keyProvider
    }

    func load<Value: Decodable>(_ type: Value.Type) -> SecureStoreLoadResult<Value> {
        lock.lock()
        defer { lock.unlock() }
        let result = loadValue(type)
        switch result {
        case .unavailable, .corrupted: locked = true
        default: break
        }
        return result
    }

    private func loadValue<Value: Decodable>(_ type: Value.Type) -> SecureStoreLoadResult<Value> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        let key: Data
        do { key = try keyProvider(false) }
        catch { return .unavailable(error.localizedDescription) }
        let encrypted: Data
        do {
            encrypted = try Data(contentsOf: fileURL)
        } catch {
            return .unavailable("无法读取加密文件：\(error.localizedDescription)")
        }
        do {
            let box = try AES.GCM.SealedBox(combined: encrypted)
            let clear = try AES.GCM.open(box, using: SymmetricKey(data: key))
            return .loaded(try JSONDecoder().decode(type, from: clear))
        } catch {
            return .corrupted("加密数据验证或解码失败：\(error.localizedDescription)")
        }
    }

    @discardableResult
    func save<Value: Encodable>(_ value: Value) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !locked else { return false }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let exists = FileManager.default.fileExists(atPath: fileURL.path)
            let key = try keyProvider(!exists)
            if exists {
                let prior = try AES.GCM.SealedBox(combined: Data(contentsOf: fileURL))
                _ = try AES.GCM.open(prior, using: SymmetricKey(data: key))
            }
            let clear = try JSONEncoder().encode(value)
            guard let combined = try AES.GCM.seal(clear, using: SymmetricKey(data: key)).combined else { return false }
            try combined.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            locked = true
            return false
        }
    }
}
