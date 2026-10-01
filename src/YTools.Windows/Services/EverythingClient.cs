using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace YTools.Services;

public enum EverythingAvailabilityStatus
{
    NotRunning = 0,
    Available = 1,
    IntegrityMismatch = 2,
    AccessDenied = 3,
    IpcUnavailable = 4,
    Disposed = 5
}

/// <summary>
/// Read-only client for the local Everything IPC window. It implements the
/// official QUERY2 WM_COPYDATA protocol directly, so a normal Everything
/// installation needs no separately downloaded Everything64.dll.
/// </summary>
public sealed class EverythingClient : IDisposable
{
    private const string EverythingWindowClass = "EVERYTHING_TASKBAR_NOTIFICATION";
    private const int WmCopyData = 0x004A;
    private const uint CopyDataQuery2W = 18;
    private const uint Query2RequestFullPathAndName = 0x00000004;
    private const uint SortNameAscending = 1;
    private const uint ReplyMessageId = 0x59544F4F; // "YTOO"
    private const uint SmtoAbortIfHung = 0x0002;
    private const uint PmRemove = 0x0001;
    private const uint ProcessQueryLimitedInformation = 0x1000;
    private const uint TokenQuery = 0x0008;
    private const int TokenIntegrityLevel = 25;
    private const int ErrorInsufficientBuffer = 122;
    private static readonly TimeSpan QueryTimeout = TimeSpan.FromMilliseconds(800);
    private readonly object _lock = new();
    private bool _disposed;
    private uint _lastError;
    private EverythingAvailabilityStatus _availabilityStatus = EverythingAvailabilityStatus.NotRunning;
    private uint _everythingProcessId;

    private EverythingClient()
    {
    }

    public bool IsAvailable => AvailabilityStatus == EverythingAvailabilityStatus.Available;

    public EverythingAvailabilityStatus AvailabilityStatus
    {
        get
        {
            lock (_lock)
            {
                return RefreshAvailabilityUnsafe();
            }
        }
    }

    public uint EverythingProcessId
    {
        get
        {
            lock (_lock)
            {
                _ = RefreshAvailabilityUnsafe();
                return _everythingProcessId;
            }
        }
    }

    public static EverythingClient? TryCreate()
    {
        return FindWindow(EverythingWindowClass, null) == IntPtr.Zero
            ? null
            : new EverythingClient();
    }

    public bool Query(string search, int limit, out List<string> paths)
    {
        return Query(search, limit, CancellationToken.None, out paths);
    }

    public bool Query(
        string search,
        int limit,
        CancellationToken cancellationToken,
        out List<string> paths)
    {
        paths = [];
        lock (_lock)
        {
            if (_disposed)
            {
                _availabilityStatus = EverythingAvailabilityStatus.Disposed;
                _lastError = EverythingIpcError.Unavailable;
                return false;
            }

            if (cancellationToken.IsCancellationRequested)
            {
                _lastError = EverythingIpcError.Cancelled;
                return false;
            }

            var everythingWindow = FindWindow(EverythingWindowClass, null);
            if (everythingWindow == IntPtr.Zero)
            {
                _availabilityStatus = EverythingAvailabilityStatus.NotRunning;
                _lastError = EverythingIpcError.Unavailable;
                return false;
            }

            if (RefreshAvailabilityUnsafe() != EverythingAvailabilityStatus.Available)
            {
                _lastError = ErrorForAvailability(_availabilityStatus);
                return false;
            }

            if (cancellationToken.IsCancellationRequested)
            {
                _lastError = EverythingIpcError.Cancelled;
                return false;
            }
            using var replyWindow = new EverythingReplyWindow(
                ReplyMessageId,
                everythingWindow,
                _everythingProcessId);
            var queryBuffer = BuildQueryBuffer(
                replyWindow.Handle,
                search,
                Math.Clamp(limit, 1, 100));
            var queryPointer = Marshal.AllocHGlobal(queryBuffer.Length);
            try
            {
                Marshal.Copy(queryBuffer, 0, queryPointer, queryBuffer.Length);
                var copyData = new CopyDataStruct
                {
                    Data = new UIntPtr(CopyDataQuery2W),
                    Size = (uint)queryBuffer.Length,
                    DataPointer = queryPointer
                };
                var copyDataPointer = Marshal.AllocHGlobal(Marshal.SizeOf<CopyDataStruct>());
                try
                {
                    Marshal.StructureToPtr(copyData, copyDataPointer, fDeleteOld: false);
                    if (cancellationToken.IsCancellationRequested)
                    {
                        _lastError = EverythingIpcError.Cancelled;
                        return false;
                    }

                    if (!SendQuery(
                            everythingWindow,
                            replyWindow.Handle,
                            copyDataPointer,
                            cancellationToken,
                            out var accepted,
                            out var cancelled)
                        || accepted == IntPtr.Zero)
                    {
                        if (cancelled)
                        {
                            _lastError = EverythingIpcError.Cancelled;
                            return false;
                        }

                        _availabilityStatus = EverythingAvailabilityStatus.IpcUnavailable;
                        _lastError = EverythingIpcError.SendFailed;
                        return false;
                    }
                }
                finally
                {
                    Marshal.FreeHGlobal(copyDataPointer);
                }

                var stopwatch = Stopwatch.StartNew();
                while (!replyWindow.IsComplete && stopwatch.Elapsed < QueryTimeout)
                {
                    if (cancellationToken.IsCancellationRequested)
                    {
                        _lastError = EverythingIpcError.Cancelled;
                        return false;
                    }

                    var processedMessage = false;
                    while (PeekMessage(out var message, replyWindow.Handle, 0, 0, PmRemove))
                    {
                        processedMessage = true;
                        _ = TranslateMessage(ref message);
                        _ = DispatchMessage(ref message);
                    }

                    if (!processedMessage)
                    {
                        Thread.Sleep(1);
                    }
                }

                if (!replyWindow.IsComplete)
                {
                    _availabilityStatus = EverythingAvailabilityStatus.IpcUnavailable;
                    _lastError = EverythingIpcError.TimedOut;
                    return false;
                }

                paths = replyWindow.Paths;
                _availabilityStatus = EverythingAvailabilityStatus.Available;
                _lastError = EverythingIpcError.Ok;
                return true;
            }
            finally
            {
                Marshal.FreeHGlobal(queryPointer);
            }
        }
    }

