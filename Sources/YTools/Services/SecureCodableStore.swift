import CryptoKit
import Foundation

enum SecureStoreLoadResult<Value> {
    case missing
    case loaded(Value)
    case unavailable(String)
    case corrupted(String)
}

final class SecureCodableStore {
    private let fileURL: URL
    private let keyAccessor: KeychainKeyAccessor

    init(name: String, fileManager: FileManager = .default) {
        keyAccessor = KeychainKeyAccessor(
            service: "com.ztools.native.secure-store",
            account: "\(name)-key-v1",
            missingKeyMessage: "加密文件存在，但钥匙串密钥缺失；为防止覆盖，存储已锁定。",
            randomGenerationMessage: "无法生成安全随机密钥。"
        )
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        // Compatibility namespace retained across the product rename.
        let directory = support.appendingPathComponent("ZToolsNative", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        fileURL = directory.appendingPathComponent("\(name).v1.enc")
    }

    func load<Value: Decodable>(_ type: Value.Type) -> SecureStoreLoadResult<Value> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        let key: Data
        do { key = try keyAccessor.key(createIfMissing: false) }
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
        guard let key = try? keyAccessor.key(createIfMissing: true),
              let clear = try? JSONEncoder().encode(value),
              let combined = try? AES.GCM.seal(clear, using: SymmetricKey(data: key)).combined else {
            return false
        }
        do {
            try combined.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            return false
        }
    }

}
