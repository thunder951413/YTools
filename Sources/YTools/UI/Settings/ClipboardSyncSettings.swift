import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 剪贴板

struct ClipboardSettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var clipboardManager: ClipboardHistoryManager
    @StateObject private var fileImporter = FileImporterPresentation()
    @State private var addingRule = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "记录") {
                if let error = clipboardManager.storageError {
                    SettingsNoteRow("⚠︎ " + error)
                    SettingsDivider()
                }
                SettingsToggleRow("记录剪贴板历史", target: "ClipboardEnabled", isOn: $preferences.clipboardEnabled)
                SettingsDivider()
                SettingsToggleRow("暂停记录", detail: "保留现有历史，只是暂时不再记录", target: "ClipboardPaused",
                                  isOn: $preferences.clipboardPaused)
                    .disabled(!preferences.clipboardEnabled)
                SettingsDivider()
                SettingsRow(title: "保留时间", detail: "过期记录会自动删除") {
                    Picker("保留时间", selection: $preferences.clipboardRetentionDays) {
                        Text("24 小时").tag(1)
                        Text("7 天").tag(7)
                        Text("1 个月").tag(30)
                        Text("3 个月").tag(90)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                SettingsDivider()
                SettingsRow(title: "最多记录") {
                    SettingsStepper(value: $preferences.clipboardMaximumItems, range: 50...1_000, step: 50) { "\($0) 条" }
                }
                SettingsDivider()
                SettingsRow(title: "文本长度上限", detail: "更长的文本仍可正常粘贴，但不进入历史") {
                    SettingsStepper(value: $preferences.clipboardMaximumTextCharacters, range: 100...10_000, step: 100) {
                        "\($0) 字符"
                    }
                }
                SettingsDivider()
                SettingsToggleRow("记录图片", detail: "最大 5 MB，与文本一起 AES-GCM 加密", target: "ClipboardStoreImages",
                                  isOn: $preferences.clipboardStoreImages)
                SettingsDivider()
                SettingsRow(title: "加密存储占用", detail: "清单、记录与缩略图") {
                    Text(ByteCountFormatter.string(fromByteCount: clipboardManager.storageByteCount, countStyle: .file))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            SettingsGroup(title: "粘贴", isNew: true) {
                SettingsToggleRow("选中后直接粘贴到前台应用", detail: "需要辅助功能权限；关闭时只复制并关闭面板",
                                  target: "PasteToFrontApplication",
                                  isOn: $preferences.clipboardBehavior.pasteToFrontApplication)
                if preferences.clipboardBehavior.pasteToFrontApplication && !PasteService.shared.isTrusted {
                    SettingsNoteRow("⚠︎ 尚未授予辅助功能权限，当前只会复制。") {
                        Button("请求权限") { PasteService.shared.requestTrust() }
                    }
                }
                SettingsDivider()
                SettingsToggleRow("连续粘贴", detail: "在历史中按 ⌥↩ 依次加入队列，再用快捷键逐条粘贴",
                                  target: "SequentialPaste", isOn: $preferences.clipboardBehavior.sequentialPaste)
            }

            SettingsGroup(title: "过滤规则") {
                SettingsRow(title: "忽略的应用", detail: "密码管理器与标记为隐藏的内容始终忽略",
                            target: "ClipboardIgnoredApplications") {
                    Menu("添加应用…") {
                        let running = runningApplications
                        if !running.isEmpty {
                            Section("运行中的应用") {
                                ForEach(running, id: \.bundleID) { app in
                                    Button(app.name) { addIgnored(bundleID: app.bundleID) }
                                }
                            }
                        }
                        Button("从“应用程序”选择…") { fileImporter.isPresented = true }
                    }
                    .fixedSize()
                }
                ForEach(preferences.clipboardIgnoredBundleIDs, id: \.self) { bundleID in
                    SettingsDivider()
                    SettingsListItem(title: applicationName(bundleID), subtitle: bundleID) {
                        applicationIcon(bundleID)
                    } trailing: {
                        RemoveButton(label: "不再忽略" + applicationName(bundleID)) {
                            preferences.removeClipboardIgnoredApplication(bundleID)
                        }
                    }
                }
                SettingsDivider()
                SettingsRow(title: "忽略内容规则", detail: "匹配正则表达式的文本不进入历史", isNew: true,
                            target: "ClipboardIgnoreRules") {
                    Button("添加规则…") { addingRule = true }
                }
                ForEach(preferences.clipboardBehavior.ignoreRules) { rule in
                    SettingsDivider()
                    SettingsListItem(title: rule.pattern, subtitle: rule.isValid ? rule.label : "⚠︎ 正则表达式无效，已跳过",
                                     monospaced: true) {
                        RemoveButton(label: "移除规则" + rule.label) {
                            preferences.clipboardBehavior.ignoreRules.removeAll { $0.id == rule.id }
                        }
                    }
                }
                SettingsDivider()
                SettingsRow(title: "疑似敏感内容自动删除", detail: "看起来像验证码、令牌或长随机串的文本到期后从历史移除",
                            isNew: true, target: "SensitiveAutoDelete") {
                    Picker("疑似敏感内容自动删除", selection: $preferences.clipboardBehavior.sensitiveAutoDeleteMinutes) {
                        Text("不自动删除").tag(0)
                        Text("5 分钟后").tag(5)
                        Text("15 分钟后").tag(15)
                        Text("1 小时后").tag(60)
                        Text("1 天后").tag(1_440)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }
        }
        .sheet(isPresented: $addingRule) {
            AddIgnoreRuleSheet { rule in preferences.clipboardBehavior.ignoreRules.append(rule) }
        }
        .fileImporter(
            isPresented: $fileImporter.isPresented,
            allowedContentTypes: [.applicationBundle],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            urls.forEach(preferences.addClipboardIgnoredApplication)
        }
        .fileDialogDefaultDirectory(URL(fileURLWithPath: "/Applications", isDirectory: true))
        .fileDialogConfirmationLabel("忽略所选应用")
    }

    private struct RunningApplication {
        let name: String
        let bundleID: String
    }

    private var runningApplications: [RunningApplication] {
        let ownBundleID = Bundle.main.bundleIdentifier?.lowercased()
        let ignored = Set(preferences.clipboardIgnoredBundleIDs)
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApplication? in
                guard let bundleID = app.bundleIdentifier?.lowercased(), bundleID != ownBundleID,
                      !ignored.contains(bundleID), seen.insert(bundleID).inserted else { return nil }
                return RunningApplication(name: app.localizedName ?? bundleID, bundleID: bundleID)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func addIgnored(bundleID: String) {
        guard !preferences.clipboardIgnoredBundleIDs.contains(bundleID) else { return }
        preferences.clipboardIgnoredBundleIDs.append(bundleID)
    }

    private func applicationURL(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private func applicationName(_ bundleID: String) -> String {
        guard let url = applicationURL(bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    @ViewBuilder
    private func applicationIcon(_ bundleID: String) -> some View {
        if let url = applicationURL(bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().scaledToFit().frame(width: 24, height: 24)
        } else {
            Image(systemName: "app.dashed").frame(width: 24, height: 24).foregroundStyle(.secondary)
        }
    }
}

private struct AddIgnoreRuleSheet: View {
    let onAdd: (ClipboardIgnoreRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pattern = ""
    @State private var label = ""
    @State private var sample = ""

    private var rule: ClipboardIgnoreRule {
        ClipboardIgnoreRule(pattern: pattern, label: label.trimmingCharacters(in: .whitespaces).isEmpty ? "自定义规则" : label)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添加忽略内容规则").font(.headline)
            Text("复制的文本只要有一处匹配，就不会进入剪贴板历史。")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text("常用：").font(.caption).foregroundStyle(.secondary)
                preset("6 位验证码", #"^\d{6}$"#)
                preset("API 密钥", #"sk-[A-Za-z0-9]{20,}"#)
                preset("银行卡号", #"^\d{16,19}$"#)
            }
            TextField("正则表达式，例如 ^\\d{6}$", text: $pattern)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
            TextField("说明（可选）", text: $label)
                .textFieldStyle(.roundedBorder)
            TextField("试一试：输入示例文本", text: $sample)
                .textFieldStyle(.roundedBorder)
            Group {
                if pattern.isEmpty {
                    Text(" ")
                } else if !rule.isValid {
                    Text("⚠︎ 正则表达式无效").foregroundStyle(.orange)
                } else if !sample.isEmpty {
                    Text(rule.matches(sample) ? "✓ 示例会被忽略" : "示例不匹配，会正常记录")
                        .foregroundStyle(rule.matches(sample) ? Color.green : Color.secondary)
                } else {
                    Text(" ")
                }
            }
            .font(.caption)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("添加") {
                    onAdd(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pattern.isEmpty || !rule.isValid)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func preset(_ title: String, _ value: String) -> some View {
        Button(title) {
            pattern = value
            if label.isEmpty { label = title }
        }
        .controlSize(.small)
    }
}

// MARK: - 坚果云同步

struct CloudSyncSettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var clipboardManager: ClipboardHistoryManager

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "") {
                HStack(spacing: 14) {
                    SettingsTile(symbol: SettingsSection.sync.icon, color: SettingsSection.sync.tint, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preferences.clipboardCloudSyncEnabled ? "同步已启用" : "同步已关闭")
                            .font(.system(size: 15, weight: .semibold))
                        Text("启用后仅连接 dav.jianguoyun.com；每条记录独立 AES-GCM 加密后再上传")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("启用坚果云同步", isOn: $preferences.clipboardCloudSyncEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(14)
                .settingsTarget("ClipboardCloudSyncEnabled")
            }

            SettingsGroup(title: "账号", footer: "凭据加密保存在登录钥匙串；保存后输入框会清空。") {
                SettingsRow(title: "坚果云用户名", target: "CloudUsername") {
                    TextField("name@example.com", text: $clipboardManager.cloudUsernameInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 230)
                }
                SettingsDivider()
                SettingsRow(title: "应用密码", detail: "在坚果云网页“账户信息 › 安全选项”中生成", target: "CloudAppPassword") {
                    SecureField("应用密码", text: $clipboardManager.cloudAppPasswordInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 230)
                }
                SettingsDivider()
                SettingsRow(title: "同步口令", detail: "至少 12 个字符，所有设备必须一致", target: "CloudPassphrase") {
                    SecureField("同步口令", text: $clipboardManager.cloudSyncPassphraseInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 230)
                }
                SettingsDivider()
                SettingsNoteRow("用户名、应用密码与同步口令需一起保存。") {
                    Button("加密保存") {
                        Task {
                            _ = await clipboardManager.saveCloudSyncCredentials(
                                username: clipboardManager.cloudUsernameInput,
                                appPassword: clipboardManager.cloudAppPasswordInput,
                                syncPassphrase: clipboardManager.cloudSyncPassphraseInput
                            )
                        }
                    }
                    .disabled(clipboardManager.cloudUsernameInput.isEmpty)
                }
            }

            SettingsGroup(title: "选项") {
                SettingsRow(title: "远端目录", detail: "英文字母、数字、点、下划线与连字符", target: "ClipboardCloudSyncFolder") {
                    TextField("YTools/clipboard-sync", text: $preferences.clipboardCloudSyncFolder)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 210)
                }
                SettingsDivider()
                SettingsRow(title: "拉取间隔", detail: "无变化时只读取每台设备的小型标记文件") {
                    SettingsStepper(value: $preferences.clipboardCloudSyncIntervalMinutes, range: 15...240, step: 5) {
                        "\($0) 分钟"
                    }
                }
                SettingsDivider()
                SettingsRow(title: "同步状态",
                            detail: clipboardManager.cloudSyncStatus.isEmpty ? "尚未同步" : clipboardManager.cloudSyncStatus) {
                    Button("立即同步") { Task { await clipboardManager.syncCloudNow() } }
                        .disabled(!preferences.clipboardCloudSyncEnabled)
                }
            }
        }
    }
}