    public bool Query(
        string search,
        int limit,
        out List<string> paths,
        CancellationToken cancellationToken)
    {
        return Query(search, limit, cancellationToken, out paths);
    }

    public uint LastError()
    {
        lock (_lock)
        {
            return _lastError;
        }
    }

    public void Dispose()
    {
        lock (_lock)
        {
            _disposed = true;
        }
    }

    internal static IReadOnlyList<string> ParseResultBuffer(byte[] buffer)
    {
        const int listHeaderSize = 20;
        const int itemSize = 8;
        if (buffer.Length < listHeaderSize)
        {
            return [];
        }

        var count = ReadUInt32(buffer, 4);
        if (count > 100 || count > (buffer.Length - listHeaderSize) / itemSize)
        {
            return [];
        }

        var paths = new List<string>((int)count);
        var minimumDataOffset = listHeaderSize + (int)count * itemSize;
        for (var index = 0; index < count; index++)
        {
            var itemOffset = listHeaderSize + (int)index * itemSize;
            var dataOffset = ReadUInt32(buffer, itemOffset + 4);
            if (dataOffset < minimumDataOffset || dataOffset > buffer.Length - sizeof(uint))
            {
                return [];
            }

            var characterCount = ReadUInt32(buffer, (int)dataOffset);
            var textOffset = checked((int)dataOffset + sizeof(uint));
            var byteCount = checked((long)characterCount * sizeof(char));
            if (characterCount > 32_767 || textOffset + byteCount > buffer.Length)
            {
                return [];
            }

            var path = Encoding.Unicode.GetString(buffer, textOffset, (int)byteCount);
            if (!string.IsNullOrWhiteSpace(path) && Path.IsPathRooted(path))
            {
                paths.Add(path);
            }
        }

        return paths;
    }

    private static byte[] BuildQueryBuffer(IntPtr replyWindow, string search, int limit)
    {
        const int queryHeaderSize = 28;
        var searchBytes = Encoding.Unicode.GetBytes(search + '\0');
        var buffer = new byte[queryHeaderSize + searchBytes.Length];
        WriteUInt32(buffer, 0, unchecked((uint)replyWindow.ToInt64()));
        WriteUInt32(buffer, 4, ReplyMessageId);
        WriteUInt32(buffer, 8, 0); // search flags
        WriteUInt32(buffer, 12, 0); // offset
        WriteUInt32(buffer, 16, (uint)limit);
        WriteUInt32(buffer, 20, Query2RequestFullPathAndName);
        WriteUInt32(buffer, 24, SortNameAscending);
        searchBytes.CopyTo(buffer, queryHeaderSize);
        return buffer;
    }

    private static uint ReadUInt32(byte[] buffer, int offset)
    {
        return BitConverter.ToUInt32(buffer, offset);
    }

    private static void WriteUInt32(byte[] buffer, int offset, uint value)
    {
        BitConverter.GetBytes(value).CopyTo(buffer, offset);
    }

    private sealed class EverythingReplyWindow : System.Windows.Forms.NativeWindow, IDisposable
    {
        private readonly uint _replyMessageId;
        private readonly IntPtr _expectedSenderWindow;
        private readonly uint _expectedSenderProcessId;

