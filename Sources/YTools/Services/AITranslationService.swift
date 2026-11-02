import Foundation
import YToolsCore

/// Endpoint presets offered in settings. Every preset only fills the editable
/// fields; requests always go to the base URL the user saved.
enum AITranslationProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI
    case deepSeek
    case qwen
    case moonshot
    case zhipu
    case openRouter
    case anthropic
    case ollama
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .deepSeek: "DeepSeek"
        case .qwen: "通义千问（阿里云百炼）"
        case .moonshot: "Kimi（Moonshot）"
        case .zhipu: "智谱 GLM"
        case .openRouter: "OpenRouter"
        case .anthropic: "Anthropic Claude"
        case .ollama: "Ollama（本机）"
        case .custom: "自定义"
        }
    }

    var format: TranslationAPIFormat { self == .anthropic ? .anthropic : .openAICompatible }

    var baseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .deepSeek: "https://api.deepseek.com/v1"
        case .qwen: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .moonshot: "https://api.moonshot.cn/v1"
        case .zhipu: "https://open.bigmodel.cn/api/paas/v4"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .anthropic: "https://api.anthropic.com"
        case .ollama: "http://localhost:11434/v1"
        case .custom: ""
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-4o-mini"
        case .deepSeek: "deepseek-chat"
        case .qwen: "qwen-plus"
        case .moonshot: "moonshot-v1-8k"
        case .zhipu: "glm-4-flash"
        case .openRouter: "openai/gpt-4o-mini"
        case .anthropic: "claude-haiku-5-5"
        case .ollama: "qwen2.5:7b"
        case .custom: ""
        }
    }

    /// Local models usually run without a key.
    var requiresKey: Bool { self != .ollama }
}

struct AITranslationOutput: Equatable, Sendable {
    let text: String
    let target: TranslationLanguage
}

enum AITranslationError: LocalizedError, Equatable {
    case disabled
    case missingKey
    case endpoint(TranslationEndpointPolicy.Rejection)
    case http(Int, String?)
    case payload(TranslationPayload.ParseError)
    case transport(String)
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .disabled: "AI 翻译尚未启用，请在“设置 › 内置工具 › AI 翻译”中开启。"
        case .missingKey: "尚未保存 API Key，请在“设置 › 内置工具 › AI 翻译”中填写。"
        case let .endpoint(rejection): rejection.message
        case let .http(status, message):
            switch status {
            case 401, 403: "API Key 无效或没有权限（HTTP \(status)）\(message.map { "：\($0)" } ?? "")"
            case 404: "接口地址或模型名称不存在（HTTP 404）\(message.map { "：\($0)" } ?? "")"
            case 429: "请求过于频繁或额度不足（HTTP 429）\(message.map { "：\($0)" } ?? "")"
            default: "接口返回 HTTP \(status)\(message.map { "：\($0)" } ?? "")"
            }
        case let .payload(error): error.message
        case let .transport(message): "无法连接翻译接口：\(message)"
        case .tooLarge: "接口返回的内容过大，已停止读取。"
        }
    }
}

/// Sends translation requests to the endpoint the user configured. This is
/// the only networked code besides the Jianguoyun synchronizer: one ephemeral
/// session, no redirects, no cookies or cache, HTTPS (or loopback HTTP) only.
actor AITranslationService {
    static let shared = AITranslationService()

    private struct Credentials: Codable {
        var apiKey: String
    }

    private struct CacheKey: Hashable {
        let text: String
        let target: TranslationLanguage
        let model: String
        let url: URL
    }

    private static let maximumResponseBytes = 2_000_000
    private let credentialStore: SecureCodableStore
    private let session = URLSession(configuration: .ephemeral, delegate: TranslationRedirectPolicy(), delegateQueue: nil)
    private var cache: [CacheKey: String] = [:]
    private var cacheOrder: [CacheKey] = []

    init(credentialStore: SecureCodableStore = SecureCodableStore(name: "ai-translation-credentials")) {
        self.credentialStore = credentialStore
    }

    var hasAPIKey: Bool {
        if case let .loaded(credentials) = credentialStore.load(Credentials.self) {
            return !credentials.apiKey.isEmpty
        }
        return false
    }

    /// Saves (or with an empty key, removes) the API key. Returns an error message.
    func saveAPIKey(_ key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 512, !trimmed.contains(where: \.isNewline) else { return "API Key 格式不正确。" }
        guard credentialStore.save(Credentials(apiKey: trimmed)) else {
            return "无法加密保存 API Key，钥匙串或本机存储当前不可用。"
        }
        cache.removeAll()
        cacheOrder.removeAll()
        return nil
    }

    func translate(_ text: String, settings: AITranslationSettings,
                   target requestedTarget: TranslationLanguage? = nil) async throws -> AITranslationOutput {
        guard settings.enabled else { throw AITranslationError.disabled }
        let source = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(TranslationQuery.maximumCharacters))
        let target = requestedTarget ?? settings.target(for: source)
        guard !source.isEmpty else { return AITranslationOutput(text: "", target: target) }
        let url: URL
        switch TranslationEndpointPolicy.requestURL(baseURL: settings.baseURL, format: settings.format) {
        case let .success(value): url = value
        case let .failure(rejection): throw AITranslationError.endpoint(rejection)
        }
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = CacheKey(text: source, target: target, model: model, url: url)
        if let cached = cache[key] { return AITranslationOutput(text: cached, target: target) }

        var apiKey = ""
        if case let .loaded(credentials) = credentialStore.load(Credentials.self) { apiKey = credentials.apiKey }
        if apiKey.isEmpty, settings.provider.requiresKey { throw AITranslationError.missingKey }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch settings.format {
        case .openAICompatible:
            if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        request.httpBody = try TranslationPayload.body(format: settings.format, model: model, text: source, target: target)

        let (status, data) = try await send(request)
        try Task.checkCancellation()
        guard (200..<300).contains(status) else {
            throw AITranslationError.http(status, TranslationPayload.errorMessage(in: data))
        }
        switch TranslationPayload.translation(from: data, format: settings.format) {
        case let .success(translation):
            remember(translation, for: key)
            return AITranslationOutput(text: translation, target: target)
        case let .failure(error):
            throw AITranslationError.payload(error)
        }
    }

    private func send(_ request: URLRequest) async throws -> (Int, Data) {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw AITranslationError.transport("无效响应") }
            guard response.expectedContentLength <= Self.maximumResponseBytes else { throw AITranslationError.tooLarge }
            var data = Data()
            for try await byte in bytes {
                guard data.count < Self.maximumResponseBytes else { throw AITranslationError.tooLarge }
                data.append(byte)
            }
            return (http.statusCode, data)
        } catch let error as AITranslationError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw AITranslationError.transport(error.localizedDescription)
        }
    }

    private func remember(_ translation: String, for key: CacheKey) {
        if cache[key] == nil { cacheOrder.append(key) }
        cache[key] = translation
        while cacheOrder.count > 100 { cache[cacheOrder.removeFirst()] = nil }
    }
}

private final class TranslationRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
