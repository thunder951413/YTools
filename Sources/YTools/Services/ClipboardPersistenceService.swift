import Foundation

/// Serializes every encrypted-vault operation away from MainActor. Revisions
/// prevent a late, older UI snapshot from overwriting a newer mutation.
actor ClipboardPersistenceService {
    private var store: ClipboardHistoryStore?
    private var latestRevision = 0

    func load() -> ClipboardStoreLoadResult {
        storeInstance().load()
    }

    func persist(
        _ items: [ClipboardHistoryItem],
        originalImages: [UUID: Data],
        revision: Int
    ) throws -> [ClipboardHistoryItem]? {
        guard revision > latestRevision else { return nil }
        let normalized = try storeInstance().persist(items, originalImages: originalImages)
        latestRevision = revision
        return normalized
    }

    func imageData(for id: UUID) -> Data? {
        storeInstance().imageData(for: id)
    }

    func clear(revision: Int) throws {
        guard revision > latestRevision else { return }
        try storeInstance().removePersistedHistory()
        latestRevision = revision
    }

    func diskUsage() -> Int64 {
        storeInstance().diskUsage()
    }

    private func storeInstance() -> ClipboardHistoryStore {
        if let store { return store }
        let created = ClipboardHistoryStore()
        store = created
        return created
    }
}
