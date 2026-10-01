import Foundation

/// Validates and canonicalizes local macOS application bundle paths.
public enum MacApplicationPathPolicy {
    /// Returns a canonical application path when it satisfies the requested
    /// format-only or strict bundle validation level.
    public static func normalize(path: String, requireExistingBundle: Bool) -> String? {
        guard path.hasPrefix("/") else { return nil }
        return normalize(url: URL(fileURLWithPath: path), requireExistingBundle: requireExistingBundle)
    }

    /// Returns a canonical application path when it satisfies the requested
    /// format-only or strict bundle validation level.
    public static func normalize(url: URL, requireExistingBundle: Bool) -> String? {
        guard url.isFileURL,
              url.host == nil || url.host?.isEmpty == true || url.host == "localhost" else {
            return nil
        }

        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        guard canonicalURL.path.hasPrefix("/"),
              canonicalURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            return nil
        }

        guard requireExistingBundle else { return canonicalURL.path }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonicalURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              Bundle(url: canonicalURL)?.bundleIdentifier != nil else {
            return nil
        }
        return canonicalURL.path
    }

    /// Normalizes, case-insensitively deduplicates, and sorts application paths.
    public static func normalize(paths: [String], requireExistingBundle: Bool) -> [String] {
        var seen: Set<String> = []
        let normalized = paths.compactMap {
            normalize(path: $0, requireExistingBundle: requireExistingBundle)
        }.filter { seen.insert($0.lowercased()).inserted }

        return normalized.sorted { left, right in
            let comparison = left.caseInsensitiveCompare(right)
            return comparison == .orderedSame ? left < right : comparison == .orderedAscending
        }
    }
}
