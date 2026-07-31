using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;
using YTools.Models;

namespace YTools.UI;

/// <summary>
/// Applies the light/dark theme and accent palette as dynamic resources.
/// System mode follows the Windows AppsUseLightTheme registry value and live
/// user preference changes.
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

    public static void Apply(AppPreferences preferences)
    {
        CurrentPreferences = preferences;
        var dark = preferences.Theme switch
        {
            AppTheme.Dark => true,
            AppTheme.Light => false,
            _ => IsSystemDark()
        };
        var resources = Application.Current.Resources;

        var panelColor = dark
            ? Color.FromArgb(242, 34, 34, 38)
            : Color.FromArgb(246, 248, 248, 250);
        var glassColor = dark
            ? Color.FromArgb(205, 44, 44, 50)
            : Color.FromArgb(190, 252, 252, 254);
        var classicColor = dark
            ? Color.FromArgb(250, 28, 28, 32)
            : Color.FromArgb(252, 252, 253, 255);
        var isGlass = preferences.LauncherAppearanceStyle == LauncherAppearanceStyle.Glass;
        var isClassic = preferences.LauncherAppearanceStyle == LauncherAppearanceStyle.Classic;
        var background = isGlass ? glassColor : isClassic ? classicColor : panelColor;

        var textPrimary = dark ? Color.FromRgb(240, 240, 244) : Color.FromRgb(28, 28, 32);
        var textSecondary = dark ? Color.FromRgb(168, 168, 178) : Color.FromRgb(100, 100, 112);
        var border = dark ? Color.FromArgb(70, 255, 255, 255) : Color.FromArgb(45, 0, 0, 0);
        var accent = AccentColor(preferences.AccentColor);
        var selection = Color.FromArgb(
            (byte)(DesignTokens.SelectionOpacity(preferences.LauncherAppearanceStyle) * 255),
            accent.R,
            accent.G,
            accent.B);
        var selectionText = dark ? Colors.White : Colors.Black;

        resources["PanelBackgroundBrush"] = new SolidColorBrush(background);
        resources["TextPrimaryBrush"] = new SolidColorBrush(textPrimary);
        resources["TextSecondaryBrush"] = new SolidColorBrush(textSecondary);
        resources["BorderBrush"] = new SolidColorBrush(border);
        resources["AccentBrush"] = new SolidColorBrush(accent);
        resources["SelectionBrush"] = new SolidColorBrush(selection);
        resources["SelectionTextBrush"] = new SolidColorBrush(selectionText);
        resources["InputBackgroundBrush"] = new SolidColorBrush(
            dark ? Color.FromArgb(60, 255, 255, 255) : Color.FromArgb(30, 0, 0, 0));
        resources["HoverBrush"] = new SolidColorBrush(
            dark ? Color.FromArgb(30, 255, 255, 255) : Color.FromArgb(22, 0, 0, 0));
        resources["WindowBackgroundBrush"] = new SolidColorBrush(
            dark ? Color.FromRgb(32, 32, 36) : Color.FromRgb(250, 250, 252));
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

    private static Color AccentColor(AppAccentColor accent)
    {
        return accent switch
        {
            AppAccentColor.Blue => Color.FromRgb(0, 120, 212),
            AppAccentColor.Purple => Color.FromRgb(140, 90, 220),
            AppAccentColor.Green => Color.FromRgb(16, 140, 90),
            AppAccentColor.Orange => Color.FromRgb(220, 120, 20),
            _ => Color.FromRgb(0, 120, 212)
        };
    }
}
