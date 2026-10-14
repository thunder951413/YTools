import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import SwiftUI

// MARK: - 权限

enum PermissionState: Equatable {
    case granted
    case denied
    case notDetermined
    case unavailable

    var title: String {
        switch self {
        case .granted: "已授权"
        case .denied: "未授权"
        case .notDetermined: "首次使用时请求"
        case .unavailable: "无法检测"
        }
    }

    var tone: StatusPill.Tone {
        switch self {
        case .granted: .positive
        case .denied: .warning
        case .notDetermined, .unavailable: .neutral
        }
    }
}

/// Read-only permission checks; none of these show a system prompt.
@MainActor
enum PermissionStatus {
    static var accessibility: PermissionState { AXIsProcessTrusted() ? .granted : .denied }

    static var screenRecording: PermissionState { CGPreflightScreenCaptureAccess() ? .granted : .denied }

    /// Apple Events permission for a target app, without asking the user.
    static func automation(bundleIdentifier: String) -> PermissionState {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        guard let address = target.aeDesc else { return .unavailable }
        let status = AEDeterminePermissionToAutomateTarget(address, typeWildCard, typeWildCard, false)
        switch status {
        case OSStatus(noErr): return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        default: return .notDetermined
        }
    }
}

struct PermissionsSettingsView: View {
    @State private var accessibility = PermissionState.unavailable
    @State private var screenRecording = PermissionState.unavailable
    @State private var finder = PermissionState.unavailable
    @State private var loginWindow = PermissionState.unavailable

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "可选功能所需权限",
                          footer: "基础启动器、搜索和剪贴板记录不需要任何权限。只有使用对应功能时才会请求；随时可以在系统设置中撤销。") {
                permissionRow(title: "辅助功能", detail: "直接粘贴到前台应用、Emoji 直接粘贴、锁定屏幕",
                              target: "AccessibilityPermission", state: accessibility,
                              pane: "Privacy_Accessibility") {
                    PasteService.shared.requestTrust()
                }
                SettingsDivider()
                permissionRow(title: "屏幕录制", detail: "截图识别文字（仅截取你框选的区域，识别在本机完成）",
                              target: "ScreenRecordingPermission", state: screenRecording,
                              pane: "Privacy_ScreenCapture") {
                    _ = CGRequestScreenCaptureAccess()
                }
                SettingsDivider()
                permissionRow(title: "自动化 · 访达", detail: "清空废纸篓", target: "FinderAutomationPermission",
                              state: finder, pane: "Privacy_Automation", request: nil)
                SettingsDivider()
                permissionRow(title: "自动化 · 登录窗口", detail: "睡眠、重新启动、关机",
                              target: "PowerAutomationPermission", state: loginWindow,
                              pane: "Privacy_Automation", request: nil)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                refresh()
            }
        }
    }

    private func refresh() {
        accessibility = PermissionStatus.accessibility
        screenRecording = PermissionStatus.screenRecording
        finder = PermissionStatus.automation(bundleIdentifier: "com.apple.finder")
        loginWindow = PermissionStatus.automation(bundleIdentifier: "com.apple.loginwindow")
    }

    private func permissionRow(title: String, detail: String, target: String, state: PermissionState,
                               pane: String, request: (() -> Void)?) -> some View {
        SettingsRow(title: title, detail: detail, target: target) {
            HStack(spacing: 8) {
                StatusPill(text: state.title, tone: state.tone)
                if state != .granted, let request {
                    Button("请求") {
                        request()
                        refresh()
                    }
                }
                Button("打开系统设置") { openPrivacyPane(pane) }
            }
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - 隐私与数据

struct PrivacySettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var recentDocuments: RecentDocumentsManager
    var diagnosticReport: () -> String = { "YTools 本机诊断" }
    @State private var diagnosticCopied = false
    @State private var confirmingRestore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "本机数据") {
                SettingsRow(title: "剪贴板、片段与最近文档", detail: "AES-GCM 加密，密钥保存在 macOS 登录钥匙串") {
                    StatusPill(text: recentDocuments.storageError == nil ? "已加密" : "需要注意",
                               tone: recentDocuments.storageError == nil ? .positive : .warning)
                }
                if let error = recentDocuments.storageError {
                    SettingsNoteRow("⚠︎ " + error)
                }
                SettingsDivider()
                SettingsRow(title: "网络", detail: "无遥测、心跳、广告或自动更新；仅在启用同步时连接坚果云") {
                    StatusPill(text: preferences.clipboardCloudSyncEnabled ? "同步已启用" : "本机模式",
                               tone: preferences.clipboardCloudSyncEnabled ? .neutral : .positive)
                }
                SettingsDivider()
                SettingsRow(title: "敏感内容", detail: "忽略 Concealed 类型与常见密码管理器；可在剪贴板中添加更多规则") {
                    EmptyView()
                }
                SettingsDivider()
                SettingsRow(title: "使用排序", detail: "只保存结果标识的 SHA-256 哈希，不保存搜索原文") {
                    EmptyView()
                }
            }

            SettingsGroup(title: "诊断") {
                SettingsRow(title: "复制本机诊断", detail: "版本、能力状态与记录数量；不含内容、路径或凭据，复制时不联网",
                            target: "LocalDiagnostics") {
                    Button(diagnosticCopied ? "已复制" : "复制") {
                        let board = NSPasteboard.general
                        board.clearContents()
                        diagnosticCopied = board.setString(diagnosticReport(), forType: .string)
                    }
                }
            }

            SettingsGroup(title: "维护") {
                SettingsRow(title: "清除使用学习", detail: "清除本机排序哈希和查询词绑定", target: "ClearUsageLearning") {
                    Button("清除") { preferences.clearUsageLearning() }
                }
                SettingsDivider()
                SettingsRow(title: "清除最近文档", detail: "删除 YTools 加密保存的最近打开记录", target: "ClearRecentDocuments") {
                    Button("清除") { recentDocuments.clear() }
                        .disabled(recentDocuments.items.isEmpty)
                }
                SettingsDivider()
                SettingsRow(title: "恢复默认设置", detail: "不影响剪贴板历史、片段和同步凭据", target: "RestoreDefaults") {
                    Button("恢复默认…") { confirmingRestore = true }
                }
            }
        }
        .confirmationDialog("恢复所有默认设置？", isPresented: $confirmingRestore) {
            Button("恢复默认", role: .destructive) { preferences.restoreDefaults() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("外观、快捷键、搜索、工具和剪贴板选项会回到初始状态；自定义应用与别名也会被清空。")
        }
    }
}
