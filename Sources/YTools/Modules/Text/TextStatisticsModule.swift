import Foundation
import YToolsModuleKit

struct TextStatisticsModule: YToolsModule {
    let descriptor = ModuleDescriptor(id: "text-statistics", name: "文本统计")

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        let trimmed = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["stats ", "统计 ", "字数 "]
        guard let prefix = prefixes.first(where: { trimmed.lowercased().hasPrefix($0) }) else { return [] }
        let text = String(trimmed.dropFirst(prefix.count))
        guard !text.isEmpty else { return [] }

        let characters = text.count
        let words = text.split(whereSeparator: \.isWhitespace).count
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        let bytes = text.lengthOfBytes(using: .utf8)
        let summary = "\(characters) 字符 · \(words) 词 · \(lines) 行 · \(bytes) 字节"
        return [LauncherResult(
            id: "text-statistics:\(stableIdentifier(text))",
            moduleID: descriptor.id,
            title: summary,
            subtitle: "本机文本统计 · 回车复制",
            icon: .system("textformat.123"),
            score: 1_030,
            action: .copy(summary)
        )]
    }

    private func stableIdentifier(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
