import Combine
import Foundation
import YToolsCore

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case search
    case customApplications
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
        case .customApplications: "自定义应用"
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
        case .customApplications: "app.badge.plus"
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
        SettingsSearchCatalog.matches(sectionID: section.rawValue, query: searchText)
    }
}

extension Notification.Name {
    static let focusYToolsSettingsSearch = Notification.Name("YTools.focusSettingsSearch")
}
