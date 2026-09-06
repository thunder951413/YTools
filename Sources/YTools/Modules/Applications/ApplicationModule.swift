import Foundation
import YToolsCore

actor ApplicationModule {
    let id = "applications"

    private struct Application {
        let name: String
        let url: URL
        let canonicalPath: String
        let searchForms: SearchTextForms
        let isCustom: Bool
    }

    typealias ApplicationScanner = @Sendable ([URL]) -> [URL]

    private let normalizer = SearchTextNormalizer()
    private let aliasMatcher = ApplicationAliasMatcher()
    private let roots: [URL]
    private let scanApplications: ApplicationScanner
    private var standardApplications: [Application] = []
    private var customApplications: [Application] = []
    private var normalizedCustomApplicationPaths: [String] = []
    private var lastScanAt = Date.distantPast
    private var watcher: ApplicationDirectoryWatcher?
    private var indexIsDirty = true
    private var invalidationGeneration = 0
    private var initialScanCompleted = false
    private var refreshTask: Task<Void, Never>?

    init() {
        let fileManager = FileManager.default
        roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        scanApplications = Self.scanApplicationURLs
    }

    /// Test-only dependency injection stays internal to the executable module.
    init(roots: [URL]) {
        self.roots = roots
        self.scanApplications = Self.scanApplicationURLs
    }

    init(roots: [URL], scan: @escaping ApplicationScanner) {
        self.roots = roots
        self.scanApplications = scan
    }

    func prepare() async {
        startWatchingIfNeeded()
        guard !initialScanCompleted else { return }
        enqueueRefreshIfNeeded()
        let task = refreshTask
        await task?.value
    }

    func results(
        for query: String,
        aliases: [String: String] = [:],
        customApplicationPaths: [String] = []
    ) async -> [LauncherResult] {
        startWatchingIfNeeded()
        rebuildCustomApplicationsIfNeeded(customApplicationPaths)

        // A search may win the startup race with prepare(). In that one case
        // waiting is preferable to publishing a misleading empty index.
        if !initialScanCompleted {
            enqueueRefreshIfNeeded()
            let task = refreshTask
            await task?.value
        } else if indexIsDirty || Date().timeIntervalSince(lastScanAt) > 300 {
            // Later invalidations never synchronously enumerate Applications.
            // The current snapshot remains searchable while one refresh runs.
            enqueueRefreshIfNeeded()
        }

        guard !Task.isCancelled else { return [] }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        let termForms = normalizer.forms(for: term)

        return indexedApplications().compactMap { application in
            guard !Task.isCancelled else { return nil }
            let nameScore = matchScore(application, term: term, forms: termForms)
            let aliasScore = aliases[application.canonicalPath].flatMap {
                aliasMatcher.score(query: term, aliases: aliasMatcher.aliases(from: $0))
            }
            let score = [nameScore, aliasScore].compactMap { $0 }.max()
            guard let score else { return nil }
            return LauncherResult(
                id: "application:\(application.canonicalPath)",
                moduleID: id,
                title: application.name,
                subtitle: application.isCustom
                    ? "自定义应用 · \(application.canonicalPath)"
                    : application.canonicalPath,
                icon: .application(application.url),
                score: score,
                action: .open(application.url)
            )
        }
        .sorted {
            if $0.score == $1.score { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return $0.score > $1.score
        }
        .prefix(12)
        .map { $0 }
    }

    private func indexedApplications() -> [Application] {
        var seenPaths = Set<String>()
        return (standardApplications + customApplications).filter {
            seenPaths.insert($0.canonicalPath.lowercased()).inserted
        }
    }

    private func rebuildCustomApplicationsIfNeeded(_ paths: [String]) {
        let normalizedPaths = MacApplicationPathPolicy.normalize(
            paths: paths,
            requireExistingBundle: true
        )
        guard normalizedPaths != normalizedCustomApplicationPaths else { return }
        normalizedCustomApplicationPaths = normalizedPaths
        customApplications = normalizedPaths.map {
            makeApplication(URL(fileURLWithPath: $0, isDirectory: true), isCustom: true)
        }
    }

    private func enqueueRefreshIfNeeded() {
        guard refreshTask == nil else { return }
        let roots = roots
        let scanner = scanApplications
        let scanGeneration = invalidationGeneration
        refreshTask = Task { [weak self] in
            let urls = await Task.detached(priority: .utility) {
                scanner(roots)
            }.value
            guard !Task.isCancelled else { return }
            await self?.finishRefresh(urls, scanGeneration: scanGeneration)
        }
    }

    private func finishRefresh(_ urls: [URL], scanGeneration: Int) {
        standardApplications = urls.map { makeApplication($0, isCustom: false) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        lastScanAt = Date()
        initialScanCompleted = true
        refreshTask = nil
        // A watcher event received while scanning invalidates this snapshot too.
        // Keep it dirty so the next query schedules exactly one newer scan.
        if invalidationGeneration == scanGeneration {
            indexIsDirty = false
        }
    }

    private func makeApplication(_ url: URL, isCustom: Bool) -> Application {
        let canonicalPath = MacApplicationPathPolicy.normalize(
            url: url,
            requireExistingBundle: false
        ) ?? url.standardizedFileURL.path
        let applicationURL = URL(fileURLWithPath: canonicalPath, isDirectory: true)
        let name = applicationURL.deletingPathExtension().lastPathComponent
        return Application(
            name: name,
            url: applicationURL,
            canonicalPath: canonicalPath,
            searchForms: normalizer.forms(for: name),
            isCustom: isCustom
        )
    }

    private static func scanApplicationURLs(roots: [URL]) -> [URL] {
        let fileManager = FileManager.default
        var urlsByPath: [String: URL] = [:]
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                urlsByPath[url.standardizedFileURL.path] = url
            }
        }
        return urlsByPath.values.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func matchScore(
        _ application: Application,
        term: String,
        forms: SearchTextForms
    ) -> Int? {
        if application.name.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return 900
        }
        let candidate = application.searchForms
        if candidate.normalized.hasPrefix(forms.normalized) { return 760 }
        if candidate.normalized.contains(forms.normalized) { return 560 }
        if candidate.abbreviation.hasPrefix(forms.normalized) { return 500 }
        if candidate.transliteration == forms.normalized { return 740 }
        if candidate.transliteration.hasPrefix(forms.normalized) { return 700 }
        if candidate.transliteration.contains(forms.normalized) { return 520 }
        if candidate.transliterationInitials.hasPrefix(forms.normalized) { return 620 }
        // Keep one-character searches precise. For longer queries, tolerate
        // omitted characters in the same way mature launchers do (slk → Slack).
        if forms.normalized.count >= 2,
           let fuzzy = normalizer.fuzzyScore(query: forms.normalized, candidate: candidate.normalized) {
            return 390 + fuzzy
        }
        if forms.normalized.count >= 2,
           let fuzzy = normalizer.fuzzyScore(query: forms.normalized, candidate: candidate.transliteration) {
            return 380 + fuzzy
        }
        return nil
    }

    private func startWatchingIfNeeded() {
        guard watcher == nil else { return }
        watcher = ApplicationDirectoryWatcher(urls: roots) { [weak self] in
            Task { await self?.invalidateIndex() }
        }
    }

    private func invalidateIndex() {
        invalidationGeneration += 1
        indexIsDirty = true
    }

    func invalidateIndexForTesting() {
        invalidateIndex()
    }

    func waitForRefreshForTesting() async {
        let task = refreshTask
        await task?.value
    }
}
