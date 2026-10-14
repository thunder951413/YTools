import Combine
import SwiftUI
import YToolsCore

enum SettingsSectionGroup: String, CaseIterable, Identifiable {
    case basics
    case search
    case tools
    case clipboard
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basics: "常规"
        case .search: "搜索"
        case .tools: "工具"
        case .clipboard: "剪贴板"
        case .system: "系统"
        }
    }

    var sections: [SettingsSection] {
        SettingsSection.allCases.filter { $0.group == self }
    }
}

/// Sidebar order mirrors `SettingsSearchCatalog.sectionIDs`.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case shortcuts
    case search
    case apps
    case files
    case tools
    case system
    case clipboard
    case sync
    case snippets
    case permissions
    case privacy

    var id: String { rawValue }

    var group: SettingsSectionGroup {
        switch self {
        case .general, .appearance, .shortcuts: .basics
        case .search, .apps, .files: .search
        case .tools, .system: .tools
        case .clipboard, .sync, .snippets: .clipboard
        case .permissions, .privacy: .system
        }
    }

    var title: String {
        switch self {
        case .general: "通用"
        case .appearance: "外观"
        case .shortcuts: "快捷键"
        case .search: "搜索与结果"
        case .apps: "应用"
        case .files: "文件"
        case .tools: "内置工具"
        case .system: "系统命令"
        case .clipboard: "剪贴板"
        case .sync: "坚果云同步"
        case .snippets: "文本片段"
        case .permissions: "权限"
        case .privacy: "隐私与数据"
        }
    }

    var summary: String {
        switch self {
        case .general: "启动方式、窗口位置与输入语言"
        case .appearance: "启动器风格、颜色、结果密度与动效"
        case .shortcuts: "全局快捷键，以及给应用、文件夹和片段绑定的快捷键"
        case .search: "哪些结果出现在启动器里，以及搜索的节奏"
        case .apps: "自定义应用、别名与运行中的应用"
        case .files: "搜索范围、常用文件夹、文件动作与预览"
        case .tools: "文本转换、时间日期、计算器、生成工具与 Emoji"
        case .system: "用关键词触发的系统动作"
        case .clipboard: "记录、粘贴方式与过滤规则"
        case .sync: "端到端加密的多设备剪贴板"
        case .snippets: "加密保存的常用文本，输入关键词即可调出"
        case .permissions: "可选功能需要的 macOS 权限与当前状态"
        case .privacy: "本机数据、诊断与维护"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "circle.lefthalf.filled"
        case .shortcuts: "command"
        case .search: "magnifyingglass"
        case .apps: "square.grid.2x2.fill"
        case .files: "folder.fill"
        case .tools: "slider.horizontal.3"
        case .system: "power"
        case .clipboard: "doc.on.clipboard.fill"
        case .sync: "arrow.triangle.2.circlepath"
        case .snippets: "text.alignleft"
        case .permissions: "hand.raised.fill"
        case .privacy: "lock.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: Color(hexString: "#8E8E93")
        case .appearance: Color(hexString: "#AF52DE")
        case .shortcuts: Color(hexString: "#5E5CE6")
        case .search: Color(hexString: "#2F6FEB")
        case .apps: Color(hexString: "#E8590C")
        case .files: Color(hexString: "#1C8DCB")
        case .tools: Color(hexString: "#2E9D4E")
        case .system: Color(hexString: "#636366")
        case .clipboard: Color(hexString: "#D9480F")
        case .sync: Color(hexString: "#1098AD")
        case .snippets: Color(hexString: "#B7791F")
        case .permissions: Color(hexString: "#D6336C")
        case .privacy: Color(hexString: "#495057")
        }
    }
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var selection: SettingsSection = .general
    @Published var searchText = ""
    @Published var targetID: String?
    @Published var targetRevision = 0

    func open(_ target: SettingsSearchTarget) {
        guard let section = SettingsSection(rawValue: target.sectionID) else { return }
        selection = section
        searchText = ""
        targetID = target.id
        targetRevision += 1
    }

    func select(_ section: SettingsSection) {
        selection = section
        targetID = nil
        searchText = ""
    }

    func matches(_ section: SettingsSection) -> Bool {
        SettingsSearchCatalog.matches(sectionID: section.rawValue, query: searchText)
    }
}

extension Notification.Name {
    static let focusYToolsSettingsSearch = Notification.Name("YTools.focusSettingsSearch")
}
