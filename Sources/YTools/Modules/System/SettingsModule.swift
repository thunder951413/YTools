import Foundation
import YToolsModuleKit

struct SettingsModule: YToolsModule {
    let descriptor = ModuleDescriptor(id: "settings", name: "设置")

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        let term = request.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let keywords = ["settings", "preferences", "设置", "偏好设置"]
        guard !term.isEmpty, keywords.contains(where: { $0.hasPrefix(term) || term.hasPrefix($0) }) else {
            return []
        }
        return [LauncherResult(
            id: "settings:open",
            moduleID: descriptor.id,
            title: "YTools 设置",
            subtitle: "外观、快捷键、剪贴板和隐私",
            icon: .system("gearshape.fill"),
            score: 880,
            action: .openSettings
        )]
    }
}
