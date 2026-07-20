import Foundation

struct FileNavigationModule: Sendable {
    func results(
        for query: String,
        showsHiddenFiles: Bool,
        sort: FileNavigationSort,
        ascending: Bool,
        foldersFirst: Bool
    ) -> [LauncherResult] {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.hasPrefix("/") || input.hasPrefix("~") else { return [] }

        let expanded = expandTilde(input)
        var isDirectory: ObjCBool = false
        let existsAsDirectory = FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory)
            && isDirectory.boolValue

        let directoryURL: URL
        let filter: String
        if input.hasSuffix("/") || existsAsDirectory {
            directoryURL = URL(fileURLWithPath: expanded, isDirectory: true)
            filter = ""
        } else {
            let candidate = URL(fileURLWithPath: expanded)
            directoryURL = candidate.deletingLastPathComponent()
            filter = candidate.lastPathComponent
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isHiddenKey,
                .creationDateKey,
                .contentModificationDateKey
            ],
            options: showsHiddenFiles ? [] : [.skipsHiddenFiles]
        ) else { return [] }
        guard !Task.isCancelled else { return [] }

        let matched = contents.compactMap { url -> (URL, Bool, Date, Date)? in
            guard matches(url.lastPathComponent, filter: filter),
                  let values = try? url.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isHiddenKey,
                    .creationDateKey,
                    .contentModificationDateKey
                  ]),
                  showsHiddenFiles || values.isHidden != true else {
                return nil
            }
            return (
                url,
                values.isDirectory == true,
                values.creationDate ?? .distantPast,
                values.contentModificationDate ?? .distantPast
            )
        }
        .sorted { left, right in
            if foldersFirst, left.1 != right.1 { return left.1 && !right.1 }
            switch sort {
            case .name:
                let comparison = left.0.lastPathComponent.localizedStandardCompare(right.0.lastPathComponent)
                return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
            case .created:
                return ascending ? left.2 < right.2 : left.2 > right.2
            case .modified:
                return ascending ? left.3 < right.3 : left.3 > right.3
            }
        }

        return matched.prefix(40).map { url, isDirectory, _, _ in
            LauncherResult(
                id: "file-navigation:\(url.path)",
                moduleID: "file-navigation",
                title: url.lastPathComponent,
                subtitle: displayPath(url.path),
                icon: .file(url),
                score: isDirectory ? 920 : 900,
                action: isDirectory ? .navigate(navigationQuery(for: url)) : .open(url)
            )
        }
    }

    private func matches(_ name: String, filter: String) -> Bool {
        guard !filter.isEmpty else { return true }
        guard filter.contains("*") else { return name.localizedCaseInsensitiveContains(filter) }
        let pattern = filter.split(separator: "*", omittingEmptySubsequences: false)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: ".*")
        return name.range(of: "^\(pattern)$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return FileManager.default.homeDirectoryForCurrentUser.path + path.dropFirst()
    }

    private func navigationQuery(for url: URL) -> String {
        let path = displayPath(url.path)
        return path.hasSuffix("/") ? path : path + "/"
    }

    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
