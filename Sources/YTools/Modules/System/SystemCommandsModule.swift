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
            )
        ]
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