        public EverythingReplyWindow(uint replyMessageId, IntPtr expectedSenderWindow, uint expectedSenderProcessId)
        {
            _replyMessageId = replyMessageId;
            _expectedSenderWindow = expectedSenderWindow;
            _expectedSenderProcessId = expectedSenderProcessId;
            CreateHandle(new System.Windows.Forms.CreateParams
            {
                Caption = "YTools Everything IPC",
                Width = 0,
                Height = 0,
                Style = 0
            });
        }

        public bool IsComplete { get; private set; }

        public List<string> Paths { get; private set; } = [];

        protected override void WndProc(ref System.Windows.Forms.Message message)
        {
            if (message.Msg == WmCopyData && message.LParam != IntPtr.Zero)
            {
                var copyData = Marshal.PtrToStructure<CopyDataStruct>(message.LParam);
                var senderProcessId = GetWindowProcessId(message.WParam);
                if (message.WParam == _expectedSenderWindow
                    && senderProcessId == _expectedSenderProcessId
                    && copyData.Data.ToUInt64() == _replyMessageId
                    && copyData.DataPointer != IntPtr.Zero
                    && copyData.Size is > 0 and <= 4_194_304)
                {
                    var buffer = new byte[copyData.Size];
                    Marshal.Copy(copyData.DataPointer, buffer, 0, buffer.Length);
                    Paths = ParseResultBuffer(buffer).ToList();
                    IsComplete = true;
                    message.Result = new IntPtr(1);
                    return;
                }
            }

            base.WndProc(ref message);
        }

