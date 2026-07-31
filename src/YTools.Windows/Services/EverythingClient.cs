using System.Runtime.InteropServices;
using System.Text;
using System.IO;

namespace YTools.Services;

/// <summary>
/// Thin, read-only client for the Everything SDK (Everything64.dll) loaded from
/// a local Everything installation. If Everything is not installed, the caller
/// falls back to the built-in file scanner. No network is involved.
/// </summary>
public sealed class EverythingClient : IDisposable
{
    private const uint EverythingRequestFullPathAndFileName = 0x00000004;
    private const uint EverythingErrorOk = 0;
    private const uint EverythingErrorIpc = 2;
    private readonly object _lock = new();
    private readonly IntPtr _module;
    private bool _disposed;

    private EverythingClient(IntPtr module)
    {
        _module = module;
    }

    public bool IsAvailable => _module != IntPtr.Zero;

    public static EverythingClient? TryCreate()
    {
        var candidates = new List<string>();
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
        if (!string.IsNullOrEmpty(localAppData))
        {
            candidates.Add(Path.Combine(localAppData, "Everything", "Everything64.dll"));
        }

        if (!string.IsNullOrEmpty(programFiles))
        {
            candidates.Add(Path.Combine(programFiles, "Everything", "Everything64.dll"));
        }

        if (!string.IsNullOrEmpty(programFilesX86))
        {
            candidates.Add(Path.Combine(programFilesX86, "Everything", "Everything64.dll"));
        }

        foreach (var candidate in candidates.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (!File.Exists(candidate))
            {
                continue;
            }

            var module = LoadLibrary(candidate);
            if (module != IntPtr.Zero)
            {
                return new EverythingClient(module);
            }
        }

        return null;
    }

    public bool Query(string search, int limit, out List<string> paths)
    {
        paths = [];
        lock (_lock)
        {
            if (!IsAvailable || _disposed)
            {
                return false;
            }

            Everything_SetSearchW(search);
            Everything_SetMatchPathEnabled(false);
            Everything_SetRequestFlags(EverythingRequestFullPathAndFileName);
            if (!Everything_QueryW(true))
            {
                return false;
            }

            var count = Math.Min((int)Everything_GetNumResults(), Math.Max(1, Math.Min(limit, 100)));
            var buffer = new StringBuilder(32_768);
            for (var index = 0; index < count; index++)
            {
                Everything_GetResultFullPathNameW((uint)index, buffer, buffer.Capacity);
                if (buffer.Length > 0)
                {
                    paths.Add(buffer.ToString());
                    buffer.Clear();
                }
            }

            return true;
        }
    }

    public uint LastError()
    {
        lock (_lock)
        {
            return _disposed ? EverythingErrorIpc : Everything_GetLastError();
        }
    }

    public void Dispose()
    {
        lock (_lock)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            if (_module != IntPtr.Zero)
            {
                FreeLibrary(_module);
            }
        }
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadLibrary(string lpFileName);

    [DllImport("kernel32.dll")]
    private static extern bool FreeLibrary(IntPtr hModule);

    [DllImport("Everything64.dll", CharSet = CharSet.Unicode)]
    private static extern void Everything_SetSearchW(string searchString);

    [DllImport("Everything64.dll")]
    private static extern void Everything_SetMatchPathEnabled(bool enabled);

    [DllImport("Everything64.dll")]
    private static extern void Everything_SetRequestFlags(uint flags);

    [DllImport("Everything64.dll")]
    private static extern bool Everything_QueryW(bool bWait);

    [DllImport("Everything64.dll")]
    private static extern uint Everything_GetNumResults();

    [DllImport("Everything64.dll", CharSet = CharSet.Unicode)]
    private static extern void Everything_GetResultFullPathNameW(uint index, StringBuilder buffer, int bufferLength);

    [DllImport("Everything64.dll")]
    private static extern uint Everything_GetLastError();
}
