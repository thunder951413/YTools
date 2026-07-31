using Microsoft.Win32;

namespace YTools.Services;

/// <summary>
/// Windows equivalent of ServiceManagement: a per-user Run key. The value is
/// fixed to this executable's path; no user input ever becomes a command.
/// </summary>
public static class LaunchAtLoginService
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "YTools";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath);
            return key?.GetValue(ValueName) is string value
                && string.Equals(value, ExecutablePath(), StringComparison.OrdinalIgnoreCase);
        }
    }

    public static void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath);
        if (enabled)
        {
            key.SetValue(ValueName, ExecutablePath(), RegistryValueKind.String);
        }
        else
        {
            key.DeleteValue(ValueName, throwOnMissingValue: false);
        }
    }

    private static string ExecutablePath()
    {
        var path = Environment.ProcessPath;
        return string.IsNullOrEmpty(path) ? "YTools.exe" : path;
    }
}
