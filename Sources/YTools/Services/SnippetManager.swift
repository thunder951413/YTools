import AppKit
import Combine
import Foundation
import YToolsCore
import YToolsModuleKit

@MainActor
final class SnippetManager: ObservableObject, SnippetSaving {
    @Published private(set) var items: [SnippetItem]
    @Published private(set) var storageError: String?
    private let store = SecureCodableStore(name: "snippets")
    private let saveDebouncer = DebouncedAction()
    private var persistedItems: [SnippetItem] = []

    init() {
        switch store.load([SnippetItem].self) {
        case .missing:
            items = []
            storageError = nil
        case let .loaded(loaded):
            items = loaded
            storageError = nil
        case let .unavailable(message), let .corrupted(message):
            items = []
            storageError = message
        }
        persistedItems = items
    }

    func searchModule(clipboardText: String, now: Date = Date()) -> SnippetSearchModule {
        SnippetSearchModule(items: items, clipboardText: clipboardText, now: now)
    }

    var saveError: String? { storageError }

    @discardableResult
    func save(text: String, title: String? = nil, keyword: String = "", collection: String = "默认") -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let inferredTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = inferredTitle.flatMap { $0.isEmpty ? nil : $0 } ?? preview(trimmed, limit: 36)
        let now = Date()
        items.insert(SnippetItem(
            id: UUID(),
            title: finalTitle,
            keyword: keyword,
            content: text,
            collection: collection,
            createdAt: now,
            updatedAt: now
        ), at: 0)
        return persistCurrent(failureMessage: "无法写入加密文本片段；现有文件未被覆盖。")
    }

    func delete(_ item: SnippetItem) {
        items.removeAll { $0.id == item.id }
        _ = persistCurrent(failureMessage: "无法保存删除操作。")
    }

    func update(
        id: UUID,
        title: String? = nil,
        keyword: String? = nil,
        content: String? = nil,
        collection: String? = nil
    ) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if let title { items[index].title = title }
        if let keyword { items[index].keyword = keyword }
        if let content { items[index].content = content }
        if let collection { items[index].collection = collection }
        items[index].updatedAt = Date()
        saveDebouncer.schedule(after: .milliseconds(350)) { [weak self] in
            _ = self?.persistCurrent(failureMessage: "无法保存文本片段修改。")
        }
    }

    func flushPendingChanges() {
        saveDebouncer.cancel()
        guard items != persistedItems else { return }
        _ = persistCurrent(failureMessage: "无法保存文本片段修改。")
    }

    @discardableResult
    private func persistCurrent(failureMessage: String) -> Bool {
        saveDebouncer.cancel()
        if store.save(items) {
            persistedItems = items
            storageError = nil
            return true
        }
        items = persistedItems
        storageError = failureMessage
        return false
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
