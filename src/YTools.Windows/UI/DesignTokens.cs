using YTools.Models;

namespace YTools.UI;

public static class DesignTokens
{
    public const double DefaultPanelWidth = 720;
    public const double PanelMaximumHeight = 500;
    public const double PanelMinimumHeight = 196;
    public const double HeaderHeight = 72;
    public const double FooterHeight = 34;
    public const double EmptyBodyHeight = 150;
    public const double ComfortableRowHeight = 60;
    public const double CompactRowHeight = 52;
    public const double ResultCornerRadius = 9;
    public const double ResultIconSize = 34;
    public const double HorizontalPadding = 18;

    public static double HeaderHeightFor(LauncherAppearanceStyle style)
    {
        return style switch
        {
            LauncherAppearanceStyle.Minimal => 40,
            LauncherAppearanceStyle.Classic => 60,
            LauncherAppearanceStyle.Modern => 68,
            LauncherAppearanceStyle.Glass => 64,
            _ => 64
        };
    }

    public static double SearchFontSizeFor(LauncherAppearanceStyle style)
    {
        return style switch
        {
            LauncherAppearanceStyle.Minimal => 18,
            LauncherAppearanceStyle.Classic => 22,
            _ => 23
        };
    }

    public static bool ShowsFooter(LauncherAppearanceStyle style)
    {
        return style == LauncherAppearanceStyle.Modern;
    }

    public static bool CollapsesWhenIdle(LauncherAppearanceStyle style)
    {
        return style != LauncherAppearanceStyle.Modern;
    }

    public static double EmptyBodyHeightFor(LauncherAppearanceStyle style)
    {
        return style switch
        {
            LauncherAppearanceStyle.Minimal or LauncherAppearanceStyle.Glass => 78,
            LauncherAppearanceStyle.Classic => 96,
            _ => EmptyBodyHeight
        };
    }

    public static double SelectionOpacity(LauncherAppearanceStyle style)
    {
        return style switch
        {
            LauncherAppearanceStyle.Minimal => 0.12,
            LauncherAppearanceStyle.Classic => 0.18,
            LauncherAppearanceStyle.Modern => 0.16,
            LauncherAppearanceStyle.Glass => 0.20,
            _ => 0.16
        };
    }
}
