import SwiftUI

struct SystemCommandsSettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "本机系统命令", icon: "gearshape.2") {
                Text("关键词只选择下列编译期固定动作，不会作为 Shell、脚本、URL 或可执行参数运行。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(SystemCommandID.allCases.enumerated()), id: \.element.id) { index, command in
                    if index > 0 { Divider() }
                    commandRow(command)
                }
            }

            SettingsCard(title: "行为说明", icon: "lock.shield") {
                PrivacyLine(
                    icon: "trash.slash",
                    title: "永久删除始终确认",
                    detail: "empty 只向 Finder 发送固定清空命令；首次使用需允许控制 Finder。"
                )
                Divider()
                PrivacyLine(
                    icon: "moon.fill",
                    title: "勿扰和主题",
                    detail: "macOS 没有公开的安全切换 API，因此只打开对应系统设置页。"
                )
                Divider()
                HStack {
                    Text("修改关键词后立即生效；留空可只通过中文名称搜索。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("恢复默认命令") { preferences.restoreSystemCommandDefaults() }
                }
            }
        }
    }

    @ViewBuilder
    private func commandRow(_ command: SystemCommandID) -> some View {
        HStack(spacing: 14) {
            Toggle("", isOn: enabledBinding(command))
                .labelsHidden()
            VStack(alignment: .leading, spacing: 3) {
                Text(command.title)
                Text(command.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("关键词", text: keywordBinding(command))
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
                .disabled(!preferences.isSystemCommandEnabled(command))
            if duplicateKeywords.contains(normalizedKeyword(command)) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("关键词与其他系统命令重复")
            }
        }
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
