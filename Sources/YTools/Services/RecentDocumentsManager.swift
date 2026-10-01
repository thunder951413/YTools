import AppKit
import Combine
import YToolsModuleKit

/// Keeps a private, encrypted list of files opened through YTools. This is
/// intentionally independent of cloud accounts and macOS shared recent items.
@MainActor
final class RecentDocumentsManager: ObservableObject, RecentDocumentsRecording {
    @Published private(set) var items: [RecentDocumentItem]
    @Published private(set) var storageError: String?
    @Published private(set) var isLoaded = false
    @Published private(set) var isSaving = false

    private let writer: OrderedSecureStoreWriter
    private let maximumItems = 200
    private var pendingMutations: [PendingMutation] = []
    private var initializationTask: Task<Void, Never>?
    private var revision: UInt64 = 0
    private var queuedRevision: UInt64 = 0
    private var latestSaveTask: Task<Bool, Never>?

    init() {
        writer = OrderedSecureStoreWriter { SecureCodableStore(name: "recent-documents") }
        items = []
        storageError = nil
        startLoading()
    }

    init(storeFactory: @escaping @Sendable () -> SecureCodableStore) {
        writer = OrderedSecureStoreWriter(storeFactory: storeFactory)
        items = []
        storageError = nil
        startLoading()
    }

    private func startLoading() {
        initializationTask = Task { [weak self, writer] in
            let rawResult = await writer.load([RecentDocumentItem].self)
            let result = await Task.detached {
                switch rawResult {
                case let .loaded(items):
                    let filtered = items.filter { FileManager.default.fileExists(atPath: $0.path) }
                    return PreparedLoad(result: .loaded(filtered), removedMissingItems: filtered.count != items.count)
                case .missing: return PreparedLoad(result: .missing, removedMissingItems: false)
                case let .unavailable(message): return PreparedLoad(result: .unavailable(message), removedMissingItems: false)
                case let .corrupted(message): return PreparedLoad(result: .corrupted(message), removedMissingItems: false)
                }
            }.value
            guard let self else { return }
            applyLoad(result)
        }
    }

    private func applyLoad(_ prepared: PreparedLoad) {
        guard !isLoaded else { return }
        let result = prepared.result
        var loaded: [RecentDocumentItem]
        switch result {
        case .missing:
            loaded = []
            storageError = nil
        case let .loaded(value):
            loaded = value
            storageError = nil
        case let .unavailable(message), let .corrupted(message):
            loaded = []
            storageError = message
        }
        pendingMutations.forEach { $0.apply(to: &loaded, maximumItems: maximumItems) }
        pendingMutations.removeAll()
        items = loaded
        isLoaded = true
        if revision > 0 || prepared.removedMissingItems {
            revision = max(1, revision)
            _ = queueCurrentSnapshot()
        }
    }

    func record(_ url: URL) {
        guard url.isFileURL,
              url.pathExtension.caseInsensitiveCompare("app") != .orderedSame,
              FileManager.default.fileExists(atPath: url.path) else { return }
        apply(.record(RecentDocumentItem(id: UUID(), path: url.path, lastOpenedAt: Date())))
        if isLoaded { _ = queueCurrentSnapshot() }
    }

    func clear() {
        apply(.clear)
        if isLoaded { _ = queueCurrentSnapshot() }
    }

    func searchModule() -> RecentDocumentsSearchModule {
        RecentDocumentsSearchModule(items: items)
    }

    func flushPendingChanges() async {
        await initializationTask?.value
        if queuedRevision < revision { _ = await queueCurrentSnapshot().value }
        _ = await latestSaveTask?.value
    }

    func waitUntilLoaded() async { await initializationTask?.value }

    private func apply(_ mutation: PendingMutation) {
        mutation.apply(to: &items, maximumItems: maximumItems)
        if !isLoaded { pendingMutations.append(mutation) }
        revision &+= 1
    }

    private func queueCurrentSnapshot() -> Task<Bool, Never> {
        let snapshot = items
        let saveRevision = revision
        queuedRevision = max(queuedRevision, saveRevision)
        isSaving = true
        let previous = latestSaveTask
        let task = Task { [weak self, writer] in
            _ = await previous?.value
            let success = await writer.save(snapshot)
            guard let self else { return success }
            if saveRevision == revision {
                isSaving = false
                storageError = success ? nil : "无法写入加密最近文档；现有文件未被明文替代。"
            }
            return success
        }
        latestSaveTask = task
        return task
    }

    private enum PendingMutation {
        case record(RecentDocumentItem)
        case clear

        func apply(to items: inout [RecentDocumentItem], maximumItems: Int) {
            switch self {
            case let .record(item):
                items.removeAll { $0.path == item.path }
                items.insert(item, at: 0)
                items = Array(items.prefix(maximumItems))
            case .clear:
                items.removeAll()
            }
        }
    }

    private struct PreparedLoad: Sendable {
        let result: BackgroundStoreLoad<[RecentDocumentItem]>
        let removedMissingItems: Bool
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
