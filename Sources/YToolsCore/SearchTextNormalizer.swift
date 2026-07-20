import Foundation

public struct SearchTextForms: Equatable, Sendable {
    public let normalized: String
    public let abbreviation: String
    public let transliteration: String
    public let transliterationInitials: String
}

public struct SearchTextNormalizer: Sendable {
    private static let stableLocale = Locale(identifier: "en_US_POSIX")

    public init() {}

    public func forms(for value: String) -> SearchTextForms {
        let normalizedValue = normalized(value)
        let latin = value.applyingTransform(.toLatin, reverse: false) ?? value
        let latinWords = latin.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let latinInitials = normalized(String(latinWords.compactMap(\.first)))
        let wordInitials = value
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .compactMap(\.first)
        let nativeAbbreviation: String
        if wordInitials.count > 1 {
            nativeAbbreviation = normalized(String(wordInitials))
        } else {
            let characters = Array(value)
            nativeAbbreviation = normalized(String(characters.enumerated().compactMap { index, character in
                character.isUppercase || index == 0 ? character : nil
            }))
        }
        let containsNonASCII = value.unicodeScalars.contains { !$0.isASCII }

        return SearchTextForms(
            normalized: normalizedValue,
            abbreviation: containsNonASCII ? latinInitials : nativeAbbreviation,
            transliteration: normalized(latin),
            transliterationInitials: latinInitials
        )
    }

    public func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Self.stableLocale)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Scores an ordered, non-contiguous match such as `slk` → `Slack`.
    /// Prefix and substring matches should still be ranked separately by callers.
    public func fuzzyScore(query: String, candidate: String) -> Int? {
        let queryCharacters = Array(normalized(query))
        let candidateCharacters = Array(normalized(candidate))
        guard !queryCharacters.isEmpty,
              queryCharacters.count <= candidateCharacters.count else { return nil }

        var searchStart = 0
        var previousMatch: Int?
        var firstMatch: Int?
        var score = 0

        for character in queryCharacters {
            guard let match = candidateCharacters[searchStart...].firstIndex(of: character) else {
                return nil
            }
            if firstMatch == nil { firstMatch = match }
            score += 12
            if let previousMatch {
                let gap = match - previousMatch - 1
                score += gap == 0 ? 8 : -min(gap * 2, 12)
            }
            previousMatch = match
            searchStart = match + 1
        }

        let coverage = queryCharacters.count * 30 / candidateCharacters.count
        let startPenalty = min((firstMatch ?? 0) * 2, 20)
        return max(1, min(99, score + coverage - startPenalty))
    }
}
