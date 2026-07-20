import Combine
import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case search
    case applicationAliases
    case systemCommands
    case appearance
    case shortcuts
    case clipboard
    case snippets
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .search: "搜索与结果"
        case .applicationAliases: "应用别名"
        case .systemCommands: "系统命令"
        case .appearance: "外观"
        case .shortcuts: "快捷键"
        case .clipboard: "剪贴板"
        case .snippets: "文本片段"
        case .privacy: "隐私与安全"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .search: "magnifyingglass"
        case .applicationAliases: "app.badge"
        case .systemCommands: "gearshape.2"
        case .appearance: "paintbrush"
        case .shortcuts: "command"
        case .clipboard: "clipboard"
        case .snippets: "text.quote"
        case .privacy: "lock.shield"
        }
    }
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var selection: SettingsSection = .general
    @Published var searchText = ""

    func matches(_ section: SettingsSection) -> Bool {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return true }
        let keywords: [SettingsSection: [String]] = [
            .general: ["通用", "启动", "登录", "位置", "恢复", "学习", "语言", "输入源", "keyboard", "菜单栏", "状态栏", "图标", "隐藏"],
            .search: ["搜索", "结果", "文件", "词典", "范围", "spotlight", "标签", "tag", "隐藏", "排序", "升序", "降序", "通配", "输入", "停顿", "延迟"],
            .applicationAliases: ["应用", "程序", "别名", "简称", "拼音", "alias", "微信", "weixin"],
            .systemCommands: ["系统", "命令", "empty", "trash", "废纸篓", "屏保", "显示器", "睡眠", "勿扰", "专注", "主题", "外观", "dnd", "theme"],
            .appearance: ["外观", "主题", "风格", "极简", "经典", "现代", "玻璃", "深色", "浅色", "紧凑", "副标题", "预览", "延迟", "展开", "速度", "动画", "quick look"],
            .shortcuts: ["快捷键", "热键", "启动器", "剪贴板", "hotkey"],
            .clipboard: ["剪贴板", "历史", "保留", "记录", "条数", "长度", "字符", "图片", "忽略", "应用"],
            .snippets: ["片段", "文本", "snippet", "关键词", "占位符"],
            .privacy: ["隐私", "安全", "加密", "网络", "权限", "敏感"]
        ]
        return (keywords[section] ?? []).contains { $0.lowercased().contains(term) }
    }
}

extension Notification.Name {
    static let focusYToolsSettingsSearch = Notification.Name("YTools.focusSettingsSearch")
}
