import Foundation

/// Languages offered by the AI translator. The raw value is stored in settings.
public enum TranslationLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case russian = "ru"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chineseSimplified: "简体中文"
        case .chineseTraditional: "繁體中文"
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        case .russian: "Русский"
        }
    }

    /// The name used inside the model prompt.
    public var promptName: String {
        switch self {
        case .chineseSimplified: "Simplified Chinese"
        case .chineseTraditional: "Traditional Chinese"
        case .english: "English"
        case .japanese: "Japanese"
        case .korean: "Korean"
        case .french: "French"
        case .german: "German"
        case .spanish: "Spanish"
        case .russian: "Russian"
        }
    }

    /// Script family used by the offline direction guess.
    var script: TranslationScript {
        switch self {
        case .chineseSimplified, .chineseTraditional: .han
        case .japanese: .kana
        case .korean: .hangul
        case .russian: .cyrillic
        case .english, .french, .german, .spanish: .latin
        }
    }
}

enum TranslationScript {
    case han, kana, hangul, cyrillic, latin
}

/// Picks the target language for a pair: text written in the primary
/// language goes to the secondary one, anything else goes to the primary.
public enum TranslationDirection {
    public static func target(
        for text: String,
        primary: TranslationLanguage,
        secondary: TranslationLanguage
    ) -> TranslationLanguage {
        guard let script = dominantScript(of: text) else { return secondary }
        if script == .han,
           (primary == .chineseSimplified && secondary == .chineseTraditional)
            || (primary == .chineseTraditional && secondary == .chineseSimplified) {
            let detected: TranslationLanguage = prefersTraditionalChinese(text) ? .chineseTraditional : .chineseSimplified
            return detected == primary ? secondary : primary
        }
        if script == primary.script { return secondary }
        if script == secondary.script { return primary }
        // Japanese text mixes kana with Han; treat Han-only input as Chinese.
        if script == .kana, primary.script == .han { return primary }
        return primary
    }

    private static let traditionalMarkers = Set("體國學語機電網書車門開關東風長時會見發經現實點頭後裡與為無專業愛義樂話說讀寫聽買賣錢價張陳劉楊黃趙吳週鄭謝蘇馬馮葉鐘蔣韓鄧許蕭曾潘蔡韋薛閻盧體驗際應設數統處變條問議導認識響護標證際權環節優選備際".unicodeScalars)
    private static let simplifiedMarkers = Set("体国学语机电网书车门开关东风长时不见发经现实点头后里与为无专业爱义乐话说读写听买卖钱价张陈刘杨黄赵吴周郑谢苏马冯叶钟蒋韩邓许萧曾潘蔡韦薛阎卢体验际应设数统处变条问议导认识响护标证际权环节优选备".unicodeScalars)

    private static func prefersTraditionalChinese(_ text: String) -> Bool {
        var traditional = 0, simplified = 0
        for scalar in text.unicodeScalars {
            if traditionalMarkers.contains(scalar) { traditional += 1 }
            if simplifiedMarkers.contains(scalar) { simplified += 1 }
        }
        return traditional > simplified
    }

    static func dominantScript(of text: String) -> TranslationScript? {
        var han = 0, kana = 0, hangul = 0, cyrillic = 0, latin = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF: kana += 1
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF, 0x20000...0x2FA1F: han += 1
            case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F: hangul += 1
            case 0x0400...0x04FF: cyrillic += 1
            case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F: latin += 1
            default: break
            }
        }
        // Any kana marks Japanese even in kanji-dense sentences (e.g. 13 kanji + 1 particle).
        if kana > 0, kana * 15 >= han { return .kana }
        // CJK characters carry more meaning per character than Latin letters.
        let candidates: [(TranslationScript, Int)] = [
            (.han, han * 3), (.hangul, hangul * 3), (.cyrillic, cyrillic), (.latin, latin)
        ]
        guard let best = candidates.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        return best.0
    }
}

/// `fy hello` style launcher queries. Returns the text after the keyword,
/// or an empty string when only the keyword was typed.
public enum TranslationQuery {
    public static let maximumCharacters = 5_000

    public static func parse(_ query: String, keywords: [String]) -> String? {
        let trimmedLeading = query.drop(while: \.isWhitespace)
        for keyword in keywords where !keyword.isEmpty {
            guard trimmedLeading.count >= keyword.count,
                  trimmedLeading.prefix(keyword.count).lowercased() == keyword.lowercased() else { continue }
            let rest = trimmedLeading.dropFirst(keyword.count)
            if rest.isEmpty { return "" }
            guard let first = rest.first, first.isWhitespace else { continue }
            return String(rest.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumCharacters))
        }
        return nil
    }

    /// Splits a comma/space separated keyword setting into clean keywords.
    public static func keywords(from setting: String) -> [String] {
        let parts = setting.split(whereSeparator: { $0 == "," || $0 == "，" || $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count <= 12 }
        var seen = Set<String>()
        return parts.filter { seen.insert($0.lowercased()).inserted }.prefix(5).map { $0 }
    }
}

