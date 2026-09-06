import Foundation

enum BackgroundStoreLoad<Value: Sendable>: Sendable {
    case missing
    case loaded(Value)
    case unavailable(String)
    case corrupted(String)
}

/// Owns one secure store and serializes all of its disk and keychain work.
actor OrderedSecureStoreWriter {
    private let storeFactory: @Sendable () -> SecureCodableStore
    private var store: SecureCodableStore?

    init(storeFactory: @escaping @Sendable () -> SecureCodableStore) {
        self.storeFactory = storeFactory
    }

    func load<Value: Decodable & Sendable>(_ type: Value.Type) -> BackgroundStoreLoad<Value> {
        let store = resolvedStore()
        switch store.load(type) {
        case .missing: return .missing
        case let .loaded(value): return .loaded(value)
        case let .unavailable(message): return .unavailable(message)
        case let .corrupted(message): return .corrupted(message)
        }
    }

    func save<Value: Encodable & Sendable>(_ value: Value) -> Bool {
        resolvedStore().save(value)
    }

    private func resolvedStore() -> SecureCodableStore {
        if let store { return store }
        let created = storeFactory()
        store = created
        return created
    }
}
