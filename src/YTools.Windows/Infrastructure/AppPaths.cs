using System.IO;
using System.Security.AccessControl;
using System.Security.Principal;

namespace YTools.Infrastructure;

/// <summary>
/// Owns the per-user data directory. All YTools data stays under
/// %APPDATA%\YTools and is ACL-restricted to the current user.
/// </summary>
public static class AppPaths
{
    public static string RootDirectory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "YTools");

    public static string VaultDirectory { get; } = Path.Combine(RootDirectory, "vault");

    public static string SettingsFile { get; } = Path.Combine(RootDirectory, "settings.json");

    public static string UsageRankingFile { get; } = Path.Combine(RootDirectory, "usage-ranking.json");

    public static string KeyFile { get; } = Path.Combine(RootDirectory, "secure-key.bin");

    public static void EnsureDirectories()
    {
        Directory.CreateDirectory(RootDirectory);
        Directory.CreateDirectory(VaultDirectory);
        RestrictDirectory(RootDirectory);
    }

    public static void RestrictFile(string path)
    {
        if (!File.Exists(path))
        {
            return;
        }

        try
        {
            var fileInfo = new FileInfo(path);
            var security = fileInfo.GetAccessControl();
            var identity = WindowsIdentity.GetCurrent().User;
            if (identity is null)
            {
                return;
            }

            security.SetAccessRuleProtection(true, false);
            security.AddAccessRule(new FileSystemAccessRule(
                identity,
                FileSystemRights.FullControl,
                InheritanceFlags.None,
                PropagationFlags.None,
                AccessControlType.Allow));
            fileInfo.SetAccessControl(security);
        }
        catch
        {
            // ACL hardening is best-effort; encryption remains the data boundary.
        }
    }

    public static void LogException(Exception exception)
    {
        try
        {
            EnsureDirectories();
            File.AppendAllText(
                Path.Combine(RootDirectory, "error.log"),
                $"[{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss}] {exception}\n\n");
        }
        catch
        {
            // Logging must never mask the original failure.
        }
    }

    private static void RestrictDirectory(string path)
    {
        try
        {
            var directoryInfo = new DirectoryInfo(path);
            var security = directoryInfo.GetAccessControl();
            var identity = WindowsIdentity.GetCurrent().User;
            if (identity is null)
            {
                return;
            }

            security.SetAccessRuleProtection(true, false);
            security.AddAccessRule(new FileSystemAccessRule(
                identity,
                FileSystemRights.FullControl,
                InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                PropagationFlags.None,
                AccessControlType.Allow));
            directoryInfo.SetAccessControl(security);
        }
        catch
        {
            // Best-effort; encryption remains the data boundary.
        }
    }
}
