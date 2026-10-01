namespace YTools.Core;

public sealed record SettingsSearchTarget(string Id, string SectionId, string WindowsSectionId, string Title, string RowTitle, string Keywords);

public static partial class SettingsSearchCatalog
{
    public static IReadOnlyList<SettingsSearchTarget> Targets { get; } =
    [
        new("LaunchAtLogin", "general", "general", "登录时启动", "登录时启动 YTools", "开机 启动 自动 登录"),
        new("ShowTrayIcon", "general", "general", "菜单栏 / 托盘图标", "显示菜单栏图标", "状态栏 隐藏 后台 图标 tray"),
        new("Theme", "appearance", "general", "颜色模式 / 主题", "颜色模式", "外观 深色 浅色 亮色 dark light theme"),
        new("AccentColor", "appearance", "general", "强调色", "强调色", "颜色 选中 高亮"),
        new("PanelPosition", "general", "appearance", "默认窗口位置", "窗口位置", "默认位置 屏幕 居中 顶部 记忆"),
        new("ScreenPreference", "general", "appearance", "显示器偏好", "显示器", "多屏 屏幕 鼠标 主屏"),
        new("PanelWidth", "appearance", "appearance", "面板宽度", "面板宽度", "窗口 宽度 尺寸"),
        new("PanelCornerRadius", "appearance", "appearance", "圆角半径", "外层圆角", "圆角 外观 边缘"),
        new("CompactResults", "appearance", "appearance", "紧凑结果行", "", "行高 间距 紧凑"),
        new("ShowSubtitles", "appearance", "appearance", "结果副标题与路径", "", "副标题 文件路径"),
        new("ShowNumberShortcuts", "appearance", "appearance", "数字快捷执行提示", "", "数字 快捷 提示"),
        new("LauncherAppearanceStyle", "appearance", "appearance", "启动器风格", "", "外观 风格 极简 经典 现代 玻璃"),
        new("PreviewSelectionDelay", "appearance", "appearance", "预览切换停留时间", "预览切换停留时间", "预览 延迟 quick look"),
        new("ResultExpansionDuration", "appearance", "appearance", "结果展开速度", "结果展开速度", "展开 速度 动画 停顿"),
        new("SearchInputDelay", "search", "search", "输入停止后搜索", "输入停止后搜索", "搜索 输入 停顿 延迟 毫秒"),
        new("MaximumSearchResults", "search", "search", "最大结果数", "最多文件结果", "搜索 最大 结果 条数 文件"),
        new("IncludeFilesInDefaultResults", "search", "search", "默认结果包含文件", "", "默认 文件 搜索"),
        new("EnabledSearchContentTypes", "search", "search", "搜索内容类型", "", "模块 词典 应用 搜索 类型"),
        new("SearchScopePaths", "search", "search", "搜索范围", "", "目录 范围 spotlight 路径"),
        new("FileNavigationShowsHiddenFiles", "search", "search", "显示隐藏文件", "", "隐藏 文件 导航"),
        new("FileNavigationSort", "search", "search", "文件排序方式", "排序依据", "名称 日期 修改时间 创建时间 排序"),
        new("FileNavigationSortAscending", "search", "search", "文件升序排列", "", "升序 降序 排列"),
        new("FileNavigationFoldersFirst", "search", "search", "文件夹优先", "", "文件夹 优先 排序"),
        new("ClipboardEnabled", "clipboard", "clipboard", "记录剪贴板历史", "", "启用 记录 剪贴板 历史"),
        new("ClipboardPaused", "clipboard", "clipboard", "暂停剪贴板记录", "", "暂停 保留 历史"),
        new("ClipboardRetentionDays", "clipboard", "clipboard", "保留天数", "保留时间", "历史 保留 天数 时间 过期"),
        new("ClipboardMaximumItems", "clipboard", "clipboard", "最多记录条数", "最多记录", "历史 最大 条数 规模"),
        new("ClipboardMaximumTextCharacters", "clipboard", "clipboard", "文本长度上限", "文本长度上限", "文本 长度 字符 上限"),
        new("ClipboardStoreImages", "clipboard", "clipboard", "记录剪贴板图片", "", "图片 保存 历史"),
        new("ClipboardIgnoredApplications", "clipboard", "clipboard", "忽略的应用 / 进程", "", "忽略 应用 进程 密码管理器"),
        new("ClipboardCloudSyncEnabled", "clipboard", "clipboard", "启用坚果云同步", "", "同步 坚果云 webdav 云端 sync jianguoyun"),
        new("ClipboardCloudSyncFolder", "clipboard", "clipboard", "坚果云远端目录", "远端目录", "同步 webdav 远端 目录 路径"),
        new("ClipboardCloudSyncIntervalMinutes", "clipboard", "clipboard", "后台拉取间隔", "拉取间隔", "同步 拉取 间隔 时间"),
        new("CloudUsername", "clipboard", "clipboard", "坚果云用户名", "", "坚果云 webdav 账号 用户名"),
        new("CloudAppPassword", "clipboard", "clipboard", "坚果云应用密码", "", "坚果云 webdav 应用密码 认证 密码"),
        new("CloudPassphrase", "clipboard", "clipboard", "同步口令", "", "坚果云 webdav 同步口令 passphrase 加密 密钥 密码"),
        new("LauncherHotKey", "shortcuts", "shortcuts", "启动器快捷键", "显示启动器", "主快捷键 热键 hotkey launcher"),
        new("ClipboardHotKey", "shortcuts", "shortcuts", "剪贴板快捷键", "剪贴板历史", "热键 剪贴板 hotkey"),
    ];
    public static IReadOnlyList<SettingsSearchTarget> SearchTargets(string query)
    {
        var terms = query.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        if (terms.Length == 0) { return []; }
        return Targets.Where(target => terms.All(term =>
            (target.Title + " " + target.RowTitle + " " + target.Keywords).Contains(term, StringComparison.OrdinalIgnoreCase))).ToList();
    }
}
