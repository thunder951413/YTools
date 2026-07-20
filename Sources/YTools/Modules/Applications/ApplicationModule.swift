import Foundation
import YToolsCore

actor ApplicationModule {
    let id = "applications"

    private struct Application {
        let name: String
        let url: URL
        let searchForms: SearchTextForms
    }

    private let fileManager: FileManager
    private let normalizer = SearchTextNormalizer()
    private let aliasMatcher = ApplicationAliasMatcher()
    private let roots: [URL]
    private var applications: [Application] = []
    private var lastScanAt = Date.distantPast
    private var watcher: ApplicationDirectoryWatcher?
    private var indexIsDirty = true

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    func prepare() {
        startWatchingIfNeeded()
        if indexIsDirty { refreshApplications() }
    }

    func results(for query: String, aliases: [String: String] = [:]) -> [LauncherResult] {
        startWatchingIfNeeded()
        if indexIsDirty || Date().timeIntervalSince(lastScanAt) > 300 {
            refreshApplications()
        }
        guard !Task.isCancelled else { return [] }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        let termForms = normalizer.forms(for: term)

        return applications.compactMap { application in
            guard !Task.isCancelled else { return nil }
            let nameScore = matchScore(application, term: term, forms: termForms)
            let aliasScore = aliases[application.url.path].flatMap {
                aliasMatcher.score(query: term, aliases: aliasMatcher.aliases(from: $0))
            }
            let score = [nameScore, aliasScore].compactMap { $0 }.max()
            guard let score else { return nil }
            return LauncherResult(
                id: "application:\(application.url.path)",
                moduleID: id,
                title: application.name,
                subtitle: application.url.path,
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

    private func refreshApplications() {
        var urlsByPath: [String: URL] = [:]
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                urlsByPath[url.path] = url
            }
        }

        applications = urlsByPath.values.map { url in
            let name = url.deletingPathExtension().lastPathComponent
            return Application(name: name, url: url, searchForms: normalizer.forms(for: name))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        lastScanAt = Date()
        indexIsDirty = false
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
        indexIsDirty = true
    }

}
