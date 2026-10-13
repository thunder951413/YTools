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
                && (string.Equals(value, QuotedExecutablePath(), StringComparison.OrdinalIgnoreCase)
                    || string.Equals(value, ExecutablePath(), StringComparison.OrdinalIgnoreCase));
        }
    }

    public static void SetEnabled(bool enabled)
    {
        var executablePath = Environment.ProcessPath;
        if (enabled && string.IsNullOrEmpty(executablePath))
        {
            // A relative "YTools.exe" would resolve against the system working
            // directory at logon and silently never start; surface it instead.
            throw new InvalidOperationException("无法确定 YTools 可执行文件的完整路径。");
        }

        using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath);
        if (enabled)
        {
            // Quote the path: an unquoted Run value containing spaces is resolved
            // by trying each space-separated prefix as an executable.
            key.SetValue(ValueName, Quote(executablePath!), RegistryValueKind.String);
        }
        else
        {
            key.DeleteValue(ValueName, throwOnMissingValue: false);
        }
    }

    private static string ExecutablePath()
    {
        return Environment.ProcessPath ?? "YTools.exe";
    }

    private static string QuotedExecutablePath() => Quote(ExecutablePath());

    private static string Quote(string path) => $"\"{path.Trim('"')}\"";
}
