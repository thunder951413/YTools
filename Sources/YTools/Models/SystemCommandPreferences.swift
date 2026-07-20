import Foundation

enum SystemCommandID: String, Codable, CaseIterable, Identifiable, Sendable {
    case emptyTrash
    case showTrash
    case screenSaver
    case sleepDisplays
    case focusSettings
    case appearanceSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emptyTrash: "清空废纸篓"
        case .showTrash: "显示废纸篓"
        case .screenSaver: "启动屏幕保护程序"
        case .sleepDisplays: "关闭显示器"
        case .focusSettings: "打开专注模式设置"
        case .appearanceSettings: "打开系统外观设置"
        }
    }

    var detail: String {
        switch self {
        case .emptyTrash: "由 Finder 清空所有卷的废纸篓；执行前始终确认"
        case .showTrash: "在访达中打开废纸篓"
        case .screenSaver: "立即运行 macOS 屏幕保护程序"
        case .sleepDisplays: "让显示器立即睡眠，不退出应用"
        case .focusSettings: "打开勿扰模式与专注模式设置；不模拟点击"
        case .appearanceSettings: "打开系统深浅主题设置；不使用私有接口切换"
        }
    }

    var defaultKeyword: String {
        switch self {
        case .emptyTrash: "empty"
        case .showTrash: "trash"
        case .screenSaver: "screensaver"
        case .sleepDisplays: "sleepdisplays"
        case .focusSettings: "dnd"
        case .appearanceSettings: "theme"
        }
    }
}

struct SystemCommandConfiguration: Sendable {
    let enabled: Set<SystemCommandID>
    let keywords: [SystemCommandID: String]
}
