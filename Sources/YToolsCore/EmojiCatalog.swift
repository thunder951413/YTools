import Foundation

/// Offline emoji and symbol search with Chinese names, English keywords and
/// pinyin matching. Data lives in `Resources/Emoji/emoji.tsv` (shared with
/// Windows); `EmojiCatalogData.tsv` embeds an identical copy because the app
/// bundle does not ship SwiftPM resource bundles.
public struct EmojiEntry: Equatable, Sendable {
    public let glyph: String
    public let name: String
    public let keywords: [String]
    public let acceptsSkinTone: Bool

    public func glyph(skinTone: Int) -> String {
        guard acceptsSkinTone, (1...5).contains(skinTone),
              let modifier = Unicode.Scalar(UInt32(0x1F3FA + skinTone)) else { return glyph }
        var scalars = Array(glyph.unicodeScalars)
        guard !scalars.isEmpty else { return glyph }
        // Drop a variation selector after the base, then insert the modifier.
        if scalars.count > 1, scalars[1].value == 0xFE0F { scalars.remove(at: 1) }
        scalars.insert(modifier, at: 1)
        var output = String.UnicodeScalarView()
        output.append(contentsOf: scalars)
        return String(output)
    }
}

public struct EmojiCatalog: Sendable {
    public let entries: [EmojiEntry]
    private let terms: [[SearchTextForms]]
    private let normalizer = SearchTextNormalizer()

    public static let shared = EmojiCatalog(tsv: EmojiCatalogData.tsv)
    public static let prefixes = ["emoji ", "表情 ", "符号 ", ":"]

    public init(tsv: String) {
        var entries: [EmojiEntry] = []
        for line in tsv.split(separator: "\n", omittingEmptySubsequences: true) where !line.hasPrefix("#") {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count >= 3, !columns[0].isEmpty, !columns[1].isEmpty else { continue }
            entries.append(EmojiEntry(
                glyph: columns[0],
                name: columns[1],
                keywords: columns[2].split(separator: " ").map(String.init),
                acceptsSkinTone: columns.count > 3 && columns[3].contains("s")
            ))
        }
        self.entries = entries
        let normalizer = SearchTextNormalizer()
        terms = entries.map { entry in ([entry.name] + entry.keywords).map { normalizer.forms(for: $0) } }
    }

    /// Returns the search text when the query uses an emoji prefix.
    public static func searchText(from rawQuery: String) -> String? {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespaces)
        for prefix in prefixes where trimmed.lowercased().hasPrefix(prefix) {
            let text = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    public func search(_ text: String, limit: Int = 24) -> [EmojiEntry] {
        let query = normalizer.normalized(text)
        guard !query.isEmpty else { return [] }
        var scored: [(index: Int, score: Int)] = []
        for (index, forms) in terms.enumerated() {
            var best = 0
            for (position, form) in forms.enumerated() {
                let namePenalty = position == 0 ? 0 : 5
                var score = 0
                if form.normalized == query { score = 100 }
                else if form.normalized.hasPrefix(query) { score = 80 }
                else if form.transliteration.hasPrefix(query) { score = 70 }
                else if !form.transliterationInitials.isEmpty, form.transliterationInitials.hasPrefix(query), query.count >= 2 { score = 60 }
                else if query.count >= 2, form.normalized.contains(query) { score = 40 }
                if score > 0 { best = max(best, score - namePenalty) }
            }
            if best > 0 { scored.append((index, best)) }
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .prefix(limit)
            .map { entries[$0.index] }
    }
}
