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
        case pinned

        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "全部"
            case .text: "文本"
            case .files: "文件"
            case .image: "图片"
            case .pinned: "固定"
            }
        }
    }

    @Published private(set) var items: [ClipboardHistoryItem] = [] {
        didSet { rebuildFilteredItems() }
    }
    @Published private(set) var totalMatches = 0
    var hasMore: Bool { filteredItems.count < totalMatches }
    @Published private(set) var filteredItems: [ClipboardHistoryItem] = []
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            filterRevision += 1
            filterTask?.cancel()
            visibleLimit = pageSize
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
            visibleLimit = pageSize
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
    @Published private(set) var copyError: String?
    @Published private(set) var isCopying = false
    @Published private(set) var isClearing = false
    @Published var cloudUsernameInput = ""
    @Published var cloudAppPasswordInput = ""
    @Published var cloudSyncPassphraseInput = ""

    private let persistence: ClipboardPersistenceService
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
    private let pageSize = 100
    private var visibleLimit = 100
    private var appliedLimit = 100
    private var localWorkTail: Task<Void, Never>?
    private var localWorkGeneration = 0
    private var isShuttingDown = false
    private var uploadTask: Task<Void, Never>?
    private var uploadRequested = false
    private let pasteboard: NSPasteboard
    private var loadingTask: Task<Void, Never>?

    var layoutInvalidations: AnyPublisher<Void, Never> {
        $filteredItems
            .map(\.count)
            .removeDuplicates()
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    init(preferences: AppPreferences, persistence: ClipboardPersistenceService = ClipboardPersistenceService(),
         cloudSync: ClipboardCloudSyncService = ClipboardCloudSyncService(),
         pasteboard: NSPasteboard = .general, monitorsClipboard: Bool = true) {
        self.preferences = preferences
        self.persistence = persistence
        self.cloudSync = cloudSync
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        super.init()

        scheduleLocalWork { [weak self, persistence] in
            let result = await persistence.load()
            let byteCount = await persistence.diskUsage()
            self?.finishLoading(result, storageByteCount: byteCount)
        }
        loadingTask = localWorkTail
        if monitorsClipboard {
            timer = Timer.scheduledTimer(timeInterval: 0.5, target: self,
                selector: #selector(pollPasteboard), userInfo: nil, repeats: true)
        }
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
        isShuttingDown = true
        timer?.invalidate()
        timer = nil
        cloudPullTimer?.invalidate()
        cloudPullTimer = nil
        filterDebouncer.cancel()
        filterTask?.cancel()
        filterTask = nil
        cancellables.removeAll()
    }

    func flushPendingChanges() async {
        shutdown()
        // Local jobs may append a follow-up save (capture -> ingest -> persist).
        // Drain until the last scheduled generation has completed.
        while let tail = localWorkTail {
            let generation = localWorkGeneration
            await tail.value
            if generation == localWorkGeneration {
                localWorkTail = nil
                break
            }
        }
    }

    func waitUntilLoaded() async { await loadingTask?.value }

    private func scheduleLocalWork(_ operation: @escaping @MainActor () async -> Void) {
        let previous = localWorkTail
        localWorkGeneration += 1
        localWorkTail = Task {
            await previous?.value
            await operation()
        }
    }

    func loadMore() {
        guard hasMore else { return }
        visibleLimit += pageSize
        rebuildFilteredItems()
    }

    func prepareForPresentation() {
        visibleLimit = pageSize
        query = ""
        filter = .all
        selectedIndex = 0
        rebuildFilteredItems()
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
    func copySelected() async -> Bool {
        ensureFilterIsCurrent()
        let visible = filteredItems
        guard visible.indices.contains(selectedIndex) else { return false }
        return await copy(visible[selectedIndex])
    }

    @discardableResult
    func copy(_ item: ClipboardHistoryItem) async -> Bool {
        guard !isCopying, !isShuttingDown else { return false }
        isCopying = true
        copyError = nil
        defer { isCopying = false }
        let success: Bool
        switch item.kind {
        case .text:
            success = item.payload.first.map { text in
                writeToPasteboard { $0.setString(text, forType: .string) }
            } ?? false
        case .files:
            let urls = item.payload.map { NSURL(fileURLWithPath: $0) }
            success = !urls.isEmpty && writeToPasteboard { $0.writeObjects(urls) }
        case .image:
            guard let data = await persistence.imageData(for: item.id) else {
                copyError = "无法读取图片原件，请选择其他记录或稍后重试。"
                return false
            }
            guard !isShuttingDown else { return false }
            success = writeToPasteboard { $0.setData(data, forType: .png) }
        }
        guard success else {
            copyError = "无法写入系统剪贴板，请稍后重试。"
            return false
        }
        promoteToTop(item)
        return true
    }

    private func promoteToTop(_ item: ClipboardHistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let existing = items[index]
        let now = Date()
        items[index] = ClipboardHistoryItem(id: existing.id, kind: existing.kind, payload: existing.payload,
            createdAt: now, sourceApplication: existing.sourceApplication, binaryData: existing.binaryData,
            contentHash: existing.contentHash, isPinned: existing.pinned, updatedAt: now, copyCount: existing.copyCount)
        sortItems()
        persistCurrent(changedItemID: item.id)
    }

    func delete(_ item: ClipboardHistoryItem) {
        guard !isClearing else { return }
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
        guard !isClearing else { return }
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
        guard storageReady, !isClearing else { return }
        isClearing = true
        let previous = items
        let deletedIDs = previous.map(\.id)
        let deletedAt = Date()
        deletedIDs.forEach { localDeletedForSync[$0] = deletedAt }
        items.removeAll()
        selectedIndex = 0
        persistenceRevision += 1
        let revision = persistenceRevision
        let configuration = cloudConfiguration
        persistenceWritable = false
        scheduleLocalWork { [weak self, persistence] in
            defer { self?.isClearing = false }
            do {
                try await persistence.clear(revision: revision)
                guard let self else { return }
                if self.persistenceRevision == revision {
                    self.persistenceWritable = true
                    self.storageError = nil
                    self.storageByteCount = 0
                    if !self.items.isEmpty { self.persistCurrent() }
                }
                await self.enqueueCloudDeletion(deletedIDs, timestamp: deletedAt, configuration: configuration)
            } catch {
                guard let self, self.persistenceRevision == revision else { return }
                self.items = previous
                self.persistenceWritable = false
                self.storageError = "无法清除剪贴板密文：\(error.localizedDescription)"
            }
        }
    }

    func clearRecent(minutes: Int) {
        guard !isClearing else { return }
        let cutoff = Date().addingTimeInterval(-TimeInterval(minutes * 60))
        let deletedIDs = items.filter { $0.createdAt >= cutoff }.map(\.id)
        items.removeAll { $0.createdAt >= cutoff }
        selectedIndex = min(selectedIndex, max(filteredItems.count - 1, 0))
        persistCurrent(deletedIDs: deletedIDs)
    }

    @objc private func pollPasteboard() {
        guard storageReady, !isShuttingDown else { return }
        let pasteboard = self.pasteboard
        guard preferences.clipboardEnabled, !preferences.clipboardPaused else {
            lastChangeCount = pasteboard.changeCount
            return
        }
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard !isSensitive(pasteboard), let capture = makeCapture(from: pasteboard) else { return }
        scheduleLocalWork { [weak self, processor] in
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
        guard appliedQuery != query || appliedFilter != filter || appliedLimit != visibleLimit else { return }
        filterDebouncer.cancel()
        filterTask?.cancel()
        filterRevision += 1
        let revision = filterRevision
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = Self.filterItems(
            items,
            term: term,
            filter: filter,
            limit: visibleLimit
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
            let matches = Self.filterItems(snapshot, term: term, filter: requestedFilter, limit: visibleLimit)
            applyFilteredItems(matches, query: requestedQuery, filter: requestedFilter, revision: revision)
            return
        }

        let limit = visibleLimit
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
        _ page: HistoryPage<ClipboardHistoryItem>,
        query requestedQuery: String,
        filter requestedFilter: Filter,
        revision: Int
    ) {
        guard revision == filterRevision,
              query == requestedQuery,
              filter == requestedFilter else { return }
        let selectedID = appliedQuery == requestedQuery && appliedFilter == requestedFilter
            && filteredItems.indices.contains(selectedIndex) ? filteredItems[selectedIndex].id : nil
        filteredItems = page.items
        totalMatches = page.totalMatches
        appliedLimit = visibleLimit
        appliedQuery = requestedQuery
        appliedFilter = requestedFilter
        selectedIndex = selectedID.flatMap { id in page.items.firstIndex { $0.id == id } }
            ?? min(selectedIndex, max(page.items.count - 1, 0))
    }

    nonisolated private static func filterItems(
        _ items: [ClipboardHistoryItem],
        term: String,
        filter: Filter,
        limit: Int
    ) -> HistoryPage<ClipboardHistoryItem> {
        HistoryPage.select(items, limit: limit) { item in
            let matchesType = filter == .all || (filter == .pinned ? item.pinned : item.kind.rawValue == filter.rawValue)
            return matchesType && (term.isEmpty
                || item.displayText.localizedCaseInsensitiveContains(term)
                || (item.sourceApplication?.localizedCaseInsensitiveContains(term) ?? false))
        }
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
        let configuration = cloudConfiguration
        scheduleLocalWork { [weak self, persistence] in
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
                    await self.enqueueCloudChange(changedItem, originalImage: originalImages[changedItem.id], configuration: configuration)
                } else if !deletedIDs.isEmpty {
                    await self.enqueueCloudDeletion(deletedIDs, timestamp: deletedAt, configuration: configuration)
                }
            } catch {
                guard let self, self.persistenceRevision == revision else { return }
                self.persistenceWritable = false
                self.storageError = "剪贴板加密存储失败；后续修改仅保留在本次运行内存中：\(error.localizedDescription)"
            }
        }
    }

    private func writeToPasteboard(_ writer: (NSPasteboard) -> Bool) -> Bool {
        let pasteboard = self.pasteboard
        pasteboard.clearContents()
        let success = writer(pasteboard)
        lastChangeCount = pasteboard.changeCount
        return success
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

    private func enqueueCloudChange(_ item: ClipboardHistoryItem, originalImage: Data? = nil,
                                    configuration: ClipboardCloudSyncService.Configuration) async {
        var publishable = item
        if item.kind == .image {
            let original: Data?
            if let originalImage { original = originalImage }
            else { original = await persistence.imageData(for: item.id) }
            publishable = ClipboardHistoryItem(id: item.id, kind: item.kind, payload: item.payload,
                createdAt: item.createdAt, sourceApplication: item.sourceApplication,
                binaryData: original, contentHash: item.contentHash, isPinned: item.pinned,
                updatedAt: item.updatedAt, copyCount: item.copyCount)
        }
        await handleEnqueueResult(await cloudSync.enqueueChangedItem(publishable, configuration: configuration))
    }

    private func enqueueCloudDeletion(_ ids: [UUID], timestamp: Date,
                                      configuration: ClipboardCloudSyncService.Configuration) async {
        await handleEnqueueResult(await cloudSync.enqueueDeleted(ids, timestamp: timestamp, configuration: configuration))
    }

    private func handleEnqueueResult(_ result: ClipboardCloudSyncService.Result) async {
        if !result.message.isEmpty { cloudSyncStatus = result.message }
        guard result.success, !result.message.isEmpty, !isShuttingDown else { return }
        uploadRequested = true
        guard uploadTask == nil else { return }
        uploadTask = Task { [weak self] in
            guard let self else { return }
            while self.uploadRequested, !self.isShuttingDown {
                self.uploadRequested = false
                await self.applyCloudResult(await self.cloudSync.uploadPending(configuration: self.cloudConfiguration))
            }
            self.uploadTask = nil
        }
    }

    private func applyCloudResult(_ result: ClipboardCloudSyncService.Result) async {
        guard !isShuttingDown else { return }
        guard !result.message.isEmpty else { return }
        cloudSyncStatus = result.message
        guard result.success, let events = result.events, persistenceWritable else { return }
        var deleted = await cloudSync.deletionSnapshot()
        guard !isShuttingDown else { return }
        for (id, date) in localDeletedForSync { deleted[id] = max(deleted[id] ?? .distantPast, date) }
        // Read items after the await: local edits may have occurred meanwhile.
        items = ClipboardCloudSyncService.apply(events: events, to: items, deleted: deleted)
        prune()
        persistCurrent(acknowledge: events)
    }

    private func startCloudPullTimer() {
        cloudPullTimer?.invalidate()
        cloudPullTimer = nil
        guard storageReady, !isShuttingDown, preferences.clipboardCloudSyncEnabled else { return }
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
