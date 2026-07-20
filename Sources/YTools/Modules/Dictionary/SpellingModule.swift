import AppKit
import YToolsModuleKit

struct SpellingModule: YToolsModule {
    let descriptor = ModuleDescriptor(id: "spelling", name: "拼写检查")

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        let trimmed = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["spell", "拼写"]
        guard let prefix = prefixes.first(where: {
            trimmed.lowercased().hasPrefix($0.lowercased() + " ")
        }) else { return [] }
        let word = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return [] }

        let outcome = await MainActor.run { () -> (guesses: [String], isCorrect: Bool) in
            let checker = NSSpellChecker.shared
            let range = NSRange(location: 0, length: (word as NSString).length)
            let guesses = checker.guesses(
                forWordRange: range,
                in: word,
                language: nil,
                inSpellDocumentWithTag: 0
            ) ?? []
            return (guesses, checker.checkSpelling(of: word, startingAt: 0).location == NSNotFound)
        }
        if outcome.guesses.isEmpty, outcome.isCorrect {
            return [LauncherResult(
                id: "spelling:correct:\(word)",
                moduleID: descriptor.id,
                title: word,
                subtitle: "拼写正确 · 回车复制",
                icon: .system("checkmark.seal"),
                score: 1_050,
                action: .copy(word)
            )]
        }
        return outcome.guesses.prefix(8).enumerated().map { index, suggestion in
            LauncherResult(
                id: "spelling:\(word):\(suggestion)",
                moduleID: descriptor.id,
                title: suggestion,
                subtitle: "“\(word)” 的拼写建议 · 回车复制",
                icon: .system("textformat.abc.dottedunderline"),
                score: 1_050 - index,
                action: .copy(suggestion)
            )
        }
    }
}
