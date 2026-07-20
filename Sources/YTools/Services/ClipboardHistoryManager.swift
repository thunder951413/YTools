import AppKit
import Combine
import YToolsCore

@MainActor
final class ClipboardHistoryManager: NSObject, ObservableObject {
    enum Filter: String, CaseIterable, Identifiable, Sendable {
        case all
        case text
        case files
        case image

        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "全部"
            case .text: "文本"
            case .files: "文件"
            case .image: "图片"
            }
        }
    }

    @Published private(set) var items: [ClipboardHistoryItem] = [] {
        didSet { rebuildFilteredItems() }
    }
    @Published private(set) var filteredItems: [ClipboardHistoryItem] = []
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            if selectedIndex != 0 { selectedIndex = 0 }
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                filterDebouncer.cancel()
                rebuildFilteredItems()
            } else {
                scheduleFilter()
            }
        }
    }
    @Published var selectedIndex = 0
    @Published var filter: Filter = .all {
        didSet {
            guard filter != oldValue else { return }
            selectedIndex = 0
            filterDebouncer.cancel()
            rebuildFilteredItems()
        }
    }
    @Published var showsClearConfirmation = false
    @Published private(set) var storageError: String?
    @Published private(set) var isLoading = true
    @Published private(set) var storageByteCount: Int64 = 0

    private let persistence = ClipboardPersistenceService()
    private let processor = ClipboardCaptureProcessor()
    private let preferences: AppPreferences
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var lastChangeCount: Int
    private var persistenceRevision = 0
    private var storageReady = false
    private var persistenceWritable = false
    private let filterDebouncer = DebouncedAction()
    private var filterTask: Task<Void, Never>?
    private var filterRevision = 0
    private var appliedQuery = ""
    private var appliedFilter: Filter = .all
    private let maximumVisibleItems = 100

    var layoutInvalidations: AnyPublisher<Void, Never> {
        $filteredItems
            .map(\.count)
            .removeDuplicates()
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    init(preferences: AppPreferences) {
        self.preferences = preferences
        self.lastChangeCount = NSPasteboard.general.changeCount
        super.init()

        Task { [weak self, persistence] in
            let result = await persistence.load()
            let byteCount = await persistence.diskUsage()
            self?.finishLoading(result, storageByteCount: byteCount)
        }
        timer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(pollPasteboard),
            userInfo: nil,
            repeats: true
        )
        preferences.$clipboardRetentionDays.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.pruneAndPersist() }
        }.store(in: &cancellables)
        preferences.$clipboardMaximumItems.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.pruneAndPersist() }
        }.store(in: &cancellables)
        preferences.$searchInputDelay.dropFirst().sink { [weak self] _ in
            self?.scheduleFilter()
        }.store(in: &cancellables)
    }

    isolated deinit {
        timer?.invalidate()
        filterTask?.cancel()
    }

    func prepareForPresentation() {
        query = ""
        filter = .all
        selectedIndex = 0
        pollPasteboard()
    }

    @discardableResult
    func clearQuery() -> Bool {
        guard !query.isEmpty else { return false }
        query = ""
        return true
    }

    func moveSelection(by offset: Int) {
        ensureFilterIsCurrent()
        let visible = filteredItems
        guard !visible.isEmpty else { return }
        selectedIndex = (selectedIndex + offset + visible.count) % visible.count
    }

    @discardableResult
    func copySelected() -> Bool {
        ensureFilterIsCurrent()
        let visible = filteredItems
        guard visible.indices.contains(selectedIndex) else { return false }
        copy(visible[selectedIndex])
        return true
    }

    func copy(_ item: ClipboardHistoryItem) {
        switch item.kind {
        case .text:
            guard let text = item.payload.first else { return }
            writeToPasteboard { $0.setString(text, forType: .string) }
        case .files:
            let urls = item.payload.map { NSURL(fileURLWithPath: $0) }
            writeToPasteboard { $0.writeObjects(urls) }
        case .image:
            Task { [weak self, persistence] in
                guard let data = await persistence.imageData(for: item.id) ?? item.binaryData,
                      let self else { return }
                self.writeToPasteboard { $0.setData(data, forType: .png) }
            }
        }
    }

    func delete(_ item: ClipboardHistoryItem) {
        items.removeAll { $0.id == item.id }
        selectedIndex = min(selectedIndex, max(filteredItems.count - 1, 0))
        persistCurrent()
    }

    func deleteSelected() {
        ensureFilterIsCurrent()
        let visible = filteredItems
        guard visible.indices.contains(selectedIndex) else { return }
        delete(visible[selectedIndex])
    }

    func togglePinned(_ item: ClipboardHistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned = !items[index].pinned
        sortItems()
        persistCurrent()
    }

    var selectedText: String? {
        ensureFilterIsCurrent()
        let visible = filteredItems
        guard visible.indices.contains(selectedIndex), visible[selectedIndex].kind == .text else { return nil }
        return visible[selectedIndex].payload.first
    }

    func clear() {
        let previous = items
        items.removeAll()
        selectedIndex = 0
        persistenceRevision += 1
        let revision = persistenceRevision
        persistenceWritable = false
        Task { [weak self, persistence] in
            do {
                try await persistence.clear(revision: revision)
                guard let self, self.persistenceRevision == revision else { return }
                self.persistenceWritable = true
                self.storageError = nil
                self.storageByteCount = 0
                if !self.items.isEmpty { self.persistCurrent() }
            } catch {
                guard let self, self.persistenceRevision == revision else { return }
                self.items = previous
                self.persistenceWritable = false
                self.storageError = "无法清除剪贴板密文：\(error.localizedDescription)"
            }
        }
    }

    func clearRecent(minutes: Int) {
        let cutoff = Date().addingTimeInterval(-TimeInterval(minutes * 60))
        items.removeAll { $0.createdAt >= cutoff }
        selectedIndex = min(selectedIndex, max(filteredItems.count - 1, 0))
        persistCurrent()
    }

    @objc private func pollPasteboard() {
        guard storageReady else { return }
        let pasteboard = NSPasteboard.general
        guard preferences.clipboardEnabled, !preferences.clipboardPaused else {
            lastChangeCount = pasteboard.changeCount
            return
        }
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard !isSensitive(pasteboard), let capture = makeCapture(from: pasteboard) else { return }
        Task { [weak self, processor] in
            guard let processed = await processor.process(capture) else { return }
            self?.ingest(processed)
        }
    }

    private func finishLoading(_ result: ClipboardStoreLoadResult, storageByteCount: Int64) {
        switch result {
        case .missing:
            items = []
            storageError = nil
            persistenceWritable = true
        case let .loaded(loadedItems, warning):
            items = loadedItems
            storageError = warning
            persistenceWritable = true
        case let .unavailable(message), let .corrupted(message):
            items = []
            storageError = "\(message) 新记录仅保留在本次运行内存中。"
            persistenceWritable = false
        }
        storageReady = true
        isLoading = false
        self.storageByteCount = storageByteCount
        prune()
        if persistenceWritable { persistCurrent() }
    }

    private func ingest(_ processed: ProcessedClipboardCapture) {
        let item = processed.item
        items.removeAll { $0.hasSameContent(as: item) }
        items.insert(item, at: 0)
        sortItems()
        prune()
        let images = processed.originalImage.map { [item.id: $0] } ?? [:]
        persistCurrent(originalImages: images)
    }

    private func makeCapture(from pasteboard: NSPasteboard) -> ClipboardCapture? {
        let source = NSWorkspace.shared.frontmostApplication?.localizedName
        let createdAt = Date()

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return .files(paths: urls.map(\.path), sourceApplication: source, createdAt: createdAt)
        }
        if preferences.clipboardStoreImages {
            if let data = pasteboard.data(forType: .png) {
                return .image(data: data, isPNG: true, sourceApplication: source, createdAt: createdAt)
            }
            if let data = pasteboard.data(forType: .tiff) {
                return .image(data: data, isPNG: false, sourceApplication: source, createdAt: createdAt)
            }
        }
        if let text = pasteboard.string(forType: .string) {
            let policy = ClipboardTextPolicy(
                maximumCharacters: preferences.clipboardMaximumTextCharacters
            )
            guard policy.shouldStore(text) else { return nil }
            return .text(value: text, sourceApplication: source, createdAt: createdAt)
        }
        return nil
    }

    private func isSensitive(_ pasteboard: NSPasteboard) -> Bool {
        let sensitiveTypes = [
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType",
            "com.agilebits.onepassword"
        ]
        let presentTypes = Set((pasteboard.types ?? []).map(\.rawValue))
        if sensitiveTypes.contains(where: presentTypes.contains) { return true }

        let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() ?? ""
        if preferences.clipboardIgnoredBundleIDs.contains(bundleIdentifier) { return true }
        return ["1password", "bitwarden", "keepass", "enpass"]
            .contains { bundleIdentifier.contains($0) }
    }

    private func pruneAndPersist() {
        guard storageReady else { return }
        prune()
        persistCurrent()
    }

    private func scheduleFilter() {
        let delayMilliseconds = Int((preferences.searchInputDelay * 1_000).rounded())
        filterDebouncer.schedule(after: .milliseconds(delayMilliseconds)) { [weak self] in
            self?.rebuildFilteredItems()
        }
    }

    private func ensureFilterIsCurrent() {
        guard appliedQuery != query || appliedFilter != filter else { return }
        filterDebouncer.cancel()
        filterTask?.cancel()
        filterRevision += 1
        let revision = filterRevision
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = Self.filterItems(
            items,
            term: term,
            filter: filter,
            limit: maximumVisibleItems
        )
        applyFilteredItems(matches, query: query, filter: filter, revision: revision)
    }

    private func rebuildFilteredItems() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedQuery = query
        let requestedFilter = filter
        let snapshot = items
        filterTask?.cancel()
        filterRevision += 1
        let revision = filterRevision

        guard !term.isEmpty else {
            let matches = requestedFilter == .all
                ? Array(snapshot.prefix(maximumVisibleItems))
                : Array(snapshot.lazy.filter { $0.kind.rawValue == requestedFilter.rawValue }
                    .prefix(maximumVisibleItems))
            applyFilteredItems(matches, query: requestedQuery, filter: requestedFilter, revision: revision)
            return
        }

        let limit = maximumVisibleItems
        filterTask = Task.detached(priority: .userInitiated) { [weak self] in
            let matches = Self.filterItems(
                snapshot,
                term: term,
                filter: requestedFilter,
                limit: limit
            )
            guard !Task.isCancelled else { return }
            await self?.applyFilteredItems(
                matches,
                query: requestedQuery,
                filter: requestedFilter,
                revision: revision
            )
        }
    }

    private func applyFilteredItems(
        _ matches: [ClipboardHistoryItem],
        query requestedQuery: String,
        filter requestedFilter: Filter,
        revision: Int
    ) {
        guard revision == filterRevision,
              query == requestedQuery,
              filter == requestedFilter else { return }
        filteredItems = matches
        appliedQuery = requestedQuery
        appliedFilter = requestedFilter
        selectedIndex = min(selectedIndex, max(matches.count - 1, 0))
    }

    nonisolated private static func filterItems(
        _ items: [ClipboardHistoryItem],
        term: String,
        filter: Filter,
        limit: Int
    ) -> [ClipboardHistoryItem] {
        var matches: [ClipboardHistoryItem] = []
        matches.reserveCapacity(min(limit, items.count))
        for item in items {
            guard !Task.isCancelled else { return [] }
            let matchesType = filter == .all || item.kind.rawValue == filter.rawValue
            guard matchesType,
                  term.isEmpty
                    || item.displayText.localizedCaseInsensitiveContains(term)
                    || (item.sourceApplication?.localizedCaseInsensitiveContains(term) ?? false) else {
                continue
            }
            matches.append(item)
            if matches.count == limit { break }
        }
        return matches
    }

    private func prune() {
        let retentionInterval = TimeInterval(preferences.clipboardRetentionDays) * 24 * 60 * 60
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        items = Array(items.filter { $0.pinned || $0.createdAt >= cutoff }.prefix(preferences.clipboardMaximumItems))
        selectedIndex = min(selectedIndex, max(filteredItems.count - 1, 0))
    }

    private func sortItems() {
        items.sort {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.createdAt > $1.createdAt
        }
    }

    private func persistCurrent(originalImages: [UUID: Data] = [:]) {
        guard storageReady, persistenceWritable else { return }
        persistenceRevision += 1
        let revision = persistenceRevision
        let snapshot = items
        Task { [weak self, persistence] in
            do {
                guard let normalized = try await persistence.persist(
                    snapshot,
                    originalImages: originalImages,
                    revision: revision
                ) else { return }
                let byteCount = await persistence.diskUsage()
                guard let self, self.persistenceRevision == revision else { return }
                self.items = normalized
                self.storageByteCount = byteCount
                self.storageError = nil
            } catch {
                guard let self, self.persistenceRevision == revision else { return }
                self.persistenceWritable = false
                self.storageError = "剪贴板加密存储失败；后续修改仅保留在本次运行内存中：\(error.localizedDescription)"
            }
        }
    }

    private func writeToPasteboard(_ writer: (NSPasteboard) -> Void) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        writer(pasteboard)
        lastChangeCount = pasteboard.changeCount
    }
}
