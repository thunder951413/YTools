import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShortcutSettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        SettingsCard(title: "全局快捷键", icon: "command") {
            SettingsRow(title: "显示启动器", detail: "当前全局组合键；可点击后重新录制") {
                HotKeyRecorderView(hotKey: $preferences.launcherHotKey)
            }
            Divider()
            SettingsRow(title: "剪贴板历史", detail: "当前全局组合键；可点击后重新录制") {
                HotKeyRecorderView(hotKey: $preferences.clipboardHotKey)
            }
            if let error = preferences.hotKeyError {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Divider()
            Text("组合键必须包含 Command、Option 或 Control；Shift 只能作为附加修饰键。若被 macOS 或其他应用占用，会在此处提示。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ClipboardSettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var clipboardManager: ClipboardHistoryManager
    @StateObject private var fileImporter = FileImporterPresentation()

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "剪贴板历史", icon: "clipboard") {
                if let error = clipboardManager.storageError {
                    Label(error, systemImage: "exclamationmark.shield")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Divider()
                }
                Toggle("记录剪贴板历史", isOn: $preferences.clipboardEnabled)
                Divider()
                Toggle("暂停记录（保留现有历史）", isOn: $preferences.clipboardPaused)
                    .disabled(!preferences.clipboardEnabled)
                Divider()
                SettingsRow(title: "保留时间", detail: "过期记录会自动删除") {
                    Picker("", selection: $preferences.clipboardRetentionDays) {
                        Text("24 小时").tag(1)
                        Text("7 天").tag(7)
                        Text("1 个月").tag(30)
                        Text("3 个月").tag(90)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                Divider()
                SettingsRow(title: "最多记录", detail: "限制数据库和搜索规模") {
                    Stepper(
                        "\(preferences.clipboardMaximumItems) 条",
                        value: $preferences.clipboardMaximumItems,
                        in: 50...1000,
                        step: 50
                    )
                    .frame(width: 145)
                }
                Divider()
                SettingsRow(title: "文本长度上限", detail: "超过上限的文本仍可正常粘贴，但不会进入历史") {
                    Stepper(
                        "\(preferences.clipboardMaximumTextCharacters) 字符",
                        value: $preferences.clipboardMaximumTextCharacters,
                        in: 100...10_000,
                        step: 100
                    )
                    .frame(width: 160)
                }
                Divider()
                Toggle("记录图片（最大 5 MB）", isOn: $preferences.clipboardStoreImages)
                Text("图片与文本一起写入 AES-GCM 加密历史。为减少敏感数据和磁盘占用，此项默认关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                SettingsRow(title: "加密存储占用", detail: "包括清单、记录和图片缩略图") {
                    Text(formattedStorageSize)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(title: "忽略的应用", icon: "eye.slash") {
                Text("从这些应用复制的内容不会进入历史。密码管理器和 Concealed 类型始终忽略。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(preferences.clipboardIgnoredBundleIDs, id: \.self) { bundleID in
                    Divider()
                    HStack {
                        Image(systemName: "app.badge")
                        Text(bundleID).textSelection(.enabled)
                        Spacer()
                        Button {
                            preferences.removeClipboardIgnoredApplication(bundleID)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Divider()
                Button("选择应用…") { fileImporter.isPresented = true }
            }
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

    private var formattedStorageSize: String {
        ByteCountFormatter.string(
            fromByteCount: clipboardManager.storageByteCount,
            countStyle: .file
        )
    }
}

struct PrivacySettingsView: View {
    @ObservedObject var recentDocuments: RecentDocumentsManager

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "本机数据", icon: "internaldrive") {
                PrivacyLine(
                    icon: "lock.fill",
                    title: "剪贴板加密",
                    detail: "AES-GCM 加密，密钥位于 macOS 登录钥匙串"
                )
                Divider()
                PrivacyLine(
                    icon: "network.slash",
                    title: "无启动联网",
                    detail: "没有心跳、遥测、广告或自动更新请求"
                )
                Divider()
                PrivacyLine(
                    icon: "eye.slash",
                    title: "敏感内容过滤",
                    detail: "忽略 Concealed 类型及常见密码管理器"
                )
                Divider()
                PrivacyLine(
                    icon: "number",
                    title: "匿名使用排序",
                    detail: "只保存结果标识的 SHA-256 哈希"
                )
                if let error = recentDocuments.storageError {
                    Divider()
                    Label(error, systemImage: "exclamationmark.shield")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            SettingsCard(title: "权限原则", icon: "hand.raised") {
                Text("基础启动器和剪贴板复制不需要辅助功能权限。未来的自动粘贴、联系人或日历功能必须单独启用，并在设置中说明用途。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
