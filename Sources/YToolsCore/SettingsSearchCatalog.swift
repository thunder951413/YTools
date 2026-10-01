import Foundation

/// Searchable settings categories shared by the native settings UI.
public enum SettingsSearchCatalog {
    private static let keywords: [String: [String]] = [
        "general": ["通用", "启动", "登录", "位置", "恢复", "学习", "语言", "输入源", "keyboard", "菜单栏", "状态栏", "图标", "隐藏"],
        "search": ["搜索", "结果", "文件", "词典", "范围", "spotlight", "标签", "tag", "隐藏", "排序", "升序", "降序", "通配", "输入", "停顿", "延迟"],
        "customApplications": ["自定义应用", "应用", "程序", "添加", "app", "application", "路径", "别名"],
        "applicationAliases": ["应用", "程序", "别名", "简称", "拼音", "alias", "微信", "weixin"],
        "systemCommands": ["系统", "命令", "empty", "trash", "废纸篓", "屏保", "显示器", "睡眠", "勿扰", "专注", "主题", "外观", "dnd", "theme"],
        "appearance": ["外观", "主题", "风格", "极简", "经典", "现代", "玻璃", "深色", "浅色", "紧凑", "副标题", "预览", "延迟", "展开", "速度", "动画", "quick look"],
        "shortcuts": ["快捷键", "热键", "启动器", "剪贴板", "hotkey"],
        "clipboard": ["剪贴板", "历史", "保留", "记录", "条数", "长度", "字符", "图片", "忽略", "应用", "同步", "坚果云", "jianguoyun", "webdav", "云端", "账号", "用户名", "应用密码", "同步口令", "密码", "passphrase", "sync", "保留天数", "暂停"],
        "snippets": ["片段", "文本", "snippet", "关键词", "占位符", "缩写", "模板", "导入", "导出"],
        "privacy": ["隐私", "安全", "加密", "网络", "权限", "敏感"]
    ]

    public static func matches(sectionID: String, query: String) -> Bool {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return true }
        guard let words = keywords[sectionID] else { return false }
        return terms.allSatisfy { term in words.contains { $0.localizedCaseInsensitiveContains(term) } }
    }
}
