import Foundation

/// Searchable settings categories shared by the native settings UI.
public enum SettingsSearchCatalog {
    /// Section identifiers in sidebar order; the macOS `SettingsSection` enum mirrors these.
    public static let sectionIDs = [
        "general", "appearance", "shortcuts", "search", "apps", "files", "tools",
        "system", "clipboard", "sync", "snippets", "permissions", "privacy"
    ]

    private static let keywords: [String: [String]] = [
        "general": ["通用", "启动", "登录", "位置", "窗口", "显示器", "屏幕", "语言", "输入源", "输入法", "keyboard", "菜单栏", "状态栏", "图标", "隐藏"],
        "appearance": ["外观", "主题", "风格", "极简", "经典", "现代", "玻璃", "深色", "浅色", "颜色", "强调色", "紧凑", "副标题", "宽度", "圆角", "预览", "延迟", "展开", "速度", "动画", "动效", "quick look"],
        "shortcuts": ["快捷键", "热键", "启动器", "剪贴板", "截图", "识别", "文字", "ocr", "连续粘贴", "自定义", "hotkey"],
        "search": ["搜索", "结果", "类型", "模块", "词典", "释义", "输入", "停顿", "延迟", "条数", "默认结果"],
        "apps": ["应用", "程序", "自定义应用", "添加", "app", "application", "别名", "简称", "拼音", "alias", "微信", "weixin", "运行中", "退出", "隐藏", "切换"],
        "files": ["文件", "文件夹", "目录", "范围", "spotlight", "常用", "收藏", "移到", "终端", "terminal", "压缩", "zip", "新建", "扩展名", "隐藏", "排序", "升序", "降序", "预览", "pdf", "office", "通配"],
        "tools": ["工具", "文本", "转换", "tx", "大小写", "json", "base64", "编码", "哈希", "时间", "日期", "时间戳", "时区", "城市", "计算器", "进制", "百分比", "密码", "uuid", "二维码", "qr", "颜色", "emoji", "表情", "符号", "肤色"],
        "system": ["系统", "命令", "empty", "trash", "废纸篓", "屏保", "显示器", "锁屏", "锁定", "推出", "静音", "音量", "睡眠", "重启", "关机", "勿扰", "专注", "主题", "dnd", "theme"],
        "clipboard": ["剪贴板", "历史", "保留", "记录", "条数", "长度", "字符", "图片", "粘贴", "连续", "忽略", "应用", "规则", "正则", "敏感", "验证码", "保留天数", "暂停"],
        "sync": ["同步", "坚果云", "jianguoyun", "webdav", "云端", "账号", "用户名", "应用密码", "同步口令", "密码", "passphrase", "sync", "远端", "间隔"],
        "snippets": ["片段", "文本", "snippet", "关键词", "占位符", "缩写", "模板"],
        "permissions": ["权限", "辅助功能", "屏幕录制", "自动化", "访达", "授权", "accessibility", "隐私"],
        "privacy": ["隐私", "安全", "加密", "网络", "数据", "诊断", "维护", "清除", "恢复", "默认", "敏感"]
    ]

    public static func matches(sectionID: String, query: String) -> Bool {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return true }
        guard let words = keywords[sectionID] else { return false }
        return terms.allSatisfy { term in words.contains { $0.localizedCaseInsensitiveContains(term) } }
    }
}
