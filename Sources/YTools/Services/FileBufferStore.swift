import Foundation

struct FileBufferStore {
    private(set) var urls: [URL] = []

    func contains(_ url: URL) -> Bool { urls.contains(url) }

    mutating func add(_ url: URL) {
        if !urls.contains(url) { urls.append(url) }
    }

    @discardableResult
    mutating func removeLast() -> Bool {
        guard !urls.isEmpty else { return false }
        urls.removeLast()
        return true
    }

    mutating func clear() {
        urls.removeAll()
    }
}
