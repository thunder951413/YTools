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
    @Published private(set) var cloudSyncStatus = ""
    @Published var cloudUsernameInput = ""
    @Published var cloudAppPasswordInput = ""
    @Published var cloudSyncPassphraseInput = ""

    private let persistence = ClipboardPersistenceService()
    private let processor = ClipboardCaptureProcessor()
    private let preferences: AppPreferences
    private let cloudSync: ClipboardCloudSyncService
    private var timer: Timer?
    private var cloudPullTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var lastChangeCount: Int
    private var persistenceRevision = 0
    private var localDeletedForSync: [UUID: Date] = [:]
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
        self.cloudSync = ClipboardCloudSyncService()
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
        preferences.$clipboardCloudSyncEnabled.dropFirst().sink { [weak self] _ in
            self?.startCloudPullTimer()
        }.store(in: &cancellables)
        preferences.$clipboardCloudSyncFolder.dropFirst().sink { [weak self] _ in
            self?.startCloudPullTimer()
        }.store(in: &cancellables)
        preferences.$clipboardCloudSyncIntervalMinutes.dropFirst().sink { [weak self] _ in
            self?.startCloudPullTimer()
        }.store(in: &cancellables)
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        cloudPullTimer?.invalidate()
        cloudPullTimer = nil
        filterDebouncer.cancel()
        filterTask?.cancel()
        filterTask = nil
        cancellables.removeAll()
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
        persistCurrent(deletedIDs: [item.id])
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
        items[index].updatedAt = Date()
        sortItems()
        persistCurrent(changedItemID: item.id)
    }

    var selectedText: String? {
        ensureFilterIsCurrent()
        let visible = filteredItems
        guard visible.indices.contains(selectedIndex), visible[selectedIndex].kind == .text else { return nil }
        return visible[selectedIndex].payload.first
    }

    func clear() {
        let previous = items
        let deletedIDs = previous.map(\.id)
        let deletedAt = Date()
        deletedIDs.forEach { localDeletedForSync[$0] = deletedAt }
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
                await self.publishCloudDeletion(deletedIDs, timestamp: deletedAt)
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
        let deletedIDs = items.filter { $0.createdAt >= cutoff }.map(\.id)
        items.removeAll { $0.createdAt >= cutoff }
        selectedIndex = min(selectedIndex, max(filteredItems.count - 1, 0))
        persistCurrent(deletedIDs: deletedIDs)
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
        startCloudPullTimer()
    }

    private func ingest(_ processed: ProcessedClipboardCapture) {
        var item = processed.item
        if let existingIndex = items.firstIndex(where: { $0.hasSameContent(as: item) }) {
            items[existingIndex].copyCount += 1
            persistCurrent()
            return
        }
        item.updatedAt = item.createdAt
        items.insert(item, at: 0)
        sortItems()
        prune()
        let images = processed.originalImage.map { [item.id: $0] } ?? [:]
        persistCurrent(originalImages: images, changedItemID: item.id)
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

    private func persistCurrent(
        originalImages: [UUID: Data] = [:],
        changedItemID: UUID? = nil,
        deletedIDs: [UUID] = [],
        acknowledge: [ClipboardCloudSyncService.Event] = []
    ) {
        guard storageReady, persistenceWritable else { return }
        let deletedAt = Date()
        deletedIDs.forEach { localDeletedForSync[$0] = deletedAt }
        persistenceRevision += 1
        let revision = persistenceRevision
        let snapshot = items
        Task { [weak self, persistence] in
            do {
                let normalized = try await persistence.persist(
                    snapshot,
                    originalImages: originalImages,
                    revision: revision
                )
                let byteCount = await persistence.diskUsage()
                guard let self else { return }
                if self.persistenceRevision == revision, let normalized {
                    self.items = normalized
                    self.storageByteCount = byteCount
                    self.storageError = nil
                }
                if !acknowledge.isEmpty {
                    do { try await self.cloudSync.acknowledge(acknowledge) }
                    catch { self.cloudSyncStatus = "同步确认待重试：\(error.localizedDescription)" }
                }
                // Publishing an event is independent of whether its old UI
                // snapshot can still be displayed.
                if let changedItemID, let changedItem = snapshot.first(where: { $0.id == changedItemID }) {
                    await self.publishCloudChange(changedItem)
                } else if !deletedIDs.isEmpty {
                    await self.publishCloudDeletion(deletedIDs, timestamp: deletedAt)
                }
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

    func saveCloudSyncCredentials(username: String, appPassword: String, syncPassphrase: String) async -> String? {
        let error = await cloudSync.saveCredentials(username: username, appPassword: appPassword, syncPassphrase: syncPassphrase)
        cloudSyncStatus = error ?? "坚果云同步凭据已加密保存。"
        if error == nil {
            cloudAppPasswordInput = ""
            cloudSyncPassphraseInput = ""
        }
        return error
    }

    private var cloudConfiguration: ClipboardCloudSyncService.Configuration {
        .init(enabled: preferences.clipboardCloudSyncEnabled, folder: preferences.clipboardCloudSyncFolder)
    }

    func syncCloudNow() async {
        guard storageReady, persistenceWritable else { return }
        cloudSyncStatus = "正在同步坚果云剪贴板…"
        await applyCloudResult(await cloudSync.synchronize(configuration: cloudConfiguration))
    }

    private func publishCloudChange(_ item: ClipboardHistoryItem) async {
        var publishable = item
        if item.kind == .image {
            let original = await persistence.imageData(for: item.id)
            publishable = ClipboardHistoryItem(id: item.id, kind: item.kind, payload: item.payload,
                createdAt: item.createdAt, sourceApplication: item.sourceApplication,
                binaryData: original, contentHash: item.contentHash, isPinned: item.pinned,
                updatedAt: item.updatedAt, copyCount: item.copyCount)
        }
        await applyCloudResult(await cloudSync.publishChangedItem(publishable, configuration: cloudConfiguration))
    }

    private func publishCloudDeletion(_ ids: [UUID], timestamp: Date) async {
        await applyCloudResult(await cloudSync.publishDeleted(ids, timestamp: timestamp, configuration: cloudConfiguration))
    }

    private func applyCloudResult(_ result: ClipboardCloudSyncService.Result) async {
        guard !result.message.isEmpty else { return }
        cloudSyncStatus = result.message
        guard result.success, let events = result.events, persistenceWritable else { return }
        var deleted = await cloudSync.deletionSnapshot()
        for (id, date) in localDeletedForSync { deleted[id] = max(deleted[id] ?? .distantPast, date) }
        // Read items after the await: local edits may have occurred meanwhile.
        items = ClipboardCloudSyncService.apply(events: events, to: items, deleted: deleted)
        prune()
        persistCurrent(acknowledge: events)
    }

    private func startCloudPullTimer() {
        cloudPullTimer?.invalidate()
        cloudPullTimer = nil
        guard storageReady, preferences.clipboardCloudSyncEnabled else { return }
        Task { [weak self] in
            guard let self else { return }
            let events = await self.cloudSync.pendingEvents()
            if !events.isEmpty {
                await self.applyCloudResult(.init(success: true, items: nil, message: "正在恢复已接收的剪贴板变更…", events: events))
            }
        }
        cloudPullTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(preferences.clipboardCloudSyncIntervalMinutes * 60),
            repeats: true
        ) { [weak self] _ in
            Task { await self?.syncCloudNow() }
        }
    }
}