        public void Dispose()
        {
            DestroyHandle();
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct CopyDataStruct
    {
        public UIntPtr Data;
        public uint Size;
        public IntPtr DataPointer;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeMessage
    {
        public IntPtr Window;
        public uint Message;
        public UIntPtr WParam;
        public IntPtr LParam;
        public uint Time;
        public System.Drawing.Point Point;
        public uint Private;
    }

    private static class EverythingIpcError
    {
        public const uint Ok = 0;
        public const uint Unavailable = 2;
        public const uint SendFailed = 3;
        public const uint TimedOut = 4;
        public const uint Cancelled = 5;
        public const uint IntegrityMismatch = 6;
        public const uint AccessDenied = 7;
        public const uint IpcUnavailable = 8;
    }

    private EverythingAvailabilityStatus RefreshAvailabilityUnsafe()
    {
        if (_disposed)
        {
            _availabilityStatus = EverythingAvailabilityStatus.Disposed;
            _lastError = EverythingIpcError.Unavailable;
            return _availabilityStatus;
        }

        var everythingWindow = FindWindow(EverythingWindowClass, null);
        if (everythingWindow == IntPtr.Zero)
        {
            _everythingProcessId = 0;
            _availabilityStatus = EverythingAvailabilityStatus.NotRunning;
            _lastError = EverythingIpcError.Unavailable;
            return _availabilityStatus;
        }

        var processId = GetWindowProcessId(everythingWindow);
        if (processId == 0)
        {
            _everythingProcessId = 0;
            _availabilityStatus = EverythingAvailabilityStatus.AccessDenied;
            _lastError = EverythingIpcError.AccessDenied;
            return _availabilityStatus;
        }

        _everythingProcessId = processId;
        if (!TryGetIntegrityLevel((uint)Environment.ProcessId, out var currentIntegrityLevel)
            || !TryGetIntegrityLevel(processId, out var everythingIntegrityLevel))
        {
            _availabilityStatus = EverythingAvailabilityStatus.AccessDenied;
            _lastError = EverythingIpcError.AccessDenied;
            return _availabilityStatus;
        }

        _availabilityStatus = currentIntegrityLevel == everythingIntegrityLevel
            ? EverythingAvailabilityStatus.Available
            : EverythingAvailabilityStatus.IntegrityMismatch;
        _lastError = ErrorForAvailability(_availabilityStatus);
        return _availabilityStatus;
    }

    private static uint ErrorForAvailability(EverythingAvailabilityStatus status)
    {
        return status switch
        {
            EverythingAvailabilityStatus.IntegrityMismatch => EverythingIpcError.IntegrityMismatch,
            EverythingAvailabilityStatus.AccessDenied => EverythingIpcError.AccessDenied,
            EverythingAvailabilityStatus.IpcUnavailable => EverythingIpcError.IpcUnavailable,
            _ => EverythingIpcError.Unavailable
        };
    }

    private static bool SendQuery(
        IntPtr everythingWindow,
        IntPtr replyWindow,
        IntPtr copyDataPointer,
        CancellationToken cancellationToken,
        out IntPtr accepted,
        out bool cancelled)
    {
        accepted = IntPtr.Zero;
        cancelled = false;

        // SendMessageTimeout itself has no cancellation handle. Run it on a
        // worker and keep the unmanaged buffers alive until the native call
        // returns; cancellation then bounds the caller's wait to the native
        // timeout instead of adding another fixed multi-second stall.
        var sendTask = Task.Run(() =>
        {
            var result = SendMessageTimeout(
                everythingWindow,
                WmCopyData,
                replyWindow,
                copyDataPointer,
                SmtoAbortIfHung,
                (uint)QueryTimeout.TotalMilliseconds,
                out var acceptedResult);
            return (result, acceptedResult);
        });

        while (!sendTask.Wait(TimeSpan.FromMilliseconds(10)))
        {
            // Everything may send the reply synchronously while handling the
            // request. Pump the reply window while the worker is in the
            // native call, otherwise a cross-thread SendMessage can wait for
            // a response that this thread never dispatches.
            PumpMessages(replyWindow);

            if (cancellationToken.IsCancellationRequested)
            {
                cancelled = true;
                // The unmanaged query buffer is owned by the caller. Wait for
                // the bounded native call to finish before it is freed.
                _ = sendTask.GetAwaiter().GetResult();
                return false;
            }
        }

        var sendResult = sendTask.GetAwaiter().GetResult();
        accepted = sendResult.acceptedResult;
        return sendResult.result != IntPtr.Zero;
    }

    private static void PumpMessages(IntPtr window)
    {
        while (PeekMessage(out var message, window, 0, 0, PmRemove))
        {
            _ = TranslateMessage(ref message);
            _ = DispatchMessage(ref message);
        }
    }

    private static uint GetWindowProcessId(IntPtr window)
    {
        if (window == IntPtr.Zero)
        {
            return 0;
        }

        _ = GetWindowThreadProcessId(window, out var processId);
        return processId;
    }

    private static bool TryGetIntegrityLevel(uint processId, out uint integrityLevel)
    {
        integrityLevel = 0;
        var processHandle = OpenProcess(ProcessQueryLimitedInformation, false, processId);
        if (processHandle == IntPtr.Zero)
        {
            return false;
        }

        try
        {
            if (!OpenProcessToken(processHandle, TokenQuery, out var tokenHandle))
            {
                return false;
            }

            try
            {
                _ = GetTokenInformation(tokenHandle, TokenIntegrityLevel, IntPtr.Zero, 0, out var bufferLength);
                if (Marshal.GetLastWin32Error() != ErrorInsufficientBuffer || bufferLength <= 0)
                {
                    return false;
                }

                var buffer = Marshal.AllocHGlobal(bufferLength);
                try
                {
                    if (!GetTokenInformation(
                            tokenHandle,
                            TokenIntegrityLevel,
                            buffer,
                            bufferLength,
                            out _))
                    {
                        return false;
                    }

                    var label = Marshal.PtrToStructure<TokenMandatoryLabel>(buffer);
                    if (label.Label.Sid == IntPtr.Zero)
                    {
                        return false;
                    }

                    var subAuthorityCount = Marshal.ReadByte(label.Label.Sid, 1);
                    if (subAuthorityCount == 0)
                    {
                        return false;
                    }

                    var subAuthority = GetSidSubAuthority(label.Label.Sid, (byte)(subAuthorityCount - 1));
                    if (subAuthority == IntPtr.Zero)
                    {
                        return false;
                    }

                    integrityLevel = unchecked((uint)Marshal.ReadInt32(subAuthority));
                    return true;
                }
                finally
                {
                    Marshal.FreeHGlobal(buffer);
                }
            }
            finally
            {
                _ = CloseHandle(tokenHandle);
            }
        }
        finally
        {
            _ = CloseHandle(processHandle);
        }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindow(string className, string? windowName);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint desiredAccess, bool inheritHandle, uint processId);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr processHandle, uint desiredAccess, out IntPtr tokenHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool GetTokenInformation(
        IntPtr tokenHandle,
        int tokenInformationClass,
        IntPtr tokenInformation,
        int tokenInformationLength,
        out int returnLength);

    [DllImport("advapi32.dll")]
    private static extern IntPtr GetSidSubAuthority(IntPtr sid, byte subAuthorityIndex);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SendMessageTimeout(
        IntPtr window,
        uint message,
        IntPtr wParam,
        IntPtr lParam,
        uint flags,
        uint timeout,
        out IntPtr result);

    [DllImport("user32.dll")]
    private static extern bool PeekMessage(
        out NativeMessage message,
        IntPtr window,
        uint messageFilterMinimum,
        uint messageFilterMaximum,
        uint removeMessage);

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref NativeMessage message);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref NativeMessage message);

    [StructLayout(LayoutKind.Sequential)]
    private struct TokenMandatoryLabel
    {
        public SidAndAttributes Label;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SidAndAttributes
    {
        public IntPtr Sid;
        public uint Attributes;
    }
}
