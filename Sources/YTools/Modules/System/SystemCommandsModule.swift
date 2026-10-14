import Foundation
import YToolsModuleKit

/// A fixed native allowlist. User-editable keywords select a compiled action;
/// they are never used as executable paths, shell input, URLs or arguments.
struct SystemCommandsModule: YToolsModule {
    let descriptor = ModuleDescriptor(id: "system-commands", name: "系统命令")
    let configuration: SystemCommandConfiguration

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        let term = request.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return [] }
        if let volume = volumeResult(for: term) { return [volume] }
        return commands.compactMap { command in
            guard configuration.enabled.contains(command.id) else { return nil }
            let keyword = configuration.keywords[command.id, default: command.id.defaultKeyword]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let keywordMatches = !keyword.isEmpty
                && (keyword.hasPrefix(term) || term.hasPrefix(keyword))
            let titleMatches = command.id.title.localizedCaseInsensitiveContains(term)
            guard keywordMatches || titleMatches else { return nil }
            return command.result.withScore(term == keyword ? 1_300 : command.result.score)
        }
    }

    private var commands: [(id: SystemCommandID, result: LauncherResult)] {
        [
            command(
                .emptyTrash,
                subtitle: "由 Finder 清空所有卷的废纸篓；执行前需要确认",
                icon: "trash.slash",
                score: 1_220,
                action: .emptyTrash
            ),
            command(
                .showTrash,
                subtitle: "在访达中打开废纸篓；不会删除文件",
                icon: "trash",
                score: 1_150,
                action: .showTrash
            ),
            command(
                .screenSaver,
                subtitle: "运行 macOS 屏幕保护程序",
                icon: "sparkles.rectangle.stack",
                score: 1_120,
                action: .startScreenSaver
            ),
            command(
                .sleepDisplays,
                subtitle: "让所有显示器立即睡眠；不会退出应用",
                icon: "display.trianglebadge.exclamationmark",
                score: 1_180,
                action: .sleepDisplays
            ),
            command(
                .focusSettings,
                subtitle: "打开勿扰模式与专注模式设置",
                icon: "moon.fill",
                score: 1_080,
                action: .openFocusSettings
            ),
            command(
                .appearanceSettings,
                subtitle: "打开系统深浅主题与强调色设置",
                icon: "circle.lefthalf.filled",
                score: 1_080,
                action: .openAppearanceSettings
            ),
            command(.lockScreen, subtitle: "立即锁定 Mac", icon: "lock", score: 1_200, action: .lockScreen),
            command(.ejectDisks, subtitle: "安全推出可移除磁盘和磁盘映像", icon: "eject", score: 1_160, action: .ejectDisks),
            command(.toggleMute, subtitle: "切换默认输出设备的静音状态", icon: "speaker.slash", score: 1_160, action: .toggleMute),
            command(.setVolume, subtitle: "继续输入数字，例如 vol 40", icon: "speaker.wave.2", score: 1_100,
                    action: .editQuery(configuration.keywords[.setVolume, default: SystemCommandID.setVolume.defaultKeyword] + " ")),
            command(.sleepComputer, subtitle: "让 Mac 进入睡眠", icon: "powersleep", score: 1_140, action: .sleepComputer),
            command(.restartComputer, subtitle: "请求所有应用正常退出后重启", icon: "restart", score: 1_100, action: .restartComputer),
            command(.shutDownComputer, subtitle: "请求所有应用正常退出后关机", icon: "power", score: 1_100, action: .shutDownComputer)
        ]
    }

    /// `vol 40` / `音量 40` sets the output volume directly.
    private func volumeResult(for term: String) -> LauncherResult? {
        guard configuration.enabled.contains(.setVolume) else { return nil }
        let keyword = configuration.keywords[.setVolume, default: SystemCommandID.setVolume.defaultKeyword]
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in [keyword, "音量"] where !prefix.isEmpty && term.hasPrefix(prefix + " ") {
            let value = term.dropFirst(prefix.count + 1).trimmingCharacters(in: CharacterSet(charactersIn: " %"))
            guard let percent = Int(value), (0...100).contains(percent) else { return nil }
            return LauncherResult(
                id: "system:setVolume:\(percent)",
                moduleID: descriptor.id,
                title: "音量设为 \(percent)%",
                subtitle: percent == 0 ? "等同于静音" : "调整默认输出设备音量",
                icon: .system(percent == 0 ? "speaker.slash" : "speaker.wave.2"),
                score: 1_320,
                action: .setVolume(percent)
            )
        }
        return nil
    }

    private func command(
        _ id: SystemCommandID,
        subtitle: String,
        icon: String,
        score: Int,
        action: ResultAction
    ) -> (id: SystemCommandID, result: LauncherResult) {
        (
            id,
            LauncherResult(
                id: "system:\(id.rawValue)",
                moduleID: descriptor.id,
                title: id.title,
                subtitle: subtitle,
                icon: .system(icon),
                score: score,
                action: action
            )
        )
    }
}
