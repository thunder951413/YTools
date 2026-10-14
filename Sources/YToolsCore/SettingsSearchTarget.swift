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
        SettingsSearchTarget(id: "PanelPosition", sectionID: "general", windowsSectionID: "appearance", title: "默认窗口位置", rowTitle: "窗口位置", keywords: "默认位置 屏幕 居中 顶部 记忆"),
        SettingsSearchTarget(id: "ScreenPreference", sectionID: "general", windowsSectionID: "appearance", title: "显示器偏好", rowTitle: "显示器", keywords: "多屏 屏幕 鼠标 主屏"),
        SettingsSearchTarget(id: "KeyboardInputSource", sectionID: "general", windowsSectionID: "general", title: "默认输入语言", rowTitle: "默认输入语言", keywords: "输入法 输入源 英文 中文 keyboard"),
        SettingsSearchTarget(id: "Theme", sectionID: "appearance", windowsSectionID: "general", title: "颜色模式 / 主题", rowTitle: "颜色模式", keywords: "外观 深色 浅色 亮色 dark light theme"),
        SettingsSearchTarget(id: "AccentColor", sectionID: "appearance", windowsSectionID: "general", title: "强调色", rowTitle: "强调色", keywords: "颜色 选中 高亮"),
        SettingsSearchTarget(id: "LauncherAppearanceStyle", sectionID: "appearance", windowsSectionID: "appearance", title: "启动器风格", rowTitle: "", keywords: "外观 风格 极简 经典 现代 玻璃"),
        SettingsSearchTarget(id: "PanelWidth", sectionID: "appearance", windowsSectionID: "appearance", title: "面板宽度", rowTitle: "面板宽度", keywords: "窗口 宽度 尺寸"),
        SettingsSearchTarget(id: "PanelCornerRadius", sectionID: "appearance", windowsSectionID: "appearance", title: "圆角半径", rowTitle: "外层圆角", keywords: "圆角 外观 边缘"),
        SettingsSearchTarget(id: "CompactResults", sectionID: "appearance", windowsSectionID: "appearance", title: "紧凑结果行", rowTitle: "紧凑结果间距", keywords: "行高 间距 紧凑"),
        SettingsSearchTarget(id: "ShowSubtitles", sectionID: "appearance", windowsSectionID: "appearance", title: "结果副标题与路径", rowTitle: "显示副标题和路径", keywords: "副标题 文件路径"),
        SettingsSearchTarget(id: "ShowNumberShortcuts", sectionID: "appearance", windowsSectionID: "appearance", title: "数字快捷执行提示", rowTitle: "显示 ⌘1…9 快速执行提示", keywords: "数字 快捷 提示"),
        SettingsSearchTarget(id: "PreviewSelectionDelay", sectionID: "appearance", windowsSectionID: "appearance", title: "预览切换停留时间", rowTitle: "预览切换停留", keywords: "预览 延迟 quick look"),
        SettingsSearchTarget(id: "ResultExpansionDuration", sectionID: "appearance", windowsSectionID: "appearance", title: "结果展开速度", rowTitle: "结果展开速度", keywords: "展开 速度 动画 停顿"),
        SettingsSearchTarget(id: "LauncherHotKey", sectionID: "shortcuts", windowsSectionID: "shortcuts", title: "启动器快捷键", rowTitle: "显示启动器", keywords: "主快捷键 热键 hotkey launcher"),
        SettingsSearchTarget(id: "ClipboardHotKey", sectionID: "shortcuts", windowsSectionID: "shortcuts", title: "剪贴板快捷键", rowTitle: "剪贴板历史", keywords: "热键 剪贴板 hotkey"),
        SettingsSearchTarget(id: "RecognizeTextHotKey", sectionID: "shortcuts", windowsSectionID: "shortcuts", title: "截图识别文字快捷键", rowTitle: "截图识别文字", keywords: "ocr 截图 识别 文字 热键 hotkey"),
        SettingsSearchTarget(id: "SequentialPasteHotKey", sectionID: "shortcuts", windowsSectionID: "shortcuts", title: "连续粘贴快捷键", rowTitle: "", keywords: "连续 依次 队列 粘贴 热键 hotkey"),
        SettingsSearchTarget(id: "CustomHotKeys", sectionID: "shortcuts", windowsSectionID: "shortcuts", title: "自定义快捷键", rowTitle: "", keywords: "自定义 应用 文件夹 片段 绑定 热键 hotkey"),
        SettingsSearchTarget(id: "EnabledSearchContentTypes", sectionID: "search", windowsSectionID: "search", title: "搜索内容类型", rowTitle: "", keywords: "模块 词典 应用 搜索 类型 结果"),
        SettingsSearchTarget(id: "SearchInputDelay", sectionID: "search", windowsSectionID: "search", title: "输入停止后搜索", rowTitle: "输入停止后搜索", keywords: "搜索 输入 停顿 延迟 毫秒"),
        SettingsSearchTarget(id: "IncludeFilesInDefaultResults", sectionID: "search", windowsSectionID: "search", title: "默认结果包含文件", rowTitle: "默认结果包含本地文件", keywords: "默认 文件 搜索"),
        SettingsSearchTarget(id: "IncludeAutomaticDictionary", sectionID: "search", windowsSectionID: "search", title: "自动显示单词释义", rowTitle: "自动显示单词释义", keywords: "词典 释义 单词"),
        SettingsSearchTarget(id: "MaximumSearchResults", sectionID: "search", windowsSectionID: "search", title: "最大结果数", rowTitle: "最多文件结果", keywords: "搜索 最大 结果 条数 文件"),
        SettingsSearchTarget(id: "CustomApplications", sectionID: "apps", windowsSectionID: "search", title: "自定义应用", rowTitle: "", keywords: "应用 程序 添加 app 路径"),
        SettingsSearchTarget(id: "ApplicationAliases", sectionID: "apps", windowsSectionID: "search", title: "应用别名", rowTitle: "", keywords: "应用 别名 简称 拼音 alias"),
        SettingsSearchTarget(id: "MarkRunningApplications", sectionID: "apps", windowsSectionID: "search", title: "标记运行中的应用", rowTitle: "在结果中标记正在运行", keywords: "运行中 切换 窗口 running"),
        SettingsSearchTarget(id: "ConfirmQuitApplication", sectionID: "apps", windowsSectionID: "search", title: "退出应用前确认", rowTitle: "退出前确认", keywords: "退出 quit 确认 应用"),
        SettingsSearchTarget(id: "SearchScopePaths", sectionID: "files", windowsSectionID: "search", title: "搜索范围", rowTitle: "", keywords: "目录 范围 spotlight 路径"),
        SettingsSearchTarget(id: "FavoriteFolders", sectionID: "files", windowsSectionID: "search", title: "常用文件夹", rowTitle: "", keywords: "常用 收藏 文件夹 移到 移动 复制"),
        SettingsSearchTarget(id: "TerminalApplication", sectionID: "files", windowsSectionID: "search", title: "在终端中打开", rowTitle: "“在终端中打开”使用", keywords: "终端 terminal iterm warp ghostty"),
        SettingsSearchTarget(id: "RevealArchiveAfterCompression", sectionID: "files", windowsSectionID: "search", title: "压缩后显示在访达", rowTitle: "压缩后显示在访达", keywords: "压缩 zip 访达 finder"),
        SettingsSearchTarget(id: "NewFileExtension", sectionID: "files", windowsSectionID: "search", title: "新建文件扩展名", rowTitle: "新建文件默认扩展名", keywords: "新建 文件 扩展名 后缀"),
        SettingsSearchTarget(id: "FileNavigationShowsHiddenFiles", sectionID: "files", windowsSectionID: "search", title: "显示隐藏文件", rowTitle: "显示隐藏文件", keywords: "隐藏 文件 导航"),
        SettingsSearchTarget(id: "FileNavigationSort", sectionID: "files", windowsSectionID: "search", title: "文件排序方式", rowTitle: "排序", keywords: "名称 日期 修改时间 创建时间 排序"),
        SettingsSearchTarget(id: "FileNavigationSortAscending", sectionID: "files", windowsSectionID: "search", title: "文件升序排列", rowTitle: "升序排列", keywords: "升序 降序 排列"),
        SettingsSearchTarget(id: "FileNavigationFoldersFirst", sectionID: "files", windowsSectionID: "search", title: "文件夹优先", rowTitle: "文件夹优先", keywords: "文件夹 优先 排序"),
        SettingsSearchTarget(id: "PreviewDocuments", sectionID: "files", windowsSectionID: "search", title: "预览 PDF 与 Office 文档", rowTitle: "预览 PDF 与 Office 文档", keywords: "预览 pdf word excel ppt office quick look"),
        SettingsSearchTarget(id: "TextTransformKeyword", sectionID: "tools", windowsSectionID: "search", title: "文本转换", rowTitle: "", keywords: "tx 转换 大小写 json base64 url 编码 哈希 md5 sha"),
        SettingsSearchTarget(id: "TimestampUnit", sectionID: "tools", windowsSectionID: "search", title: "时间戳单位", rowTitle: "时间戳单位", keywords: "时间戳 秒 毫秒 unix timestamp"),
        SettingsSearchTarget(id: "WorldClockZones", sectionID: "tools", windowsSectionID: "search", title: "世界时间城市", rowTitle: "", keywords: "时区 城市 世界时间 time zone"),
        SettingsSearchTarget(id: "NumberBaseConversion", sectionID: "tools", windowsSectionID: "search", title: "进制转换", rowTitle: "进制转换", keywords: "进制 十六进制 二进制 hex binary"),
        SettingsSearchTarget(id: "PercentExpressions", sectionID: "tools", windowsSectionID: "search", title: "百分比写法", rowTitle: "百分比写法", keywords: "百分比 percent 计算器"),
        SettingsSearchTarget(id: "PasswordLength", sectionID: "tools", windowsSectionID: "search", title: "密码长度", rowTitle: "密码长度", keywords: "密码 生成 长度 password"),
        SettingsSearchTarget(id: "PasswordIncludesSymbols", sectionID: "tools", windowsSectionID: "search", title: "密码包含符号", rowTitle: "密码包含符号", keywords: "密码 符号 password"),
        SettingsSearchTarget(id: "UUIDUppercase", sectionID: "tools", windowsSectionID: "search", title: "UUID 使用大写", rowTitle: "UUID 使用大写", keywords: "uuid 大写 生成"),
        SettingsSearchTarget(id: "EmojiSkinTone", sectionID: "tools", windowsSectionID: "search", title: "Emoji 默认肤色", rowTitle: "默认肤色", keywords: "emoji 表情 肤色"),
        SettingsSearchTarget(id: "EmojiPastesDirectly", sectionID: "tools", windowsSectionID: "search", title: "Emoji 直接粘贴", rowTitle: "选中后直接粘贴", keywords: "emoji 表情 符号 粘贴"),
        SettingsSearchTarget(id: "SystemCommandKeywords", sectionID: "system", windowsSectionID: "search", title: "系统命令关键词", rowTitle: "", keywords: "系统 命令 关键词 锁屏 音量 静音 推出 睡眠 重启 关机"),
        SettingsSearchTarget(id: "ConfirmPowerActions", sectionID: "system", windowsSectionID: "search", title: "睡眠、重启、关机前确认", rowTitle: "睡眠、重启、关机前确认", keywords: "睡眠 重启 关机 确认 电源"),
        SettingsSearchTarget(id: "ClipboardEnabled", sectionID: "clipboard", windowsSectionID: "clipboard", title: "记录剪贴板历史", rowTitle: "记录剪贴板历史", keywords: "启用 记录 剪贴板 历史"),
        SettingsSearchTarget(id: "ClipboardPaused", sectionID: "clipboard", windowsSectionID: "clipboard", title: "暂停剪贴板记录", rowTitle: "暂停记录", keywords: "暂停 保留 历史"),
        SettingsSearchTarget(id: "ClipboardRetentionDays", sectionID: "clipboard", windowsSectionID: "clipboard", title: "保留天数", rowTitle: "保留时间", keywords: "历史 保留 天数 时间 过期"),
        SettingsSearchTarget(id: "ClipboardMaximumItems", sectionID: "clipboard", windowsSectionID: "clipboard", title: "最多记录条数", rowTitle: "最多记录", keywords: "历史 最大 条数 规模"),
        SettingsSearchTarget(id: "ClipboardMaximumTextCharacters", sectionID: "clipboard", windowsSectionID: "clipboard", title: "文本长度上限", rowTitle: "文本长度上限", keywords: "文本 长度 字符 上限"),
        SettingsSearchTarget(id: "ClipboardStoreImages", sectionID: "clipboard", windowsSectionID: "clipboard", title: "记录剪贴板图片", rowTitle: "记录图片", keywords: "图片 保存 历史"),
        SettingsSearchTarget(id: "PasteToFrontApplication", sectionID: "clipboard", windowsSectionID: "clipboard", title: "直接粘贴到前台应用", rowTitle: "选中后直接粘贴到前台应用", keywords: "粘贴 自动 前台 辅助功能"),
        SettingsSearchTarget(id: "SequentialPaste", sectionID: "clipboard", windowsSectionID: "clipboard", title: "连续粘贴", rowTitle: "", keywords: "连续 依次 队列 多选"),
        SettingsSearchTarget(id: "ClipboardIgnoredApplications", sectionID: "clipboard", windowsSectionID: "clipboard", title: "忽略的应用 / 进程", rowTitle: "", keywords: "忽略 应用 进程 密码管理器"),
        SettingsSearchTarget(id: "ClipboardIgnoreRules", sectionID: "clipboard", windowsSectionID: "clipboard", title: "忽略内容规则", rowTitle: "", keywords: "忽略 正则 规则 过滤 regex"),
        SettingsSearchTarget(id: "SensitiveAutoDelete", sectionID: "clipboard", windowsSectionID: "clipboard", title: "疑似敏感内容自动删除", rowTitle: "", keywords: "敏感 验证码 令牌 token 自动删除"),
        SettingsSearchTarget(id: "ClipboardCloudSyncEnabled", sectionID: "sync", windowsSectionID: "clipboard", title: "启用坚果云同步", rowTitle: "", keywords: "同步 坚果云 webdav 云端 sync jianguoyun"),
        SettingsSearchTarget(id: "CloudUsername", sectionID: "sync", windowsSectionID: "clipboard", title: "坚果云用户名", rowTitle: "坚果云用户名", keywords: "坚果云 webdav 账号 用户名"),
        SettingsSearchTarget(id: "CloudAppPassword", sectionID: "sync", windowsSectionID: "clipboard", title: "坚果云应用密码", rowTitle: "应用密码", keywords: "坚果云 webdav 应用密码 认证 密码"),
        SettingsSearchTarget(id: "CloudPassphrase", sectionID: "sync", windowsSectionID: "clipboard", title: "同步口令", rowTitle: "同步口令", keywords: "坚果云 webdav 同步口令 passphrase 加密 密钥 密码"),
        SettingsSearchTarget(id: "ClipboardCloudSyncFolder", sectionID: "sync", windowsSectionID: "clipboard", title: "坚果云远端目录", rowTitle: "远端目录", keywords: "同步 webdav 远端 目录 路径"),
        SettingsSearchTarget(id: "ClipboardCloudSyncIntervalMinutes", sectionID: "sync", windowsSectionID: "clipboard", title: "后台拉取间隔", rowTitle: "拉取间隔", keywords: "同步 拉取 间隔 时间"),
        SettingsSearchTarget(id: "AccessibilityPermission", sectionID: "permissions", windowsSectionID: "general", title: "辅助功能权限", rowTitle: "辅助功能", keywords: "权限 辅助功能 粘贴 accessibility"),
        SettingsSearchTarget(id: "ScreenRecordingPermission", sectionID: "permissions", windowsSectionID: "general", title: "屏幕录制权限", rowTitle: "屏幕录制", keywords: "权限 屏幕录制 截图 ocr"),
        SettingsSearchTarget(id: "FinderAutomationPermission", sectionID: "permissions", windowsSectionID: "general", title: "自动化 · 访达", rowTitle: "自动化 · 访达", keywords: "权限 自动化 访达 finder 废纸篓"),
        SettingsSearchTarget(id: "PowerAutomationPermission", sectionID: "permissions", windowsSectionID: "general", title: "自动化 · 登录窗口", rowTitle: "自动化 · 登录窗口", keywords: "权限 自动化 睡眠 重启 关机"),
        SettingsSearchTarget(id: "LocalDiagnostics", sectionID: "privacy", windowsSectionID: "general", title: "复制本机诊断", rowTitle: "复制本机诊断", keywords: "诊断 版本 日志 反馈"),
        SettingsSearchTarget(id: "ClearUsageLearning", sectionID: "privacy", windowsSectionID: "general", title: "清除使用学习", rowTitle: "清除使用学习", keywords: "清除 学习 排序 哈希"),
        SettingsSearchTarget(id: "ClearRecentDocuments", sectionID: "privacy", windowsSectionID: "general", title: "清除最近文档", rowTitle: "清除最近文档", keywords: "清除 最近 文档 记录"),
        SettingsSearchTarget(id: "RestoreDefaults", sectionID: "privacy", windowsSectionID: "general", title: "恢复默认设置", rowTitle: "恢复默认设置", keywords: "恢复 默认 重置 reset"),
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
