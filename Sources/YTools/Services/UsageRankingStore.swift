import CryptoKit
import Foundation

/// Stores only SHA-256 hashes of result identifiers, so usage learning does not
/// create a second plaintext index of private file paths.
final class UsageRankingStore {
    private struct Entry: Codable {
        var count: Int
        var lastUsed: Date
    }

    private struct Latch: Codable {
        var resultHash: String
        var confirmations: Int
        var lastUsed: Date
    }

    private struct StoreData: Codable {
        var version = 2
        var entries: [String: Entry]
        var latches: [String: Latch]
    }

    private let fileURL: URL
    private var entries: [String: Entry]
    private var latches: [String: Latch]

    init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        // Compatibility namespace retained across the product rename.
        let directory = applicationSupport.appendingPathComponent("ZToolsNative", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("usage-ranking.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(StoreData.self, from: data) {
            self.entries = decoded.entries
            self.latches = decoded.latches
        } else if let data = try? Data(contentsOf: fileURL),
                  let legacy = try? JSONDecoder().decode([String: Entry].self, from: data) {
            self.entries = legacy
            self.latches = [:]
        } else {
            self.entries = [:]
            self.latches = [:]
        }
        prune()
    }

    func record(_ identifier: String, query: String) {
        let key = hash(identifier)
        let old = entries[key]
        entries[key] = Entry(count: min((old?.count ?? 0) + 1, 10_000), lastUsed: Date())
        let normalizedQuery = normalize(query)
        if !normalizedQuery.isEmpty {
            let queryHash = hash(normalizedQuery)
            let oldLatch = latches[queryHash]
            let confirmations = oldLatch?.resultHash == key
                ? min((oldLatch?.confirmations ?? 0) + 1, 20)
                : 1
            latches[queryHash] = Latch(
                resultHash: key,
                confirmations: confirmations,
                lastUsed: Date()
            )
        }
        prune()
        save()
    }

    func boost(for identifier: String, query: String) -> Int {
        let resultHash = hash(identifier)
        let entry = entries[resultHash]
        let frequency = entry.map { Int(log2(Double($0.count + 1)) * 24) } ?? 0
        let age = entry.map { Date().timeIntervalSince($0.lastUsed) } ?? .greatestFiniteMagnitude
        let recency: Int
        switch age {
        case ..<3_600: recency = 45
        case ..<86_400: recency = 30
        case ..<(7 * 86_400): recency = 15
        default: recency = 0
        }
        let normalizedQuery = normalize(query)
        let latchBoost: Int
        if !normalizedQuery.isEmpty,
           let latch = latches[hash(normalizedQuery)],
           latch.resultHash == resultHash,
           Date().timeIntervalSince(latch.lastUsed) < 28 * 86_400 {
            latchBoost = min(180, 55 + latch.confirmations * 25)
        } else {
            latchBoost = 0
        }
        return frequency + recency + latchBoost
    }

    func clear() {
        entries.removeAll()
        latches.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func normalize(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-28 * 86_400)
        entries = entries.filter { $0.value.lastUsed >= cutoff }
        latches = latches.filter { $0.value.lastUsed >= cutoff }
    }

    private func save() {
        let payload = StoreData(entries: entries, latches: latches)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // Ranking is optional and must never prevent launching a result.
        }
    }
}
