import SwiftUI

struct SystemCommandsSettingsView: View {
    @ObservedObject var preferences: AppPreferences

    private let newCommands: Set<SystemCommandID> = [
        .lockScreen, .ejectDisks, .toggleMute, .setVolume, .sleepComputer, .restartComputer, .shutDownComputer
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "命令与关键词",
                          footer: "修改关键词后立即生效；留空时仍可用中文名称搜索。关闭的命令不会出现在结果中。") {
                ForEach(Array(SystemCommandID.allCases.enumerated()), id: \.element.id) { index, command in
                    if index > 0 { SettingsDivider() }
                    commandRow(command)
                }
            }
            .settingsTarget("SystemCommandKeywords")

            SettingsGroup(title: "安全") {
                SettingsToggleRow("睡眠、重启、关机前确认", detail: "重启和关机会请求各应用正常退出；清空废纸篓始终确认",
                                  target: "ConfirmPowerActions", isOn: $preferences.behavior.confirmPowerActions)
                SettingsDivider()
                SettingsNoteRow("关键词只选择编译期固定的系统动作，不会作为 Shell、脚本或网址运行。勿扰与主题没有公开的切换接口，只打开对应系统设置。") {
                    Button("恢复默认关键词") { preferences.restoreSystemCommandDefaults() }
                }
            }
        }
    }

    private func commandRow(_ command: SystemCommandID) -> some View {
        HStack(spacing: 12) {
            Toggle(command.title, isOn: enabledBinding(command))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(command.title)
                    if newCommands.contains(command) { NewBadge() }
                }
                Text(command.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(preferences.isSystemCommandEnabled(command) ? 1 : 0.55)
            if duplicateKeywords.contains(normalizedKeyword(command)) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("关键词与其他系统命令重复")
                    .accessibilityLabel("关键词重复")
            }
            TextField("关键词", text: keywordBinding(command))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 120)
                .disabled(!preferences.isSystemCommandEnabled(command))
                .accessibilityLabel(command.title + "关键词")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func enabledBinding(_ command: SystemCommandID) -> Binding<Bool> {
        Binding(
            get: { preferences.isSystemCommandEnabled(command) },
            set: { preferences.setSystemCommand(command, enabled: $0) }
        )
    }

    private func keywordBinding(_ command: SystemCommandID) -> Binding<String> {
        Binding(
            get: { preferences.systemCommandKeywords[command, default: command.defaultKeyword] },
            set: { preferences.setSystemCommandKeyword($0, for: command) }
        )
    }

    private func normalizedKeyword(_ command: SystemCommandID) -> String {
        preferences.systemCommandKeywords[command, default: command.defaultKeyword]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var duplicateKeywords: Set<String> {
        let keywords = SystemCommandID.allCases
            .filter(preferences.isSystemCommandEnabled)
            .map(normalizedKeyword)
            .filter { !$0.isEmpty }
        let counts = Dictionary(grouping: keywords, by: { $0 }).mapValues(\.count)
        return Set(counts.compactMap { $0.value > 1 ? $0.key : nil })
    }
}
