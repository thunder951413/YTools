namespace YTools.Models;

public enum AppTheme
{
    System,
    Light,
    Dark
}

public enum AppAccentColor
{
    Blue,
    Purple,
    Green,
    Orange
}

public enum LauncherAppearanceStyle
{
    Minimal,
    Classic,
    Modern,
    Glass
}

public enum PanelPosition
{
    Upper,
    Center
}

public enum ScreenPreference
{
    Main,
    Mouse
}

public enum FileNavigationSort
{
    Name,
    Created,
    Modified
}

public enum SearchContentType
{
    Applications,
    Files,
    Calculations,
    Dictionary,
    SystemTools,
    Snippets,
    RecentDocuments,
    TextTools
}

public enum SystemCommandID
{
    EmptyTrash,
    ShowTrash,
    ScreenSaver,
    SleepDisplays,
    FocusSettings,
    AppearanceSettings
}

public enum PanelMode
{
    Launcher,
    Clipboard
}

public static class EnumMetadata
{
    public static string Title(this AppTheme theme)
    {
        return theme switch
        {
            AppTheme.System => "跟随系统",
            AppTheme.Light => "浅色",
            AppTheme.Dark => "深色",
            _ => ""
        };
    }

    public static string Title(this AppAccentColor color)
    {
        return color switch
        {
            AppAccentColor.Blue => "蓝色",
            AppAccentColor.Purple => "紫色",
            AppAccentColor.Green => "绿色",
            AppAccentColor.Orange => "橙色",
            _ => ""
        };
    }

    public static string Title(this LauncherAppearanceStyle style)
    {
        return style switch
        {
            LauncherAppearanceStyle.Minimal => "极简",
            LauncherAppearanceStyle.Classic => "经典",
            LauncherAppearanceStyle.Modern => "现代",
            LauncherAppearanceStyle.Glass => "玻璃",
            _ => ""
        };
    }

    public static string Detail(this LauncherAppearanceStyle style)
    {
        return style switch
        {
            LauncherAppearanceStyle.Minimal => "默认；空闲时只显示输入框",
            LauncherAppearanceStyle.Classic => "更实的背景与传统结果列表",
            LauncherAppearanceStyle.Modern => "完整状态提示和操作栏",
            LauncherAppearanceStyle.Glass => "更轻的半透明背景",
            _ => ""
        };
    }

    public static string Title(this PanelPosition position)
    {
        return position == PanelPosition.Upper ? "屏幕上方" : "屏幕中央";
    }

    public static string Title(this ScreenPreference preference)
    {
        return preference == ScreenPreference.Main ? "主显示器" : "鼠标所在显示器";
    }

    public static string Title(this FileNavigationSort sort)
    {
        return sort switch
        {
            FileNavigationSort.Name => "名称",
            FileNavigationSort.Created => "创建时间",
            FileNavigationSort.Modified => "修改时间",
            _ => ""
        };
    }

    public static string Title(this SearchContentType type)
    {
        return type switch
        {
            SearchContentType.Applications => "应用程序",
            SearchContentType.Files => "本地文件",
            SearchContentType.Calculations => "计算与单位换算",
            SearchContentType.Dictionary => "词典与拼写",
            SearchContentType.SystemTools => "系统工具与设置",
            SearchContentType.Snippets => "文本片段",
            SearchContentType.RecentDocuments => "最近文档",
            SearchContentType.TextTools => "文本统计工具",
            _ => ""
        };
    }

    public static string Detail(this SearchContentType type)
    {
        return type switch
        {
            SearchContentType.Applications => "扫描开始菜单与 WindowsApps 中的可启动应用",
            SearchContentType.Files => "Everything/文件名文件搜索以及 /、~ 目录导航",
            SearchContentType.Calculations => "表达式计算、常量、函数和单位转换",
            SearchContentType.Dictionary => "离线词典释义、拼写检查和建议",
            SearchContentType.SystemTools => "可配置系统命令、回收站、屏保、显示器休眠和系统设置入口",
            SearchContentType.Snippets => "搜索保存在本机的文本片段",
            SearchContentType.RecentDocuments => "搜索由 YTools 记录的最近打开项目",
            SearchContentType.TextTools => "统计剪贴板文字的字数、行数等信息",
            _ => ""
        };
    }

    public static string Title(this SystemCommandID id)
    {
        return id switch
        {
            SystemCommandID.EmptyTrash => "清空回收站",
            SystemCommandID.ShowTrash => "显示回收站",
            SystemCommandID.ScreenSaver => "启动屏幕保护程序",
            SystemCommandID.SleepDisplays => "关闭显示器",
            SystemCommandID.FocusSettings => "打开专注模式设置",
            SystemCommandID.AppearanceSettings => "打开系统外观设置",
            _ => ""
        };
    }

    public static string Detail(this SystemCommandID id)
    {
        return id switch
        {
            SystemCommandID.EmptyTrash => "由系统清空回收站；执行前始终确认",
            SystemCommandID.ShowTrash => "打开回收站窗口",
            SystemCommandID.ScreenSaver => "立即启动 Windows 屏幕保护程序",
            SystemCommandID.SleepDisplays => "让显示器立即睡眠，不退出应用",
            SystemCommandID.FocusSettings => "打开 Windows 专注模式设置；不模拟点击",
            SystemCommandID.AppearanceSettings => "打开 Windows 个性化设置；不使用私有接口切换",
            _ => ""
        };
    }

    public static string DefaultKeyword(this SystemCommandID id)
    {
        return id switch
        {
            SystemCommandID.EmptyTrash => "empty",
            SystemCommandID.ShowTrash => "trash",
            SystemCommandID.ScreenSaver => "screensaver",
            SystemCommandID.SleepDisplays => "sleepdisplays",
            SystemCommandID.FocusSettings => "dnd",
            SystemCommandID.AppearanceSettings => "theme",
            _ => ""
        };
    }
}

public sealed record SystemCommandConfiguration(
    IReadOnlySet<SystemCommandID> Enabled,
    IReadOnlyDictionary<SystemCommandID, string> Keywords);
