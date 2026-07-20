import AppKit
import Combine
import YToolsModuleKit

/// Keeps a private, encrypted list of files opened through YTools. This is
/// intentionally independent of cloud accounts and macOS shared recent items.
@MainActor
final class RecentDocumentsManager: ObservableObject, RecentDocumentsRecording {
    @Published private(set) var items: [RecentDocumentItem]
    @Published private(set) var storageError: String?

    private let store = SecureCodableStore(name: "recent-documents")
    private let maximumItems = 200

    init() {
        switch store.load([RecentDocumentItem].self) {
        case .missing:
            items = []
            storageError = nil
        case let .loaded(loaded):
            items = loaded.filter { FileManager.default.fileExists(atPath: $0.path) }
            storageError = nil
            if items.count != loaded.count { persist() }
        case let .unavailable(message), let .corrupted(message):
            items = []
            storageError = message
        }
    }

    func record(_ url: URL) {
        guard url.isFileURL,
              url.pathExtension.caseInsensitiveCompare("app") != .orderedSame,
              FileManager.default.fileExists(atPath: url.path) else { return }
        items.removeAll { $0.path == url.path }
        items.insert(
            RecentDocumentItem(id: UUID(), path: url.path, lastOpenedAt: Date()),
            at: 0
        )
        items = Array(items.prefix(maximumItems))
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    func searchModule() -> RecentDocumentsSearchModule {
        RecentDocumentsSearchModule(items: items)
    }

    private func persist() {
        if store.save(items) {
            storageError = nil
        } else {
            storageError = "无法写入加密最近文档；现有文件未被明文替代。"
        }
    }
}

struct RecentDocumentsSearchModule: YToolsModule {
    let descriptor = ModuleDescriptor(
        id: "recent-documents",
        name: "最近文档",
        capabilities: [.localFileRead]
    )
    let items: [RecentDocumentItem]

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        let trimmed = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["recent", "最近", "最近文档"]
        guard let prefix = prefixes.first(where: {
            trimmed.localizedCaseInsensitiveCompare($0) == .orderedSame
                || trimmed.lowercased().hasPrefix($0.lowercased() + " ")
        }) else { return [] }

        let term = String(trimmed.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return items.enumerated().compactMap { index, item in
            let url = item.url
            guard FileManager.default.fileExists(atPath: item.path) else { return nil }
            let name = url.lastPathComponent
            guard term.isEmpty
                    || name.localizedCaseInsensitiveContains(term)
                    || item.path.localizedCaseInsensitiveContains(term) else { return nil }
            return LauncherResult(
                id: "recent:\(item.path)",
                moduleID: descriptor.id,
                title: name,
                subtitle: "最近打开 · \(abbreviatedPath(item.path))",
                icon: .file(url),
                score: 1_300 - index,
                action: .open(url)
            )
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
