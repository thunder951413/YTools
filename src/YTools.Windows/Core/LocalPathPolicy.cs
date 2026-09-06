using System.IO;

namespace YTools.Core;

/// <summary>Validates paths before they cross into native file or process APIs.</summary>
public static class LocalPathPolicy
{
    public static bool IsValid(string? path)
    {
        return TryNormalize(path, out _);
    }

    public static bool TryNormalize(string? path, out string normalized)
    {
        normalized = "";
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }

        var candidate = path.Trim();
        if (candidate.Length < 3
            || !char.IsAsciiLetter(candidate[0])
            || candidate[1] != ':'
            || (candidate[2] != '\\' && candidate[2] != '/')
            || candidate.StartsWith("\\\\", StringComparison.Ordinal)
            || candidate.StartsWith("//", StringComparison.Ordinal)
            || candidate.IndexOf(':', 2) >= 0
            || candidate.Contains('\0'))
        {
            return false;
        }

        try
        {
            if (OperatingSystem.IsWindows() && !Path.IsPathFullyQualified(candidate))
            {
                return false;
            }

            normalized = OperatingSystem.IsWindows()
                ? Path.GetFullPath(candidate)
                : candidate.Replace('/', '\\');
            return normalized.Length >= 3
                && char.IsAsciiLetter(normalized[0])
                && normalized[1] == ':'
                && normalized[2] == '\\';
        }
        catch
        {
            normalized = "";
            return false;
        }
    }
}
