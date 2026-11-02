import Foundation
import YToolsCore
import YToolsModuleKit

/// `fy hello` / `tr 你好`: translates the text after the keyword through the
/// configured AI endpoint once typing pauses. The request itself is made by
/// `AITranslationService`; this module only shapes the results.
struct AITranslationModule: YToolsModule {
    let descriptor = ModuleDescriptor(id: "ai-translation", name: "AI 翻译")
    let settings: AITranslationSettings
    let pastes: Bool
    var service: AITranslationService = .shared

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        guard let text = TranslationQuery.parse(request.query, keywords: settings.keywordList) else { return [] }
        let keyword = settings.keywordList.first ?? "fy"
        guard settings.enabled else {
            return [result("setup", title: "AI 翻译尚未启用", subtitle: "回车打开设置，填写 API 后即可用 \(keyword) 翻译",
                           icon: "gearshape", score: 900, action: .openSettings)]
        }
        guard !text.isEmpty else {
            return [result("window", title: "打开 AI 翻译窗口",
                           subtitle: "或输入 \(keyword) 加文字直接翻译 · \(settings.primaryLanguage.title) ⇄ \(settings.secondaryLanguage.title)",
                           icon: "character.bubble", score: 1_100, action: .openTranslator(""))]
        }
        let openWindow = result("window:\(ToolResultText.stableID(text))", title: "在翻译窗口中继续编辑",
                                subtitle: "边输入边翻译，可切换翻译方向", icon: "macwindow", score: 1_090,
                                action: .openTranslator(text))
        // Wait for a pause in typing; a new keystroke cancels this search.
        try await Task.sleep(for: .milliseconds(settings.liveDelayMilliseconds))
        do {
            let output = try await service.translate(text, settings: settings)
            try Task.checkCancellation()
            let direction = "→ \(output.target.title)"
            return [
                result("text:\(ToolResultText.stableID(text + output.target.rawValue))",
                       title: ToolResultText.title(output.text, limit: 300),
                       subtitle: "AI 翻译 \(direction) · 回车\(pastes ? "粘贴" : "复制")译文",
                       icon: "character.bubble", score: 1_100,
                       action: pastes ? .paste(output.text) : .copy(output.text)),
                openWindow
            ]
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return [
                result("error:\(ToolResultText.stableID(text))", title: "翻译失败",
                       subtitle: String(error.localizedDescription.prefix(300)),
                       icon: "exclamationmark.triangle", score: 1_100, action: .openTranslator(text)),
                openWindow
            ]
        }
    }

    private func result(_ id: String, title: String, subtitle: String, icon: String,
                        score: Int, action: ResultAction) -> LauncherResult {
        LauncherResult(id: "ai-translation:\(id)", moduleID: descriptor.id, title: title, subtitle: subtitle,
                       icon: .system(icon), score: score, action: action)
    }
}
