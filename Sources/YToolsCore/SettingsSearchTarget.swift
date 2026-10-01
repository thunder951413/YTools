import Foundation

public struct SettingsSearchTarget: Identifiable, Sendable, Equatable {
    public let id: String
    public let sectionID: String
    public let windowsSectionID: String
    public let title: String
    public let rowTitle: String
    public let keywords: String
}

extension SettingsSearchCatalog {
    public static let targets: [SettingsSearchTarget] = [
        SettingsSearchTarget(id: "LaunchAtLogin", sectionID: "general", windowsSectionID: "general", title: "登录时启动", rowTitle: "登录时启动 YTools", keywords: "开机 启动 自动 登录"),
        SettingsSearchTarget(id: "ShowTrayIcon", sectionID: "general", windowsSectionID: "general", title: "菜单栏 / 托盘图标", rowTitle: "显示菜单栏图标", keywords: "状态栏 隐藏 后台 图标 tray"),
        SettingsSearchTarget(id: "Theme", sectionID: "appearance", windowsSectionID: "general", title: "颜色模式 / 主题", rowTitle: "颜色模式", keywords: "外观 深色 浅色 亮色 dark light theme"),
        SettingsSearchTarget(id: "AccentColor", sectionID: "appearance", windowsSectionID: "general", title: "强调色", rowTitle: "强调色", keywords: "颜色 选中 高亮"),
        SettingsSearchTarget(id: "PanelPosition", sectionID: "general", windowsSectionID: "appearance", title: "默认窗口位置", rowTitle: "窗口位置", keywords: "默认位置 屏幕 居中 顶部 记忆"),
        SettingsSearchTarget(id: "ScreenPreference", sectionID: "general", windowsSectionID: "appearance", title: "显示器偏好", rowTitle: "显示器", keywords: "多屏 屏幕 鼠标 主屏"),
        SettingsSearchTarget(id: "PanelWidth", sectionID: "appearance", windowsSectionID: "appearance", title: "面板宽度", rowTitle: "面板宽度", keywords: "窗口 宽度 尺寸"),
        SettingsSearchTarget(id: "PanelCornerRadius", sectionID: "appearance", windowsSectionID: "appearance", title: "圆角半径", rowTitle: "外层圆角", keywords: "圆角 外观 边缘"),
        SettingsSearchTarget(id: "CompactResults", sectionID: "appearance", windowsSectionID: "appearance", title: "紧凑结果行", rowTitle: "", keywords: "行高 间距 紧凑"),
        SettingsSearchTarget(id: "ShowSubtitles", sectionID: "appearance", windowsSectionID: "appearance", title: "结果副标题与路径", rowTitle: "", keywords: "副标题 文件路径"),
        SettingsSearchTarget(id: "ShowNumberShortcuts", sectionID: "appearance", windowsSectionID: "appearance", title: "数字快捷执行提示", rowTitle: "", keywords: "数字 快捷 提示"),
        SettingsSearchTarget(id: "LauncherAppearanceStyle", sectionID: "appearance", windowsSectionID: "appearance", title: "启动器风格", rowTitle: "", keywords: "外观 风格 极简 经典 现代 玻璃"),
        SettingsSearchTarget(id: "PreviewSelectionDelay", sectionID: "appearance", windowsSectionID: "appearance", title: "预览切换停留时间", rowTitle: "预览切换停留时间", keywords: "预览 延迟 quick look"),
        SettingsSearchTarget(id: "ResultExpansionDuration", sectionID: "appearance", windowsSectionID: "appearance", title: "结果展开速度", rowTitle: "结果展开速度", keywords: "展开 速度 动画 停顿"),
        SettingsSearchTarget(id: "SearchInputDelay", sectionID: "search", windowsSectionID: "search", title: "输入停止后搜索", rowTitle: "输入停止后搜索", keywords: "搜索 输入 停顿 延迟 毫秒"),
        SettingsSearchTarget(id: "MaximumSearchResults", sectionID: "search", windowsSectionID: "search", title: "最大结果数", rowTitle: "最多文件结果", keywords: "搜索 最大 结果 条数 文件"),
        SettingsSearchTarget(id: "IncludeFilesInDefaultResults", sectionID: "search", windowsSectionID: "search", title: "默认结果包含文件", rowTitle: "", keywords: "默认 文件 搜索"),
        SettingsSearchTarget(id: "EnabledSearchContentTypes", sectionID: "search", windowsSectionID: "search", title: "搜索内容类型", rowTitle: "", keywords: "模块 词典 应用 搜索 类型"),
        SettingsSearchTarget(id: "SearchScopePaths", sectionID: "search", windowsSectionID: "search", title: "搜索范围", rowTitle: "", keywords: "目录 范围 spotlight 路径"),
        SettingsSearchTarget(id: "FileNavigationShowsHiddenFiles", sectionID: "search", windowsSectionID: "search", title: "显示隐藏文件", rowTitle: "", keywords: "隐藏 文件 导航"),
        SettingsSearchTarget(id: "FileNavigationSort", sectionID: "search", windowsSectionID: "search", title: "文件排序方式", rowTitle: "排序依据", keywords: "名称 日期 修改时间 创建时间 排序"),
        SettingsSearchTarget(id: "FileNavigationSortAscending", sectionID: "search", windowsSectionID: "search", title: "文件升序排列", rowTitle: "", keywords: "升序 降序 排列"),
        SettingsSearchTarget(id: "FileNavigationFoldersFirst", sectionID: "search", windowsSectionID: "search", title: "文件夹优先", rowTitle: "", keywords: "文件夹 优先 排序"),
        SettingsSearchTarget(id: "ClipboardEnabled", sectionID: "clipboard", windowsSectionID: "clipboard", title: "记录剪贴板历史", rowTitle: "", keywords: "启用 记录 剪贴板 历史"),
        SettingsSearchTarget(id: "ClipboardPaused", sectionID: "clipboard", windowsSectionID: "clipboard", title: "暂停剪贴板记录", rowTitle: "", keywords: "暂停 保留 历史"),
        SettingsSearchTarget(id: "ClipboardRetentionDays", sectionID: "clipboard", windowsSectionID: "clipboard", title: "保留天数", rowTitle: "保留时间", keywords: "历史 保留 天数 时间 过期"),
        SettingsSearchTarget(id: "ClipboardMaximumItems", sectionID: "clipboard", windowsSectionID: "clipboard", title: "最多记录条数", rowTitle: "最多记录", keywords: "历史 最大 条数 规模"),
        SettingsSearchTarget(id: "ClipboardMaximumTextCharacters", sectionID: "clipboard", windowsSectionID: "clipboard", title: "文本长度上限", rowTitle: "文本长度上限", keywords: "文本 长度 字符 上限"),
        SettingsSearchTarget(id: "ClipboardStoreImages", sectionID: "clipboard", windowsSectionID: "clipboard", title: "记录剪贴板图片", rowTitle: "", keywords: "图片 保存 历史"),
        SettingsSearchTarget(id: "ClipboardIgnoredApplications", sectionID: "clipboard", windowsSectionID: "clipboard", title: "忽略的应用 / 进程", rowTitle: "", keywords: "忽略 应用 进程 密码管理器"),
        SettingsSearchTarget(id: "ClipboardCloudSyncEnabled", sectionID: "clipboard", windowsSectionID: "clipboard", title: "启用坚果云同步", rowTitle: "", keywords: "同步 坚果云 webdav 云端 sync jianguoyun"),
        SettingsSearchTarget(id: "ClipboardCloudSyncFolder", sectionID: "clipboard", windowsSectionID: "clipboard", title: "坚果云远端目录", rowTitle: "远端目录", keywords: "同步 webdav 远端 目录 路径"),
        SettingsSearchTarget(id: "ClipboardCloudSyncIntervalMinutes", sectionID: "clipboard", windowsSectionID: "clipboard", title: "后台拉取间隔", rowTitle: "拉取间隔", keywords: "同步 拉取 间隔 时间"),
        SettingsSearchTarget(id: "CloudUsername", sectionID: "clipboard", windowsSectionID: "clipboard", title: "坚果云用户名", rowTitle: "", keywords: "坚果云 webdav 账号 用户名"),
        SettingsSearchTarget(id: "CloudAppPassword", sectionID: "clipboard", windowsSectionID: "clipboard", title: "坚果云应用密码", rowTitle: "", keywords: "坚果云 webdav 应用密码 认证 密码"),
        SettingsSearchTarget(id: "CloudPassphrase", sectionID: "clipboard", windowsSectionID: "clipboard", title: "同步口令", rowTitle: "", keywords: "坚果云 webdav 同步口令 passphrase 加密 密钥 密码"),
        SettingsSearchTarget(id: "LauncherHotKey", sectionID: "shortcuts", windowsSectionID: "shortcuts", title: "启动器快捷键", rowTitle: "显示启动器", keywords: "主快捷键 热键 hotkey launcher"),
        SettingsSearchTarget(id: "ClipboardHotKey", sectionID: "shortcuts", windowsSectionID: "shortcuts", title: "剪贴板快捷键", rowTitle: "剪贴板历史", keywords: "热键 剪贴板 hotkey"),
    ]
    public static func searchTargets(_ query: String) -> [SettingsSearchTarget] {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return [] }
        return targets.filter { target in
            let haystack = target.title + " " + target.rowTitle + " " + target.keywords
            return terms.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
        }
    }
    public static func targetID(forRowTitle title: String) -> String? {
        targets.first { !$0.rowTitle.isEmpty && $0.rowTitle == title }?.id
    }
}
