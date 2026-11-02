import SwiftUI
import YToolsCore

/// "内置工具 › AI 翻译": endpoint, model, key and language pair. Nothing is
/// sent anywhere until the user turns the switch on.
struct TranslationSettingsGroup: View {
    @ObservedObject var preferences: AppPreferences
    @State private var apiKeyInput = ""
    @State private var hasAPIKey = false
    @State private var status: String?
    @State private var isTesting = false

    private var settings: Binding<AITranslationSettings> { $preferences.aiTranslation }

    var body: some View {
        SettingsGroup(title: "AI 翻译", isNew: true,
                      footer: "启用后，只有你在启动器输入翻译关键词或使用翻译窗口时，输入的文字才会发送到上面填写的接口；API Key 加密保存在本机。") {
            SettingsToggleRow("启用 AI 翻译", detail: "开启即表示同意把待翻译文本发送到所选服务商",
                              target: "AITranslationEnabled", isOn: settings.enabled)
            SettingsDivider()
            SettingsRow(title: "服务商", detail: "选择预设会填入接口地址与推荐模型，可再修改", target: "AITranslationProvider") {
                Picker("服务商", selection: Binding(
                    get: { preferences.aiTranslation.provider },
                    set: { applyPreset($0) }
                )) {
                    ForEach(AITranslationProvider.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 210)
            }
            SettingsDivider()
            SettingsRow(title: "接口格式", target: "AITranslationFormat") {
                Picker("接口格式", selection: settings.format) {
                    ForEach(TranslationAPIFormat.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }
            SettingsDivider()
            SettingsRow(title: "接口地址", detail: endpointDetail, target: "AITranslationBaseURL") {
                TextField("https://…/v1", text: settings.baseURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
            }
            SettingsDivider()
            SettingsRow(title: "模型", target: "AITranslationModel") {
                TextField("模型名称", text: settings.model)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
            }
            SettingsDivider()
            SettingsRow(title: "API Key", detail: hasAPIKey ? "已加密保存；重新填写可替换，留空保存可删除" : "尚未保存",
                        target: "AITranslationAPIKey") {
                HStack(spacing: 6) {
                    SecureField(hasAPIKey ? "••••••••" : "sk-…", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 230)
                    Button("保存") { Task { await saveKey() } }
                }
            }
            SettingsDivider()
            SettingsRow(title: "语言对", detail: "输入第一种语言时译成第二种，其余语言一律译成第一种", target: "AITranslationLanguages") {
                HStack(spacing: 6) {
                    languagePicker(settings.primaryLanguage)
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                    languagePicker(settings.secondaryLanguage)
                }
            }
            SettingsDivider()
            SettingsRow(title: "启动器关键词", detail: "用逗号分隔，最多 5 个；例如输入 fy hello", target: "AITranslationKeywords") {
                TextField("fy, tr", text: settings.keywords)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }
            SettingsDivider()
            SettingsRow(title: "停顿后翻译", detail: "停止输入多久后发送请求，越短越实时、请求越多", target: "AITranslationDelay") {
                Stepper("\(preferences.aiTranslation.liveDelayMilliseconds) ms",
                        value: settings.liveDelayMilliseconds, in: 200...3_000, step: 100)
                    .monospacedDigit()
            }
            SettingsDivider()
            SettingsNoteRow(status ?? "快捷键可在“快捷键 › AI 翻译窗口”中修改。") {
                Button(isTesting ? "测试中…" : "测试翻译") { Task { await test() } }
                    .disabled(isTesting || !preferences.aiTranslation.enabled)
            }
        }
        .task { hasAPIKey = await AITranslationService.shared.hasAPIKey }
    }

    private var endpointDetail: String {
        switch TranslationEndpointPolicy.requestURL(baseURL: preferences.aiTranslation.baseURL,
                                                    format: preferences.aiTranslation.format) {
        case let .success(url): "请求发送到 \(url.absoluteString)"
        case let .failure(rejection): "⚠︎ " + rejection.message
        }
    }

    private func languagePicker(_ selection: Binding<TranslationLanguage>) -> some View {
        Picker("语言", selection: selection) {
            ForEach(TranslationLanguage.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .frame(width: 120)
    }

    private func applyPreset(_ provider: AITranslationProvider) {
        var updated = preferences.aiTranslation
        updated.provider = provider
        if provider != .custom {
            updated.format = provider.format
            updated.baseURL = provider.baseURL
            updated.model = provider.defaultModel
        }
        preferences.aiTranslation = updated
    }

    private func saveKey() async {
        let error = await AITranslationService.shared.saveAPIKey(apiKeyInput)
        hasAPIKey = await AITranslationService.shared.hasAPIKey
        if error == nil { apiKeyInput = "" }
        status = error ?? (hasAPIKey ? "API Key 已加密保存。" : "API Key 已删除。")
    }

    private func test() async {
        isTesting = true
        defer { isTesting = false }
        let sample = preferences.aiTranslation.primaryLanguage == .english ? "你好，世界" : "Hello, world"
        do {
            let output = try await AITranslationService.shared.translate(sample, settings: preferences.aiTranslation)
            status = "✓ 连接正常：“\(sample)” → “\(output.text)”"
        } catch {
            status = "✗ " + error.localizedDescription
        }
    }
}
