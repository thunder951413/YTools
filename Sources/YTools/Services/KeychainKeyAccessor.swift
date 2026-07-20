import Foundation
import Security

/// Shared primitive for retrieving or creating a device-bound symmetric key.
/// Encryption formats remain owned by their stores; keychain policy lives here.
struct KeychainKeyAccessor {
    enum AccessError: Error, LocalizedError {
        case missing(String)
        case keychain(OSStatus)
        case randomGeneration(String)

        var errorDescription: String? {
            switch self {
            case let .missing(message), let .randomGeneration(message):
                return message
            case let .keychain(status):
                let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
                return "钥匙串不可用：\(detail)"
            }
        }
    }

    let service: String
    let account: String
    let missingKeyMessage: String
    let randomGenerationMessage: String

    func key(createIfMissing: Bool) throws -> Data {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return data }
        guard status == errSecItemNotFound else { throw AccessError.keychain(status) }
        guard createIfMissing else { throw AccessError.missing(missingKeyMessage) }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AccessError.randomGeneration(randomGenerationMessage)
        }
        let data = Data(bytes)
        let insert: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else { throw AccessError.keychain(insertStatus) }
        return data
    }
}
