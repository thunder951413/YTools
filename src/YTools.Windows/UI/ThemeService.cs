using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;
using YTools.Models;

namespace YTools.UI;

/// <summary>
/// Applies dedicated light and dark color palettes as dynamic resources.
/// System mode follows the Windows AppsUseLightTheme registry value; theme,
/// accent and launcher-style changes re-apply live.
/// </summary>
public static class ThemeService
{
    private static bool _subscribed;

    public static void Subscribe()
    {
        if (_subscribed)
        {
            return;
        }

        _subscribed = true;
        SystemEvents.UserPreferenceChanged += (_, _) =>
        {
            Application.Current.Dispatcher.Invoke(() =>
            {
                if (CurrentPreferences?.Theme == AppTheme.System)
                {
                    Apply(CurrentPreferences);
                }
            });
        };
    }

    public static AppPreferences? CurrentPreferences { get; private set; }

    public static bool IsDarkEffective(AppPreferences preferences)
    {
        return preferences.Theme switch
        {
            AppTheme.Dark => true,
            AppTheme.Light => false,
            _ => IsSystemDark()
        };
    }

    public static void Apply(AppPreferences preferences)
    {
        CurrentPreferences = preferences;
        var dark = IsDarkEffective(preferences);
        var palette = dark ? DarkPalette : LightPalette;
        var resources = Application.Current.Resources;
        var style = preferences.LauncherAppearanceStyle;

        var accent = palette.AccentFor(preferences.AccentColor);
        var selectionAlpha = (byte)(DesignTokens.SelectionOpacity(style) * 255);

        resources["WindowBackgroundBrush"] = Brush(palette.WindowBackground);
        resources["PanelBackgroundBrush"] = Brush(panelForStyle(palette, style));
        resources["InputBackgroundBrush"] = Brush(palette.InputBackground);
        resources["HoverBrush"] = Brush(palette.Hover);
        resources["BorderBrush"] = Brush(palette.Border);
        resources["TextPrimaryBrush"] = Brush(palette.TextPrimary);
        resources["TextSecondaryBrush"] = Brush(palette.TextSecondary);
        resources["AccentBrush"] = Brush(accent);
        resources["SelectionBrush"] = Brush(Color.FromArgb(selectionAlpha, accent.R, accent.G, accent.B));
        resources["SelectionTextBrush"] = Brush(dark ? Colors.White : palette.TextPrimary);
    }

    public static bool IsSystemDark()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            var value = key?.GetValue("AppsUseLightTheme");
            return value is int light && light == 0;
        }
        catch
        {
            return false;
        }
    }

    private static Color panelForStyle(Palette palette, LauncherAppearanceStyle style)
    {
        var baseColor = palette.PanelBackground;
        return style switch
        {
            LauncherAppearanceStyle.Classic => Color.FromArgb(255, baseColor.R, baseColor.G, baseColor.B),
            LauncherAppearanceStyle.Glass => Color.FromArgb(
                (byte)(darkGlassAlpha(baseColor)),
                baseColor.R,
                baseColor.G,
                baseColor.B),
            _ => Color.FromArgb(245, baseColor.R, baseColor.G, baseColor.B)
        };
    }

    private static int darkGlassAlpha(Color baseColor)
    {
        return baseColor.A == 255 ? 232 : 218;
    }

    private static SolidColorBrush Brush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private sealed record Palette(
        Color WindowBackground,
        Color PanelBackground,
        Color InputBackground,
        Color Hover,
        Color Border,
        Color TextPrimary,
        Color TextSecondary,
        Color AccentBlue,
        Color AccentPurple,
        Color AccentGreen,
        Color AccentOrange)
    {
        public Color AccentFor(AppAccentColor accent)
        {
            return accent switch
            {
                AppAccentColor.Blue => AccentBlue,
                AppAccentColor.Purple => AccentPurple,
                AppAccentColor.Green => AccentGreen,
                AppAccentColor.Orange => AccentOrange,
                _ => AccentBlue
            };
        }
    }

    private static readonly Palette LightPalette = new(
        WindowBackground: Rgb(0xF6, 0xF6, 0xF8),
        PanelBackground: Rgb(0xFE, 0xFE, 0xFF),
        InputBackground: Rgb(0xEC, 0xEC, 0xF0),
        Hover: Color.FromArgb(0x0D, 0x00, 0x00, 0x00),
        Border: Color.FromArgb(0x1E, 0x00, 0x00, 0x00),
        TextPrimary: Rgb(0x1A, 0x1A, 0x1E),
        TextSecondary: Rgb(0x6B, 0x6B, 0x76),
        AccentBlue: Rgb(0x0B, 0x67, 0xC6),
        AccentPurple: Rgb(0x7A, 0x4F, 0xCE),
        AccentGreen: Rgb(0x0E, 0x8A, 0x5D),
        AccentOrange: Rgb(0xD9, 0x6E, 0x0B));

    private static readonly Palette DarkPalette = new(
        WindowBackground: Rgb(0x1E, 0x1E, 0x22),
        PanelBackground: Rgb(0x2B, 0x2B, 0x31),
        InputBackground: Rgb(0x38, 0x38, 0x3F),
        Hover: Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF),
        Border: Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF),
        TextPrimary: Rgb(0xF1, 0xF1, 0xF4),
        TextSecondary: Rgb(0x9E, 0x9E, 0xA9),
        AccentBlue: Rgb(0x4D, 0x9F, 0xFF),
        AccentPurple: Rgb(0xB1, 0x8C, 0xFF),
        AccentGreen: Rgb(0x3C, 0xCF, 0x9B),
        AccentOrange: Rgb(0xFF, 0x9E, 0x4A));

    private static Color Rgb(byte r, byte g, byte b)
    {
        return Color.FromRgb(r, g, b);
    }
}
