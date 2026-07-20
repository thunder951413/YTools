import AppKit
import Combine
import YToolsCore

@MainActor
final class LauncherModel: ObservableObject {
    private struct LayoutState: Equatable {
        let itemCount: Int
        let isPending: Bool
    }

    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            queryDidChange()
        }
    }
    @Published private(set) var results: [LauncherResult] = []
    @Published private(set) var isSearchPending = false
    @Published var selectedIndex = 0 {
        didSet {
            guard selectedIndex != oldValue else { return }
            schedulePreviewUpdate()
        }
    }
    @Published var showsPreview = false {
        didSet {
            guard !showsPreview else { return }
            previewTask?.cancel()
            previewTask = nil
            displayedPreviewURL = nil
        }
    }
    @Published private(set) var displayedPreviewURL: URL?
    @Published private var actionMenu = ActionMenuController()
    @Published private var fileBufferStore = FileBufferStore()
    private var momentaryPreviewActive = false
    private var pinnedPreviewURL: URL?

    private let preferences: AppPreferences
    private let snippets: SnippetManager
    private let recentDocuments: RecentDocumentsManager
    private let spotlight: SpotlightSearchService
    private let searchCoordinator = SearchCoordinator()
    private let resultAggregator = ResultAggregator()
    private let actionDispatcher: ActionDispatcher
    private var spotlightResults: [LauncherResult] = []
    private var backgroundResults: [LauncherResult] = []
    private var searchTask: Task<Void, Never>?
    private let searchDebouncer = DebouncedAction()
    private let spotlightDebouncer = DebouncedAction()
    private var previewTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    var actions: [LauncherAction] { actionMenu.actions }
    var isShowingActions: Bool { actionMenu.isShowing }
    var selectedActionIndex: Int {
        get { actionMenu.selectedIndex }
        set { actionMenu.selectedIndex = newValue }
    }
    var fileBuffer: [URL] { fileBufferStore.urls }
    var layoutInvalidations: AnyPublisher<Void, Never> {
        Publishers.CombineLatest3($results, $actionMenu, $isSearchPending)
            .map { results, actionMenu, isPending in
                LayoutState(
                    itemCount: actionMenu.isShowing ? actionMenu.actions.count : results.count,
                    isPending: isPending
                )
            }
            .removeDuplicates()
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    init(
        preferences: AppPreferences,
        snippets: SnippetManager? = nil,
        recentDocuments: RecentDocumentsManager? = nil,
        onShowLargeType: @escaping (String) -> Void = { _ in },
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.preferences = preferences
        self.spotlight = SpotlightSearchService(preferences: preferences)
        let snippetModule = snippets ?? SnippetManager()
        let recentModule = recentDocuments ?? RecentDocumentsManager()
        self.snippets = snippetModule
        self.recentDocuments = recentModule
        self.actionDispatcher = ActionDispatcher(
            snippets: snippetModule,
            recentDocuments: recentModule,
            onOpenSettings: onOpenSettings,
            onShowLargeType: onShowLargeType
        )
        preferences.$enabledSearchContentTypes
            .dropFirst()
            .sink { [weak self] _ in self?.refreshImmediately() }
            .store(in: &cancellables)
        preferences.$applicationAliases
            .dropFirst()
            .sink { [weak self] _ in self?.refreshImmediately() }
            .store(in: &cancellables)
        preferences.$searchInputDelay
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleSearch() }
            .store(in: &cancellables)
        preferences.$previewSelectionDelay
            .dropFirst()
            .sink { [weak self] _ in self?.schedulePreviewUpdate() }
            .store(in: &cancellables)
        Task { [searchCoordinator] in await searchCoordinator.prepare() }
    }

    private func queryDidChange() {
        if actionMenu.isShowing { actionMenu.dismiss() }
        if showsPreview || pinnedPreviewURL != nil { endPreviewSession() }
        searchTask?.cancel()
        searchTask = nil
        spotlightDebouncer.cancel()
        // Keep typing responsive: invalidate the old callback now, and defer
        // the potentially blocking NSMetadataQuery.stop() to performSearch().
        spotlight.supersede()
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resetForEmptyQuery()
        } else {
            if !isSearchPending { isSearchPending = true }
            if !results.isEmpty {
                results = []
                if selectedIndex != 0 { selectedIndex = 0 }
            }
            scheduleSearch()
        }
    }

    private func scheduleSearch() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let delayMilliseconds = Int((preferences.searchInputDelay * 1_000).rounded())
        searchDebouncer.schedule(after: .milliseconds(delayMilliseconds)) { [weak self] in
            self?.performSearch()
        }
    }

    private func refreshImmediately() {
        searchDebouncer.cancel()
        spotlightDebouncer.cancel()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resetForEmptyQuery()
            return
        }
        performSearch()
    }

    private func performSearch() {
        let requestedQuery = query
        guard !requestedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resetForEmptyQuery()
            return
        }
        if !isSearchPending { isSearchPending = true }
        spotlightResults = []
        backgroundResults = []
        searchTask?.cancel()
        let request = BackgroundSearchRequest(
            query: requestedQuery,
            fileNavigationActive: isFileNavigationActive,
            showsHiddenFiles: preferences.fileNavigationShowsHiddenFiles,
            fileNavigationSort: preferences.fileNavigationSort,
            fileNavigationSortAscending: preferences.fileNavigationSortAscending,
            fileNavigationFoldersFirst: preferences.fileNavigationFoldersFirst,
            enabledContentTypes: preferences.enabledSearchContentTypes,
            applicationAliases: preferences.applicationAliases,
            requestModules: makeRequestModules(for: requestedQuery)
        )
        searchTask = Task { [weak self, searchCoordinator] in
            let results = await searchCoordinator.search(request)
            guard !Task.isCancelled, let self, self.query == requestedQuery else { return }
            self.backgroundResults = results
            self.isSearchPending = false
            self.rebuildResults()
        }
        let spotlightQuery = isFileNavigationActive || !preferences.isSearchContentEnabled(.files)
            ? ""
            : requestedQuery
        scheduleSpotlightSearch(spotlightQuery, requestedQuery: requestedQuery)
        rebuildResults()
    }

    private func resetForEmptyQuery() {
        searchDebouncer.cancel()
        searchTask?.cancel()
        searchTask = nil
        spotlightResults = []
        backgroundResults = []
        if isSearchPending { isSearchPending = false }
        if !results.isEmpty { results = [] }
        if selectedIndex != 0 { selectedIndex = 0 }
        // Let the key event render before stopping a potentially active query.
        spotlightDebouncer.schedule(after: .milliseconds(100)) { [weak self] in
            self?.spotlight.cancel()
        }
    }

    private func scheduleSpotlightSearch(_ spotlightQuery: String, requestedQuery: String) {
        guard !spotlightQuery.isEmpty else {
            spotlight.cancel()
            return
        }
        // Lightweight providers respond at the user-selected delay. Metadata
        // search receives a longer idle window so ordinary typing never starts
        // and immediately tears down an NSMetadataQuery between keystrokes.
        let additionalDelay = max(0, 0.3 - preferences.searchInputDelay)
        let start = { @MainActor [weak self] in
            guard let self, self.query == requestedQuery else { return }
            self.spotlight.search(spotlightQuery) { [weak self] results in
                guard let self, self.query == requestedQuery else { return }
                self.spotlightResults = results
                self.rebuildResults()
            }
        }
        guard additionalDelay > 0 else {
            start()
            return
        }
        let milliseconds = Int((additionalDelay * 1_000).rounded())
        spotlightDebouncer.schedule(after: .milliseconds(milliseconds), action: start)
    }

    private func rebuildResults() {
        let aggregated = resultAggregator.aggregate(
            background: backgroundResults,
            spotlight: spotlightResults,
            query: query,
            previousResults: results,
            selectedIndex: selectedIndex
        )
        results = aggregated.results
        selectedIndex = aggregated.selectedIndex
        if selectedFileURL == nil {
            showsPreview = false
        } else if showsPreview {
            schedulePreviewUpdate()
        }
    }

    private func makeRequestModules(for query: String) -> [RegisteredSearchModule] {
        let clipboardText = SnippetSearchModule.accepts(query)
            ? NSPasteboard.general.string(forType: .string) ?? ""
            : ""
        return [
            RegisteredSearchModule(
                snippets.searchModule(clipboardText: clipboardText),
                contentType: .snippets
            ),
            RegisteredSearchModule(
                recentDocuments.searchModule(),
                contentType: .recentDocuments,
                allowedCapabilities: [.localFileRead]
            ),
            RegisteredSearchModule(DictionaryModule(
                includeAutomaticResults: preferences.includeAutomaticDictionary
            ), contentType: .dictionary),
            RegisteredSearchModule(
                SystemCommandsModule(configuration: preferences.systemCommandConfiguration),
                contentType: .systemTools,
                allowsPrivilegedActions: true
            )
        ]
    }

    @discardableResult
    func activateSelected() -> Bool {
        if isShowingActions { return activateSelectedAction() }
        guard results.indices.contains(selectedIndex) else { return false }
        return activate(results[selectedIndex])
    }

    @discardableResult
    func activate(_ result: LauncherResult, recordUsage: Bool = true) -> Bool {
        if recordUsage { resultAggregator.record(result, query: query) }
        return apply(actionDispatcher.execute(result.action))
    }

    func moveSelection(by offset: Int) {
        if isShowingActions {
            actionMenu.moveSelection(by: offset)
            return
        }
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + offset + results.count) % results.count
    }

    @discardableResult
    func activateResult(at index: Int) -> Bool {
        guard !isShowingActions, results.indices.contains(index) else { return false }
        selectedIndex = index
        return activate(results[index])
    }

    var selectedFileURL: URL? {
        if let pinnedPreviewURL { return pinnedPreviewURL }
        if isShowingActions, let url = actionMenu.subject?.resourceURL { return url }
        guard results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex].fileURL
    }

    var actionSubjectTitle: String { actionMenu.title }

    var visibleItemCount: Int {
        isShowingActions ? actions.count : results.count
    }

    var isFileNavigationActive: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("/") || trimmed.hasPrefix("~")
    }

    func togglePreview() {
        guard selectedFileURL != nil else {
            showsPreview = false
            return
        }
        showsPreview.toggle()
        if showsPreview {
            displayPreviewImmediately()
        } else {
            pinnedPreviewURL = nil
        }
        momentaryPreviewActive = false
    }

    @discardableResult
    func beginMomentaryPreview() -> Bool {
        guard !isShowingActions, selectedFileURL != nil, !showsPreview else { return false }
        showsPreview = true
        displayPreviewImmediately()
        momentaryPreviewActive = true
        return true
    }

    func endMomentaryPreview() {
        guard momentaryPreviewActive else { return }
        showsPreview = false
        pinnedPreviewURL = nil
        momentaryPreviewActive = false
    }

    func endPreviewSession() {
        showsPreview = false
        pinnedPreviewURL = nil
        momentaryPreviewActive = false
    }

    private func displayPreviewImmediately() {
        previewTask?.cancel()
        previewTask = nil
        displayedPreviewURL = selectedFileURL
    }

    private func schedulePreviewUpdate() {
        guard showsPreview, pinnedPreviewURL == nil else { return }
        previewTask?.cancel()
        let requestedURL = selectedFileURL
        let delayMilliseconds = Int((preferences.previewSelectionDelay * 1_000).rounded())
        guard delayMilliseconds > 0 else {
            displayedPreviewURL = requestedURL
            previewTask = nil
            return
        }
        previewTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(delayMilliseconds))
            } catch {
                return
            }
            guard let self,
                  self.showsPreview,
                  self.pinnedPreviewURL == nil,
                  self.selectedFileURL == requestedURL else { return }
            self.displayedPreviewURL = requestedURL
            self.previewTask = nil
        }
    }

    @discardableResult
    func showActionsForSelected() -> Bool {
        guard !isShowingActions, results.indices.contains(selectedIndex) else { return false }
        guard actionMenu.show(for: results[selectedIndex]) else { return false }
        showsPreview = false
        pinnedPreviewURL = nil
        return true
    }

    @discardableResult
    func dismissSecondaryView() -> Bool {
        if showsPreview {
            showsPreview = false
            pinnedPreviewURL = nil
            momentaryPreviewActive = false
            return true
        }
        if isShowingActions {
            actionMenu.dismiss()
            return true
        }
        return false
    }

    func navigateToParent() -> Bool {
        guard isFileNavigationActive else { return false }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expanded = trimmed.hasPrefix("~") ? home + trimmed.dropFirst() : trimmed
        let withoutTrailingSlash = expanded.count > 1 && expanded.hasSuffix("/")
            ? String(expanded.dropLast())
            : expanded
        let parent = URL(fileURLWithPath: withoutTrailingSlash).deletingLastPathComponent().path
        if parent == home || parent.hasPrefix(home + "/") {
            query = "~" + parent.dropFirst(home.count) + "/"
        } else {
            query = parent == "/" ? "/" : parent + "/"
        }
        return true
    }

    func isBuffered(_ result: LauncherResult) -> Bool {
        guard let url = result.resourceURL else { return false }
        return fileBufferStore.contains(url)
    }

    @discardableResult
    func addSelectedToBuffer(moveToNext: Bool) -> Bool {
        guard !isShowingActions,
              results.indices.contains(selectedIndex),
              let url = results[selectedIndex].resourceURL else { return false }
        fileBufferStore.add(url)
        if moveToNext { moveSelection(by: 1) }
        return true
    }

    @discardableResult
    func removeLastBufferedItem() -> Bool {
        fileBufferStore.removeLast()
    }

    func clearFileBuffer() {
        fileBufferStore.clear()
    }

    @discardableResult
    func showFileBufferActions() -> Bool {
        guard actionMenu.show(forBufferedURLs: fileBufferStore.urls) else { return false }
        showsPreview = false
        pinnedPreviewURL = nil
        return true
    }

    private func activateSelectedAction() -> Bool {
        guard let action = actionMenu.selectedAction else { return false }
        if let subject = actionMenu.subject { resultAggregator.record(subject, query: query) }
        return apply(actionDispatcher.execute(action.kind))
    }

    @discardableResult
    func revealSelected() -> Bool {
        guard let url = selectedFileURL else { return false }
        resultAggregator.record(results[selectedIndex], query: query)
        return apply(actionDispatcher.execute(.perform(.reveal(url))))
    }

    func reveal(_ url: URL) {
        _ = actionDispatcher.execute(.perform(.reveal(url)))
    }

    func copyPath(_ url: URL) {
        _ = actionDispatcher.execute(.copyPath(url))
    }

    func clearUsageLearning() {
        resultAggregator.clearLearning()
        rebuildResults()
    }

    @discardableResult
    func clearQuery() -> Bool {
        guard !query.isEmpty else { return false }
        query = ""
        return true
    }

    var selectedLargeTypeText: String? {
        guard !isShowingActions, results.indices.contains(selectedIndex) else { return nil }
        let result = results[selectedIndex]
        if case let .copy(text) = result.action { return text }
        return result.title.isEmpty ? nil : result.title
    }

    private func apply(_ outcome: ActionExecutionOutcome) -> Bool {
        switch outcome {
        case .hidePanel:
            return true
        case .keepPanel:
            return false
        case let .navigate(path):
            query = path
            refreshImmediately()
            return false
        case let .preview(url):
            actionMenu.dismiss()
            pinnedPreviewURL = url
            displayedPreviewURL = url
            showsPreview = true
            return false
        case .clearFileBufferAndHide:
            fileBufferStore.clear()
            return true
        }
    }
}
