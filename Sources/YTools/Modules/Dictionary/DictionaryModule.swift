import CoreServices
import Foundation
import YToolsModuleKit

struct DictionaryModule: YToolsModule {
    let descriptor = ModuleDescriptor(id: "dictionary", name: "系统词典")
    private let includeAutomaticResults: Bool

    init(includeAutomaticResults: Bool) {
        self.includeAutomaticResults = includeAutomaticResults
    }

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        guard let lookup = parseRequest(request.query),
              lookup.explicit || includeAutomaticResults,
              !Task.isCancelled,
              let definition = definition(for: lookup.word) else {
            return []
        }

        return [LauncherResult(
            id: "dictionary:\(lookup.word.lowercased())",
            moduleID: descriptor.id,
            title: lookup.word,
            subtitle: definitionSummary(definition),
            icon: .system("character.book.closed"),
            score: lookup.explicit ? 950 : 350,
            action: .copy(definition)
        )]
    }

    private func parseRequest(_ query: String) -> (word: String, explicit: Bool)? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["define ", "dict ", "词典 ", "查词 "]
        for prefix in prefixes where trimmed.lowercased().hasPrefix(prefix) {
            let word = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            return word.isEmpty ? nil : (word, true)
        }

        let isSingleLatinWord = trimmed.range(
            of: #"^[A-Za-z][A-Za-z'-]{1,40}$"#,
            options: .regularExpression
        ) != nil
        return isSingleLatinWord ? (trimmed, false) : nil
    }

    private func definition(for word: String) -> String? {
        let text = word as CFString
        let range = CFRange(location: 0, length: CFStringGetLength(text))
        guard let value = DCSCopyTextDefinition(nil, text, range) else { return nil }
        return (value.takeRetainedValue() as String)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func definitionSummary(_ definition: String) -> String {
        let compact = definition
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let limit = 72
        guard compact.count > limit else { return "系统词典 · \(compact)" }
        return "系统词典 · \(compact.prefix(limit))…"
    }
}
