import XCTest
@testable import YTools
import YToolsCore
import YToolsModuleKit

final class TranslationCoreTests: XCTestCase {
    func testDirectionFollowsLanguagePair() {
        XCTAssertEqual(TranslationDirection.target(for: "今天天气很好", primary: .chineseSimplified, secondary: .english), .english)
        XCTAssertEqual(TranslationDirection.target(for: "The weather is nice", primary: .chineseSimplified, secondary: .english), .chineseSimplified)
        // Mostly Chinese with an English product name stays Chinese → English.
        XCTAssertEqual(TranslationDirection.target(for: "我在用 YTools 翻译", primary: .chineseSimplified, secondary: .english), .english)
        // A third language goes to the primary language.
        XCTAssertEqual(TranslationDirection.target(for: "Привет", primary: .chineseSimplified, secondary: .english), .chineseSimplified)
        XCTAssertEqual(TranslationDirection.target(for: "こんにちは世界", primary: .english, secondary: .japanese), .english)
        XCTAssertEqual(TranslationDirection.target(for: "1234 !!", primary: .chineseSimplified, secondary: .english), .english)
    }

    func testKeywordParsing() {
        XCTAssertEqual(TranslationQuery.parse("fy hello world", keywords: ["fy", "tr"]), "hello world")
        XCTAssertEqual(TranslationQuery.parse("TR  你好 ", keywords: ["fy", "tr"]), "你好")
        XCTAssertEqual(TranslationQuery.parse("翻译 good", keywords: ["翻译"]), "good")
        XCTAssertEqual(TranslationQuery.parse("fy", keywords: ["fy"]), "")
        XCTAssertNil(TranslationQuery.parse("fyi", keywords: ["fy"]))
        XCTAssertNil(TranslationQuery.parse("safari", keywords: ["fy"]))
        XCTAssertEqual(TranslationQuery.keywords(from: "fy, tr，翻译 fy"), ["fy", "tr", "翻译"])
    }

    func testEndpointPolicy() {
        func url(_ raw: String, _ format: TranslationAPIFormat = .openAICompatible) -> String? {
            if case let .success(value) = TranslationEndpointPolicy.requestURL(baseURL: raw, format: format) { return value.absoluteString }
            return nil
        }
        XCTAssertEqual(url("https://api.openai.com/v1"), "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(url("https://api.openai.com/v1/chat/completions"), "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(url("http://localhost:11434/v1"), "http://localhost:11434/v1/chat/completions")
        XCTAssertEqual(url("https://api.anthropic.com", .anthropic), "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(url("https://proxy.example.com/v1", .anthropic), "https://proxy.example.com/v1/messages")
        XCTAssertNil(url("http://api.example.com/v1"))
        XCTAssertNil(url("ftp://api.example.com"))
        XCTAssertNil(url("https://user:pass@api.example.com/v1"))
        XCTAssertNil(url("https://api.example.com/v1?key=1"))
        XCTAssertNil(url("api.example.com"))
        XCTAssertNil(url(""))
    }

    func testPayloadRoundTrip() throws {
        let body = try TranslationPayload.body(format: .anthropic, model: "m", text: "hi", target: .chineseSimplified)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "m")
        XCTAssertNotNil(object["system"] as? String)

        let openAI = Data(#"{"choices":[{"message":{"content":"你好"}}]}"#.utf8)
        XCTAssertEqual(try TranslationPayload.translation(from: openAI, format: .openAICompatible).get(), "你好")
        let anthropic = Data(#"{"content":[{"type":"text","text":"Hello"}]}"#.utf8)
        XCTAssertEqual(try TranslationPayload.translation(from: anthropic, format: .anthropic).get(), "Hello")
        let failure = Data(#"{"error":{"message":"invalid key"}}"#.utf8)
        XCTAssertEqual(TranslationPayload.translation(from: failure, format: .openAICompatible), .failure(.server("invalid key")))
        XCTAssertEqual(TranslationPayload.translation(from: Data("<html>".utf8), format: .openAICompatible), .failure(.malformed))
    }

    func testTranslatorActionPassesPolicy() {
        let policy = ModuleResultPolicy()
        let descriptor = ModuleDescriptor(id: "ai-translation", name: "AI 翻译")
        let ok = LauncherResult(id: "a", moduleID: "x", title: "t", subtitle: "", icon: .system("character.bubble"),
                                score: 1, action: .openTranslator("hello"))
        XCTAssertNotNil(policy.sanitize(ok, from: descriptor))
        let huge = LauncherResult(id: "b", moduleID: "x", title: "t", subtitle: "", icon: .system("character.bubble"),
                                  score: 1, action: .openTranslator(String(repeating: "a", count: 6_000)))
        XCTAssertNil(policy.sanitize(huge, from: descriptor))
    }

    func testDisabledModuleOffersSetupInsteadOfTranslating() async throws {
        let module = AITranslationModule(settings: AITranslationSettings(), pastes: true)
        let results = try await module.search(ModuleSearchRequest(query: "fy hello"))
        XCTAssertEqual(results.map(\.action), [.openSettings])
        let unrelated = try await module.search(ModuleSearchRequest(query: "finder"))
        XCTAssertTrue(unrelated.isEmpty)
    }

    func testSettingsDecodeDefaults() throws {
        let decoded = try JSONDecoder().decode(AITranslationSettings.self, from: Data(#"{"enabled":true,"liveDelayMilliseconds":5}"#.utf8))
        XCTAssertTrue(decoded.enabled)
        XCTAssertEqual(decoded.liveDelayMilliseconds, 200)
        XCTAssertEqual(decoded.keywordList, ["fy", "tr", "翻译"])
        XCTAssertEqual(decoded.primaryLanguage, .chineseSimplified)
    }

    func testClipboardPasteDefaultMigratesOnce() throws {
        let legacy = try JSONDecoder().decode(ClipboardBehaviorSettings.self,
                                              from: Data(#"{"pasteToFrontApplication":false}"#.utf8))
        XCTAssertTrue(legacy.pasteToFrontApplication)
        var chosen = legacy
        chosen.pasteToFrontApplication = false
        let reloaded = try JSONDecoder().decode(ClipboardBehaviorSettings.self, from: JSONEncoder().encode(chosen))
        XCTAssertFalse(reloaded.pasteToFrontApplication)
    }

    func testToolHotKeysGainTranslatorDefault() throws {
        let legacy = try JSONDecoder().decode(ToolHotKeySettings.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.translator, ToolHotKeySettings().translator)
        var cleared = ToolHotKeySettings()
        cleared.translator = nil
        let reloaded = try JSONDecoder().decode(ToolHotKeySettings.self, from: JSONEncoder().encode(cleared))
        XCTAssertNil(reloaded.translator)
    }
}
