import AppKit
import Combine
import Foundation
import YToolsCore
import YToolsModuleKit

@MainActor
final class SnippetManager: ObservableObject, SnippetSaving {
    @Published private(set) var items: [SnippetItem]
    @Published private(set) var storageError: String?
    @Published private(set) var isLoaded = false
    @Published private(set) var isSaving = false
    private let writer: OrderedSecureStoreWriter
    private let saveDebouncer = DebouncedAction()
    private var pendingMutations: [PendingMutation] = []
    private var initializationTask: Task<Void, Never>?
    private var revision: UInt64 = 0
    private var queuedRevision: UInt64 = 0
    private var latestSaveTask: Task<Bool, Never>?

    init() {
        self.writer = OrderedSecureStoreWriter { SecureCodableStore(name: "snippets") }
        items = []
        storageError = nil
        startLoading()
    }

    init(storeFactory: @escaping @Sendable () -> SecureCodableStore) {
        self.writer = OrderedSecureStoreWriter(storeFactory: storeFactory)
        items = []
        storageError = nil
        startLoading()
    }

    var storageStatus: String {
        if !isLoaded { return "正在读取加密片段…" }
        if isSaving { return "正在加密保存…" }
        return storageError ?? "已安全保存"
    }

    private func startLoading() {
        initializationTask = Task { [weak self, writer] in
            let result = await writer.load([SnippetItem].self)
            guard let self else { return }
            applyLoad(result)
        }
    }

    private func applyLoad(_ result: BackgroundStoreLoad<[SnippetItem]>) {
        guard !isLoaded else { return }
        var loaded: [SnippetItem]
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
        pendingMutations.forEach { $0.apply(to: &loaded) }
        pendingMutations.removeAll()
        items = loaded
        isLoaded = true
        if revision > 0 { _ = queueCurrentSnapshot(failureMessage: "无法写入加密文本片段；现有文件未被覆盖。") }
    }

    func searchModule(clipboardText: String, now: Date = Date()) -> SnippetSearchModule {
        SnippetSearchModule(items: items, clipboardText: clipboardText, now: now)
    }

    var saveError: String? { storageError }

    @discardableResult
    func save(text: String, title: String? = nil, keyword: String = "", collection: String = "默认") -> Bool {
        beginSave(text: text, title: title, keyword: keyword, collection: collection) != nil
    }

    func savePersisted(text: String, title: String? = nil, keyword: String = "", collection: String = "默认") async -> Bool {
        guard let targetRevision = beginSave(text: text, title: title, keyword: keyword, collection: collection) else { return false }
        await initializationTask?.value
        if queuedRevision < targetRevision {
            return await queueCurrentSnapshot(failureMessage: "无法写入加密文本片段；现有文件未被覆盖。").value
        }
        return await waitForQueuedWrites()
    }

