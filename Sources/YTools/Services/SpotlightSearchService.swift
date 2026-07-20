import Foundation

@MainActor
final class SpotlightSearchService {
    private enum SearchMode {
        case defaultResults
        case open
        case reveal
        case content
        case tag
    }

    private struct ParsedRequest {
        let mode: SearchMode
        let term: String
    }

    private let preferences: AppPreferences
    private var metadataQuery: NSMetadataQuery?
    private var generation = 0
    private var activeGeneration = 0
    private var activeRequest: ParsedRequest?
    private var completion: (([LauncherResult]) -> Void)?

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    isolated deinit {
        metadataQuery?.stop()
        NotificationCenter.default.removeObserver(self)
    }

    func search(_ rawQuery: String, completion: @escaping ([LauncherResult]) -> Void) {
        generation += 1
        let requestedGeneration = generation
        cancelMetadataQuery()

        let normalized: String
        if rawQuery.hasPrefix(" ") {
            let term = rawQuery.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            normalized = term.isEmpty ? "" : "open \(term)"
        } else {
            normalized = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !normalized.isEmpty else {
            completion([])
            return
        }

        beginSearch(
            parse(normalized),
            generation: requestedGeneration,
            completion: completion
        )
    }

    func cancel() {
        generation += 1
        cancelMetadataQuery()
    }

    /// Invalidates callbacks without synchronously stopping MetadataQuery.
    /// `stop()` can briefly block the main run loop, so the input hot path only
    /// advances the generation. The next debounced search performs cleanup.
    func supersede() {
        generation += 1
        completion = nil
    }

    private func beginSearch(
        _ request: ParsedRequest,
        generation requestedGeneration: Int,
        completion: @escaping ([LauncherResult]) -> Void
    ) {
        guard !request.term.isEmpty,
              request.mode != .defaultResults || request.term.count >= 2 else {
            completion([])
            return
        }
        guard request.mode != .defaultResults || preferences.includeFilesInDefaultResults else {
            completion([])
            return
        }

        let query = NSMetadataQuery()
        let configuredScopes = preferences.searchScopePaths.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        query.searchScopes = configuredScopes.isEmpty
            ? [FileManager.default.homeDirectoryForCurrentUser]
            : configuredScopes
        switch request.mode {
        case .content:
            query.predicate = NSPredicate(
                format: "%K CONTAINS[cd] %@",
                NSMetadataItemTextContentKey,
                request.term
            )
        case .tag:
            query.predicate = NSPredicate(
                format: "ANY %K BEGINSWITH[cd] %@",
                "kMDItemUserTags",
                request.term
            )
        default:
            query.predicate = NSPredicate(
                format: "%K LIKE[cd] %@",
                NSMetadataItemFSNameKey,
                "*\(request.term)*"
            )
        }

        metadataQuery = query
        activeGeneration = requestedGeneration
        activeRequest = request
        self.completion = completion
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidFinish),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        if !query.start() {
            cancelMetadataQuery()
            completion([])
        }
    }

    @objc private func queryDidFinish(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery,
              metadataQuery === query,
              generation == activeGeneration,
              let activeRequest else { return }
        let output = results(from: query, request: activeRequest)
        let completion = completion
        cancelMetadataQuery()
        completion?(output)
    }

    private func results(from query: NSMetadataQuery, request: ParsedRequest) -> [LauncherResult] {
        query.disableUpdates()
        defer { query.enableUpdates() }
        let maximumResults = request.mode == .defaultResults
            ? preferences.maximumSearchResults
            : max(30, preferences.maximumSearchResults)
        var output: [LauncherResult] = []

        for index in 0..<min(query.resultCount, 100) {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            if url.pathExtension.lowercased() == "app" || path.contains("/Library/") { continue }
            let name = (item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)
                ?? url.lastPathComponent
            let prefixScore = name.lowercased().hasPrefix(request.term.lowercased()) ? 80 : 0
            let explicit = request.mode != .defaultResults
            let subtitle = request.mode == .tag
                ? "标签匹配 · \(displayPath(path))"
                : displayPath(path)
            output.append(LauncherResult(
                id: "spotlight:\(path)",
                moduleID: "spotlight",
                title: name,
                subtitle: subtitle,
                icon: .file(url),
                score: (explicit ? 680 : 260) + prefixScore,
                action: request.mode == .reveal ? .reveal(url) : .open(url)
            ))
            if output.count >= maximumResults { break }
        }
        return output
    }

    private func cancelMetadataQuery() {
        if let metadataQuery {
            NotificationCenter.default.removeObserver(
                self,
                name: .NSMetadataQueryDidFinishGathering,
                object: metadataQuery
            )
        }
        metadataQuery?.stop()
        metadataQuery = nil
        activeRequest = nil
        completion = nil
    }

    private func parse(_ query: String) -> ParsedRequest {
        let prefixes: [(String, SearchMode)] = [
            ("open ", .open),
            ("find ", .reveal),
            ("in ", .content),
            ("打开 ", .open),
            ("查找 ", .reveal),
            ("内容 ", .content),
            ("tag ", .tag),
            ("标签 ", .tag)
        ]
        let lowered = query.lowercased()
        for (prefix, mode) in prefixes where lowered.hasPrefix(prefix) {
            return ParsedRequest(
                mode: mode,
                term: String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            )
        }
        return ParsedRequest(mode: .defaultResults, term: query)
    }

    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