/// Wire format spoken by the configured endpoint.
public enum TranslationAPIFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    /// `POST …/chat/completions` (OpenAI, DeepSeek, Qwen, Moonshot, Ollama …).
    case openAICompatible
    /// `POST …/v1/messages` (Anthropic Claude).
    case anthropic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .openAICompatible: "OpenAI 兼容"
        case .anthropic: "Anthropic"
        }
    }
}

/// Validates the user-entered base URL before any request is built.
/// HTTPS is required; plain HTTP is accepted only for a model on this Mac.
public enum TranslationEndpointPolicy {
    public enum Rejection: Error, Equatable, Sendable {
        case invalid
        case insecureScheme
        case embeddedCredentials
        case queryOrFragment

        public var message: String {
            switch self {
            case .invalid: "接口地址无效，请填写以 https:// 开头的完整地址。"
            case .insecureScheme: "接口地址必须使用 https；http 仅允许 localhost / 127.0.0.1 上的本机模型。"
            case .embeddedCredentials: "接口地址中不能包含用户名或密码，请把 API Key 填到单独的输入框。"
            case .queryOrFragment: "接口地址中不能包含 ? 查询参数或 # 片段。"
            }
        }
    }

    static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// Returns the full request URL for the format, appending the standard
    /// path unless the user already entered it.
    public static func requestURL(baseURL raw: String, format: TranslationAPIFormat) -> Result<URL, Rejection> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty else { return .failure(.invalid) }
        guard components.user == nil, components.password == nil else { return .failure(.embeddedCredentials) }
        guard components.query == nil, components.fragment == nil else { return .failure(.queryOrFragment) }
        switch scheme {
        case "https": break
        case "http" where loopbackHosts.contains(host): break
        default: return .failure(.insecureScheme)
        }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        switch format {
        case .openAICompatible:
            if !path.hasSuffix("/chat/completions") { path += "/chat/completions" }
        case .anthropic:
            if !path.hasSuffix("/messages") { path += path.hasSuffix("/v1") ? "/messages" : "/v1/messages" }
        }
        var result = URLComponents()
        result.scheme = scheme
        result.host = components.host
        result.port = components.port
        result.path = path
        guard let url = result.url else { return .failure(.invalid) }
        return .success(url)
    }
}

/// Builds request bodies and reads replies for both wire formats. Kept free
/// of networking so it can be tested offline.
public enum TranslationPayload {
    public enum ParseError: Error, Equatable, Sendable {
        case server(String)
        case emptyReply
        case malformed

        public var message: String {
            switch self {
            case let .server(text): "接口返回错误：\(text)"
            case .emptyReply: "接口没有返回译文。"
            case .malformed: "无法解析接口返回的内容。"
            }
        }
    }

    public static func systemPrompt(target: TranslationLanguage) -> String {
        """
        You are a professional translation engine. Translate the user's text into \(target.promptName). \
        Preserve meaning, tone, line breaks, Markdown, code, numbers and proper nouns. \
        If the text is already in \(target.promptName), polish it lightly instead. \
        Reply with the translation only: no quotes, notes, explanations or language labels.
        """
    }

    public static func body(
        format: TranslationAPIFormat,
        model: String,
        text: String,
        target: TranslationLanguage
    ) throws -> Data {
        let system = systemPrompt(target: target)
        let object: [String: Any]
        switch format {
        case .openAICompatible:
            object = [
                "model": model,
                "temperature": 0.2,
                "stream": false,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": text]
                ]
            ]
        case .anthropic:
            object = [
                "model": model,
                "max_tokens": 4_096,
                "system": system,
                "messages": [["role": "user", "content": text]]
            ]
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    public static func translation(from data: Data, format: TranslationAPIFormat) -> Result<String, ParseError> {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.malformed)
        }
        if let message = errorMessage(in: object) { return .failure(.server(message)) }
        let text: String?
        switch format {
        case .openAICompatible:
            let choices = object["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            text = message?["content"] as? String
        case .anthropic:
            let content = object["content"] as? [[String: Any]]
            text = content?.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        }
        guard let text else { return .failure(.malformed) }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? .failure(.emptyReply) : .success(cleaned)
    }

    /// Error text from a non-2xx reply, if the body carries one.
    public static func errorMessage(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return errorMessage(in: object)
    }

    private static func errorMessage(in object: [String: Any]) -> String? {
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return String(message.prefix(300))
        }
        if let message = object["error"] as? String { return String(message.prefix(300)) }
        return nil
    }
}