    private func beginSave(text: String, title: String?, keyword: String, collection: String) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let inferredTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = inferredTitle.flatMap { $0.isEmpty ? nil : $0 } ?? preview(trimmed, limit: 36)
        let now = Date()
        let item = SnippetItem(
            id: UUID(),
            title: finalTitle,
            keyword: keyword,
            content: text,
            collection: collection,
            createdAt: now,
            updatedAt: now
        )
        apply(.insert(item))
        if isLoaded { _ = queueCurrentSnapshot(failureMessage: "无法写入加密文本片段；现有文件未被覆盖。") }
        return revision
    }

    func delete(_ item: SnippetItem) {
        apply(.delete(item.id))
        if isLoaded { _ = queueCurrentSnapshot(failureMessage: "无法保存删除操作。") }
    }

    func update(
        id: UUID,
        title: String? = nil,
        keyword: String? = nil,
        content: String? = nil,
        collection: String? = nil
    ) {
        guard items.contains(where: { $0.id == id }) else { return }
        apply(.update(id, title, keyword, content, collection, Date()))
        saveDebouncer.schedule(after: .milliseconds(350)) { [weak self] in
            guard let self, self.isLoaded else { return }
            _ = self.queueCurrentSnapshot(failureMessage: "无法保存文本片段修改。")
        }
    }

    func flushPendingChanges() async {
        saveDebouncer.cancel()
        await initializationTask?.value
        if queuedRevision < revision {
            _ = await queueCurrentSnapshot(failureMessage: "无法保存文本片段修改。").value
        }
        _ = await waitForQueuedWrites()
    }

    func waitUntilLoaded() async { await initializationTask?.value }

    private func apply(_ mutation: PendingMutation) {
        saveDebouncer.cancel()
        mutation.apply(to: &items)
        if !isLoaded { pendingMutations.append(mutation) }
        revision &+= 1
    }

    private func queueCurrentSnapshot(failureMessage: String) -> Task<Bool, Never> {
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
                storageError = success ? nil : failureMessage
            }
            return success
        }
        latestSaveTask = task
        return task
    }

    private func waitForQueuedWrites() async -> Bool {
        // Submitting a sentinel save is unnecessary: every returned save task
        // completes only after all earlier actor operations.
        if queuedRevision < revision { return false }
        guard let latestSaveTask else { return queuedRevision == revision && storageError == nil }
        return await latestSaveTask.value
    }

    private enum PendingMutation {
        case insert(SnippetItem)
        case delete(UUID)
        case update(UUID, String?, String?, String?, String?, Date)

        func apply(to items: inout [SnippetItem]) {
            switch self {
            case let .insert(item): items.insert(item, at: 0)
            case let .delete(id): items.removeAll { $0.id == id }
            case let .update(id, title, keyword, content, collection, date):
                guard let index = items.firstIndex(where: { $0.id == id }) else { return }
                if let title { items[index].title = title }
                if let keyword { items[index].keyword = keyword }
                if let content { items[index].content = content }
                if let collection { items[index].collection = collection }
                items[index].updatedAt = date
            }
        }
    }

    private func preview(_ text: String, limit: Int = 72) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        return singleLine.count <= limit ? singleLine : String(singleLine.prefix(limit)) + "…"
    }
}

struct SnippetSearchModule: YToolsModule {
    let descriptor = ModuleDescriptor(id: "snippets", name: "文本片段")
    let items: [SnippetItem]
    let clipboardText: String
    let now: Date

    static func accepts(_ query: String) -> Bool {
        searchTerm(query) != nil
    }

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        guard let term = searchTerm(request.query) else { return [] }
        return items.filter { item in
            term.isEmpty
                || item.title.localizedCaseInsensitiveContains(term)
                || item.keyword.localizedCaseInsensitiveContains(term)
                || item.content.localizedCaseInsensitiveContains(term)
                || item.collection.localizedCaseInsensitiveContains(term)
        }
        .prefix(30)
        .map { item in
            let expanded = expand(item.content)
            return LauncherResult(
                id: "snippet:\(item.id.uuidString)",
                moduleID: descriptor.id,
                title: item.title,
                subtitle: [item.collection, item.keyword, preview(expanded)]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "),
                icon: .system("text.quote"),
                score: 820,
                action: .copy(expanded)
            )
        }
    }

    private static func searchTerm(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["snip", "snippet", "片段"] {
            if trimmed.lowercased() == prefix { return "" }
            if trimmed.lowercased().hasPrefix(prefix + " ") {
                return String(trimmed.dropFirst(prefix.count + 1))
            }
        }
        return nil
    }

    private func searchTerm(_ query: String) -> String? { Self.searchTerm(query) }

    private func expand(_ content: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        let date = formatter.string(from: now)
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        let time = formatter.string(from: now)
        return content
            .replacingOccurrences(of: "{date}", with: date)
            .replacingOccurrences(of: "{time}", with: time)
            .replacingOccurrences(of: "{clipboard}", with: clipboardText)
            .replacingOccurrences(of: "{cursor}", with: "")
    }

    private func preview(_ text: String, limit: Int = 72) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        return singleLine.count <= limit ? singleLine : String(singleLine.prefix(limit)) + "…"
    }
}
