import Foundation

enum SystemCommandID: String, Codable, CaseIterable, Identifiable, Sendable {
    case emptyTrash
    case showTrash
    case screenSaver
    case sleepDisplays
    case focusSettings
    case appearanceSettings
    case lockScreen
    case ejectDisks
    case toggleMute
    case setVolume
    case sleepComputer
    case restartComputer
    case shutDownComputer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emptyTrash: "清空废纸篓"
        case .showTrash: "显示废纸篓"
        case .screenSaver: "启动屏幕保护程序"
        case .sleepDisplays: "关闭显示器"
        case .focusSettings: "打开专注模式设置"
        case .appearanceSettings: "打开系统外观设置"
        case .lockScreen: "锁定屏幕"
        case .ejectDisks: "推出所有外接磁盘"
        case .toggleMute: "静音 / 取消静音"
        case .setVolume: "设置音量"
        case .sleepComputer: "睡眠"
        case .restartComputer: "重新启动"
        case .shutDownComputer: "关机"
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
        case .lockScreen: "需要辅助功能权限；未授权时改为关闭显示器"
        case .ejectDisks: "安全推出可移除磁盘和磁盘映像"
        case .toggleMute: "切换默认输出设备的静音状态"
        case .setVolume: "输入 vol 40 将音量设为 40%"
        case .sleepComputer: "让 Mac 进入睡眠"
        case .restartComputer: "请求所有应用正常退出后重启"
        case .shutDownComputer: "请求所有应用正常退出后关机"
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
        case .lockScreen: "lock"
        case .ejectDisks: "eject"
        case .toggleMute: "mute"
        case .setVolume: "vol"
        case .sleepComputer: "sleep"
        case .restartComputer: "restart"
        case .shutDownComputer: "shutdown"
        }
    }
}

struct SystemCommandConfiguration: Sendable {
    let enabled: Set<SystemCommandID>
    let keywords: [SystemCommandID: String]
}
