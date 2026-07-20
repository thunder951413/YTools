import Foundation

/// Parses and ranks user-defined application aliases without touching the
/// filesystem. The launcher can therefore keep alias matching in the same
/// fast, local path as ordinary application-name matching.
public struct ApplicationAliasMatcher: Sendable {
    private let normalizer = SearchTextNormalizer()

    public init() {}

    public func aliases(from rawValue: String) -> [String] {
        rawValue
            .components(separatedBy: CharacterSet(charactersIn: ",，;；\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public func score(query: String, aliases: [String]) -> Int? {
        let queryForms = normalizer.forms(for: query)
        guard !queryForms.normalized.isEmpty else { return nil }
        return aliases.compactMap { score(query: queryForms, alias: $0) }.max()
    }

    private func score(query: SearchTextForms, alias: String) -> Int? {
        let candidate = normalizer.forms(for: alias)
        if candidate.normalized == query.normalized { return 960 }
        if candidate.transliteration == query.normalized { return 940 }
        if candidate.normalized.hasPrefix(query.normalized) { return 880 }
        if candidate.transliteration.hasPrefix(query.normalized) { return 860 }
        if candidate.abbreviation.hasPrefix(query.normalized)
            || candidate.transliterationInitials.hasPrefix(query.normalized) { return 830 }
        if candidate.normalized.contains(query.normalized)
            || candidate.transliteration.contains(query.normalized) { return 760 }
        guard query.normalized.count >= 2 else { return nil }
        let normalizedFuzzy = normalizer.fuzzyScore(
            query: query.normalized,
            candidate: candidate.normalized
        )
        let transliteratedFuzzy = normalizer.fuzzyScore(
            query: query.normalized,
            candidate: candidate.transliteration
        )
        return [normalizedFuzzy, transliteratedFuzzy]
            .compactMap { $0 }
            .max()
            .map { 620 + $0 }
    }
}
