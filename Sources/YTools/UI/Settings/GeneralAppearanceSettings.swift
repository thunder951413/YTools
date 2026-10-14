import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "启动") {
                SettingsToggleRow("登录时启动 YTools", target: "LaunchAtLogin", isOn: $preferences.launchAtLogin)
                if let error = preferences.launchAtLoginError {
                    SettingsNoteRow(error)
                }
                SettingsDivider()
                SettingsToggleRow("显示菜单栏图标", detail: "隐藏后仍可用全局快捷键或 ⌘, 打开设置",
                                  target: "ShowTrayIcon", isOn: $preferences.showMenuBarIcon)
            }

            SettingsGroup(title: "窗口") {
                SettingsRow(title: "窗口位置", detail: "拖动后按显示器分辨率记住相对位置") {
                    Picker("窗口位置", selection: $preferences.panelPosition) {
                        ForEach(PanelPosition.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                SettingsDivider()
                SettingsRow(title: "显示器", detail: "多屏环境下启动器出现的屏幕") {
                    Picker("显示器", selection: $preferences.screenPreference) {
                        ForEach(ScreenPreference.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                if preferences.savedPanelTopLeft != nil {
                    SettingsDivider()
                    SettingsRow(title: "已记住拖动位置", detail: "切换显示器后自动限制在可见区域") {
                        Button("恢复预设位置") { preferences.clearSavedPanelPosition() }
                    }
                }
            }

            SettingsGroup(title: "输入") {
                SettingsRow(title: "默认输入语言", detail: "显示启动器或剪贴板时切换；也可跟随当前输入源") {
                    Picker("默认输入语言", selection: $preferences.forcedKeyboardInputSourceID) {
                        Text("跟随当前输入源").tag("")
                        ForEach(KeyboardInputSourceManager.availableInputSources()) { source in
                            Text(source.name).tag(source.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
                if let error = preferences.keyboardInputSourceError {
                    SettingsNoteRow(error)
                }
            }
        }
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "启动器") {
                VStack(alignment: .leading, spacing: 12) {
                    LauncherAppearancePreview(preferences: preferences)
                        .frame(maxWidth: 460)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.05)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    Picker("启动器风格", selection: $preferences.launcherAppearanceStyle) {
                        ForEach(LauncherAppearanceStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(preferences.launcherAppearanceStyle.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .settingsTarget("LauncherAppearanceStyle")
            }

            SettingsGroup(title: "颜色") {
                SettingsRow(title: "颜色模式", detail: "应用于启动器、剪贴板和设置") {
                    Picker("颜色模式", selection: $preferences.theme) {
                        ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 210)
                }
                SettingsDivider()
                SettingsRow(title: "强调色", detail: "选中态、图标和操作提示") {
                    HStack(spacing: 8) {
                        ForEach(AppAccentColor.allCases) { accent in
                            Button {
                                preferences.accentColor = accent
                            } label: {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.15)))
                                    .padding(3)
                                    .overlay(Circle().stroke(accent == preferences.accentColor ? accent.color : .clear,
                                                             lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .help(accent.title)
                            .accessibilityLabel(accent.title)
                            .accessibilityAddTraits(accent == preferences.accentColor ? .isSelected : [])
                        }
                    }
                }
            }

            SettingsGroup(title: "结果") {
                SettingsToggleRow("紧凑结果间距", target: "CompactResults", isOn: $preferences.compactResults)
                SettingsDivider()
                SettingsToggleRow("显示副标题和路径", target: "ShowSubtitles", isOn: $preferences.showSubtitles)
                SettingsDivider()
                SettingsToggleRow("显示 ⌘1…9 快速执行提示", target: "ShowNumberShortcuts",
                                  isOn: $preferences.showNumberShortcuts)
                SettingsDivider()
                SettingsRow(title: "面板宽度") {
                    SettingsSlider(value: $preferences.panelWidth, range: 640...960, step: 20,
                                   label: "\(Int(preferences.panelWidth)) pt")
                }
                SettingsDivider()
                SettingsRow(title: "外层圆角") {
                    SettingsSlider(value: $preferences.panelCornerRadius, range: 10...20, step: 1,
                                   label: "\(Int(preferences.panelCornerRadius)) pt")
                }
            }

            SettingsGroup(title: "动效") {
                SettingsRow(title: "预览切换停留", detail: "选中项停留后才加载预览；0 为立即切换") {
                    SettingsSlider(value: $preferences.previewSelectionDelay, range: 0...0.8, step: 0.05,
                                   label: milliseconds(preferences.previewSelectionDelay))
                }
                SettingsDivider()
                SettingsRow(title: "结果展开速度", detail: "0 为立即展开和收起") {
                    SettingsSlider(value: $preferences.resultExpansionDuration, range: 0...0.4, step: 0.025,
                                   label: milliseconds(preferences.resultExpansionDuration))
                }
            }
        }
    }

    private func milliseconds(_ seconds: Double) -> String {
        "\(Int((seconds * 1_000).rounded())) ms"
    }
}
