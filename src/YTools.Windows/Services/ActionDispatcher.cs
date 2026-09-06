using System.Diagnostics;
using System.IO;
using System.Media;
using System.Runtime.InteropServices;
using System.Windows;
using Microsoft.VisualBasic.FileIO;
using YTools.Core;
using YTools.Models;
using YTools.ModuleKit;

namespace YTools.Services;

public enum ActionExecutionOutcome
{
    HidePanel,
    KeepPanel,
    Navigate,
    Preview,
    ClearFileBufferAndHide,
    BackgroundStarted
}

public sealed record ActionExecutionResult(
    ActionExecutionOutcome Outcome,
    string? Path = null,
    string? ErrorTitle = null,
    string? ErrorMessage = null);

/// <summary>
/// Executes the bounded native action vocabulary. All file and system side
/// effects go through fixed Windows APIs; user text never becomes a command.
/// </summary>
public sealed class ActionDispatcher
{
    private const int WmSysCommand = 0x0112;
    private const int ScScreenSave = 0xF140;
    private const int ScMonitorPower = 0xF170;
    private const int MonitorPowerOff = 2;
    private const int SwHide = 0;
    private static readonly IntPtr HwndBroadcast = new(0xFFFF);

    private readonly SnippetManager _snippets;
    private readonly RecentDocumentsManager _recentDocuments;
    private readonly Action _onOpenSettings;
    private readonly Action<string> _onShowLargeType;
    private readonly Func<Window?> _ownerProvider;
    private int _backgroundOperationActive;

    public event EventHandler<ActionExecutionResult>? BackgroundOperationCompleted;

    public event EventHandler? BusyStateChanged;

    public bool IsBusy => Volatile.Read(ref _backgroundOperationActive) != 0;

    public ActionDispatcher(
        SnippetManager snippets,
        RecentDocumentsManager recentDocuments,
        Action onOpenSettings,
        Action<string> onShowLargeType,
        Func<Window?> ownerProvider)
    {
        _snippets = snippets;
        _recentDocuments = recentDocuments;
        _onOpenSettings = onOpenSettings;
        _onShowLargeType = onShowLargeType;
        _ownerProvider = ownerProvider;
    }

    public ActionExecutionResult Execute(ResultAction action)
    {
        switch (action)
        {
            case ResultAction.Copy copy:
                CopyText(copy.Text);
                break;
            case ResultAction.Open open:
                if (!LocalPathPolicy.TryNormalize(open.Path, out var openPath))
                {
                    ShowAlert("已阻止外部链接", "YTools 只允许打开本机文件和应用。");
                    return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
                }

                return OpenLocal(openPath);
            case ResultAction.ActivateApplication application:
                return ActivateApplication(application.AppUserModelId);
            case ResultAction.Reveal reveal:
                if (LocalPathPolicy.TryNormalize(reveal.Path, out var revealPath))
                {
                    _ = RevealInExplorer(revealPath);
                }

                break;
            case ResultAction.Navigate navigate:
                return new ActionExecutionResult(ActionExecutionOutcome.Navigate, navigate.Path);
            case ResultAction.EditQuery editQuery:
                return new ActionExecutionResult(ActionExecutionOutcome.Navigate, editQuery.Text);
            case ResultAction.HideApplication hide:
                HideApplication(hide.ExecutablePath);
                break;
            case ResultAction.QuitApplication quit:
                QuitApplication(quit.ExecutablePath);
                break;
            case ResultAction.ShowTrash:
                OpenRecycleBin();
                break;
            case ResultAction.EmptyTrash:
                return EmptyTrash();
            case ResultAction.StartScreenSaver:
                _ = SendMessage(HwndBroadcast, WmSysCommand, ScScreenSave, IntPtr.Zero);
                break;
            case ResultAction.SleepDisplays:
                _ = SendMessage(HwndBroadcast, WmSysCommand, ScMonitorPower, new IntPtr(MonitorPowerOff));
                break;
            case ResultAction.OpenFocusSettings:
                OpenSettingsUri("ms-settings:focus");
                break;
            case ResultAction.OpenAppearanceSettings:
                OpenSettingsUri("ms-settings:colors");
                break;
            case ResultAction.OpenSettings:
                _onOpenSettings();
                break;
            case ResultAction.None:
                return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        return new ActionExecutionResult(ActionExecutionOutcome.HidePanel);
    }

    public ActionExecutionResult Execute(LauncherAction action)
    {
        switch (action.Kind)
        {
            case LauncherActionKind.Perform when action.Payload is ResultAction resultAction:
                return Execute(resultAction);
            case LauncherActionKind.CopyPath when action.Payload is string path:
                CopyText(path);
                break;
            case LauncherActionKind.CopyText when action.Payload is string text:
                CopyText(text);
                break;
            case LauncherActionKind.LargeType when action.Payload is string text:
                _onShowLargeType(text);
                break;
            case LauncherActionKind.SaveSnippet when action.Payload is string text:
                return BeginBackgroundOperation(async () =>
                {
                    if (!await _snippets.SaveAsync(text).ConfigureAwait(false))
                    {
                        return new ActionExecutionResult(
                            ActionExecutionOutcome.KeepPanel,
                            ErrorTitle: "无法保存文本片段",
                            ErrorMessage: _snippets.SaveError ?? "加密存储当前不可用。");
                    }

                    SystemSounds.Asterisk.Play();
                    return new ActionExecutionResult(ActionExecutionOutcome.HidePanel);
                });
            case LauncherActionKind.Preview when action.Payload is string path:
                return new ActionExecutionResult(ActionExecutionOutcome.Preview, path);
            case LauncherActionKind.OpenWith when action.Payload is string path:
                if (!LocalPathPolicy.TryNormalize(path, out var openWithPath))
                {
                    ShowAlert("路径无效", "只允许使用本机磁盘上的完整绝对路径。");
                    return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
                }

                OpenWithDialog(openWithPath);
                break;
            case LauncherActionKind.CopyFile when action.Payload is string path:
                return CopyOrMoveFile(path, move: false);
            case LauncherActionKind.MoveFile when action.Payload is string path:
                return CopyOrMoveFile(path, move: true);
            case LauncherActionKind.Trash when action.Payload is string path:
                return MoveToTrash(path);
            case LauncherActionKind.OpenMany when action.Payload is List<string> paths:
                return OpenMany(paths);
            case LauncherActionKind.RevealMany when action.Payload is List<string> paths:
                return RevealMany(paths);
            case LauncherActionKind.CopyPaths when action.Payload is List<string> paths:
                CopyText(string.Join("\n", paths));
                break;
        }

        return new ActionExecutionResult(ActionExecutionOutcome.HidePanel);
    }

    public void Reveal(string path)
    {
        if (LocalPathPolicy.TryNormalize(path, out var normalized))
        {
            _ = RevealInExplorer(normalized);
        }
    }

    public void CopyPath(string path)
    {
        CopyText(path);
    }

    private ActionExecutionResult OpenLocal(string path)
    {
        if (!File.Exists(path) && !Directory.Exists(path))
        {
            ShowAlert("项目已不存在", path);
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        try
        {
            Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
            if (File.Exists(path) && !path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
            {
                _recentDocuments.Record(path);
            }

            return new ActionExecutionResult(ActionExecutionOutcome.HidePanel);
        }
        catch (Exception exception)
        {
            ShowAlert("无法打开项目", exception.Message);
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }
    }

    private ActionExecutionResult ActivateApplication(string appUserModelId)
    {
        try
        {
            var manager = (IApplicationActivationManager)new ApplicationActivationManager();
            try
            {
                manager.ActivateApplication(appUserModelId, null, 0, out _);
            }
            finally
            {
                _ = Marshal.FinalReleaseComObject(manager);
            }

            return new ActionExecutionResult(ActionExecutionOutcome.HidePanel);
        }
        catch (Exception exception)
        {
            ShowAlert("无法启动应用", exception.Message);
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }
    }

    private ActionExecutionResult CopyOrMoveFile(string source, bool move)
    {
        if (!LocalPathPolicy.TryNormalize(source, out var normalizedSource)
            || (!File.Exists(normalizedSource) && !Directory.Exists(normalizedSource)))
        {
            ShowAlert("项目已不存在", source);
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }
        if (Directory.Exists(normalizedSource) && IsReparsePointOrUnreadable(normalizedSource))
        {
            ShowAlert(move ? "移动失败" : "复制失败", "不处理目录连接或重解析点。");
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        var dialog = new Microsoft.Win32.OpenFolderDialog
        {
            Title = move ? "移动到这里" : "复制到这里",
            Multiselect = false
        };
        var owner = _ownerProvider();
        if (dialog.ShowDialog(owner) != true || string.IsNullOrEmpty(dialog.FolderName))
        {
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        if (!LocalPathPolicy.TryNormalize(dialog.FolderName, out var destinationDirectory))
        {
            ShowAlert("目标目录无效", "只允许使用本机磁盘上的完整绝对路径。");
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        var destination = Path.Combine(destinationDirectory, Path.GetFileName(normalizedSource));
        if (!LocalPathPolicy.IsValid(destination)
            || File.Exists(destination)
            || Directory.Exists(destination))
        {
            ShowAlert(move ? "移动失败" : "复制失败", "目标目录已存在同名项目，未覆盖任何文件。");
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        if (Directory.Exists(normalizedSource) && IsDescendantPath(destination, normalizedSource))
        {
            ShowAlert(move ? "移动失败" : "复制失败", "目标目录不能位于源目录内部。");
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        return BeginBackgroundOperation(() =>
        {
            try
            {
                var isDirectory = Directory.Exists(normalizedSource);
                if (move)
                {
                    if (isDirectory)
                    {
                        FileSystem.MoveDirectory(normalizedSource, destination, overwrite: false);
                    }
                    else
                    {
                        File.Move(normalizedSource, destination);
                    }
                }
                else if (isDirectory)
                {
                    CopyDirectory(normalizedSource, destination);
                }
                else
                {
                    File.Copy(normalizedSource, destination);
                }

                return new ActionExecutionResult(ActionExecutionOutcome.HidePanel);
            }
            catch (Exception exception)
            {
                return Failure(move ? "移动失败" : "复制失败", exception);
            }
        });
    }

    private ActionExecutionResult MoveToTrash(string path)
    {
        if (!LocalPathPolicy.TryNormalize(path, out var normalizedPath)
            || (!File.Exists(normalizedPath) && !Directory.Exists(normalizedPath)))
        {
            ShowAlert("项目已不存在", path);
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        var owner = _ownerProvider();
        var confirmation = MessageBox.Show(
            owner,
            $"将“{Path.GetFileName(normalizedPath)}”移入回收站？\n\nYTools 不会永久删除项目。你仍可从回收站恢复。",
            "移入回收站",
            MessageBoxButton.OKCancel,
            MessageBoxImage.Warning);
        if (confirmation != MessageBoxResult.OK)
        {
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        return BeginBackgroundOperation(() => RunSta(() =>
        {
            try
            {
                RecycleOnly(normalizedPath);

                return new ActionExecutionResult(ActionExecutionOutcome.HidePanel);
            }
            catch (Exception exception)
            {
                return Failure("无法移入回收站", exception);
            }
        }));
    }

    private ActionExecutionResult EmptyTrash()
    {
        var owner = _ownerProvider();
        var confirmation = MessageBox.Show(
            owner,
            "永久清空回收站？\n\n系统将永久删除回收站中的项目，此操作无法撤销。",
            "清空回收站",
            MessageBoxButton.OKCancel,
            MessageBoxImage.Warning);
        if (confirmation != MessageBoxResult.OK)
        {
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        return BeginBackgroundOperation(() =>
        {
            const uint noProgressUi = 0x0002;
            const uint noSound = 0x0004;
            var result = SHEmptyRecycleBin(IntPtr.Zero, null, noProgressUi | noSound);
            return result == 0
                ? new ActionExecutionResult(ActionExecutionOutcome.HidePanel)
                : new ActionExecutionResult(
                    ActionExecutionOutcome.KeepPanel,
                    ErrorTitle: "无法清空回收站",
                    ErrorMessage: $"系统返回错误 {result}。");
        });
    }

    private ActionExecutionResult OpenMany(IReadOnlyList<string> paths)
    {
        var failed = new List<string>();
        foreach (var path in paths)
        {
            if (!LocalPathPolicy.TryNormalize(path, out var normalized)
                || (!File.Exists(normalized) && !Directory.Exists(normalized)))
            {
                failed.Add(path);
                continue;
            }

            try
            {
                Process.Start(new ProcessStartInfo(normalized) { UseShellExecute = true });
            }
            catch
            {
                failed.Add(path);
            }
        }

        if (failed.Count > 0)
        {
            ShowBatchFailure("部分项目无法打开", failed);
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        return new ActionExecutionResult(ActionExecutionOutcome.ClearFileBufferAndHide);
    }

    private ActionExecutionResult RevealMany(IReadOnlyList<string> paths)
    {
        var normalized = paths
            .Select(path => LocalPathPolicy.TryNormalize(path, out var value) ? value : null)
            .Where(path => path is not null)
            .Cast<string>()
            .Where(path => File.Exists(path) || Directory.Exists(path))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (normalized.Count != paths.Count || normalized.Count == 0)
        {
            ShowAlert("无法显示全部项目", "存在无效或已不存在的路径，文件缓冲区已保留。");
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        var failures = new List<string>();
        foreach (var group in normalized.GroupBy(Path.GetDirectoryName, StringComparer.OrdinalIgnoreCase))
        {
            if (string.IsNullOrEmpty(group.Key) || !SelectManyInExplorer(group.Key, group.ToList()))
            {
                failures.AddRange(group);
            }
        }

        if (failures.Count > 0)
        {
            ShowBatchFailure("部分项目无法在资源管理器中显示", failures);
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        return new ActionExecutionResult(ActionExecutionOutcome.ClearFileBufferAndHide);
    }

    private static void OpenWithDialog(string path)
    {
        try
        {
            Process.Start(
                new ProcessStartInfo("rundll32.exe", $"shell32.dll,OpenAs_RunDLL \"{path}\"")
                {
                    UseShellExecute = false
                });
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                Application.Current.Windows.OfType<Window>().FirstOrDefault(window => window.IsActive),
                exception.Message,
                "无法打开方式对话框",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }

    private static void OpenRecycleBin()
    {
        try
        {
            Process.Start(new ProcessStartInfo("shell:RecycleBinFolder") { UseShellExecute = true });
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                exception.Message,
                "无法打开回收站",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }

    private static void OpenSettingsUri(string uri)
    {
        try
        {
            Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true });
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                exception.Message,
                "无法打开系统设置",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }

    private static bool RevealInExplorer(string path)
    {
        try
        {
            var arguments = Directory.Exists(path)
                ? $"\"{path}\""
                : $"/select,\"{path}\"";
            Process.Start(
                new ProcessStartInfo("explorer.exe", arguments)
                {
                    UseShellExecute = false
                });
            return true;
        }
        catch
        {
            // Explorer failures are non-fatal for the launcher.
            return false;
        }
    }

    private static void HideApplication(string executablePath)
    {
        foreach (var process in MatchingProcesses(executablePath))
        {
            try
            {
                _ = EnumWindows((hwnd, lParam) =>
                {
                    _ = GetWindowThreadProcessId(hwnd, out var pid);
                    if (pid == process.Id && IsWindowVisible(hwnd))
                    {
                        _ = ShowWindow(hwnd, SwHide);
                    }

                    return true;
                }, IntPtr.Zero);
            }
            finally
            {
                process.Dispose();
            }
        }
    }

    private static void QuitApplication(string executablePath)
    {
        foreach (var process in MatchingProcesses(executablePath))
        {
            try
            {
                _ = process.CloseMainWindow();
            }
            catch
            {
                // The process may have exited already.
            }
            finally
            {
                process.Dispose();
            }
        }
    }

    private static IEnumerable<Process> MatchingProcesses(string executablePath)
    {
        if (!LocalPathPolicy.TryNormalize(executablePath, out var expected)
            || !Path.GetExtension(expected).Equals(".exe", StringComparison.OrdinalIgnoreCase))
        {
            yield break;
        }

        foreach (var process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(expected)))
        {
            string? actual = null;
            try
            {
                actual = process.MainModule?.FileName;
            }
            catch
            {
                // Protected processes cannot be safely identified.
            }

            if (LocalPathPolicy.TryNormalize(actual, out var normalized)
                && string.Equals(normalized, expected, StringComparison.OrdinalIgnoreCase))
            {
                yield return process;
            }
            else
            {
                process.Dispose();
            }
        }
    }

    private static void CopyDirectory(string source, string destination)
    {
        var sourceInfo = new DirectoryInfo(source);
        if (sourceInfo.Attributes.HasFlag(FileAttributes.ReparsePoint))
        {
            throw new IOException("不复制目录连接或重解析点。");
        }

        Directory.CreateDirectory(destination);
        foreach (var file in sourceInfo.GetFiles())
        {
            file.CopyTo(Path.Combine(destination, file.Name), overwrite: false);
        }

        foreach (var child in sourceInfo.GetDirectories())
        {
            CopyDirectory(child.FullName, Path.Combine(destination, child.Name));
        }
    }

    private static bool IsDescendantPath(string candidate, string parent)
    {
        var parentWithSeparator = parent.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            + Path.DirectorySeparatorChar;
        return candidate.StartsWith(parentWithSeparator, StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsReparsePointOrUnreadable(string path)
    {
        try
        {
            return new DirectoryInfo(path).Attributes.HasFlag(FileAttributes.ReparsePoint);
        }
        catch
        {
            return true;
        }
    }

    private static void RecycleOnly(string path)
    {
        var itemId = typeof(IShellItem).GUID;
        var createResult = SHCreateItemFromParsingName(path, IntPtr.Zero, ref itemId, out var item);
        if (createResult != 0 || item is null)
        {
            if (createResult != 0) { Marshal.ThrowExceptionForHR(createResult); }
            throw new IOException("无法解析要移入回收站的项目。");
        }

        IFileOperation? operation = null;
        try
        {
            operation = (IFileOperation)new FileOperation();
            operation.SetOperationFlags(0x00080000 | 0x00100000 | 0x0010 | 0x0004 | 0x0400); // RECYCLEONDELETE + EARLYFAILURE + no UI
            operation.DeleteItem(item!, IntPtr.Zero);
            operation.PerformOperations();
            operation.GetAnyOperationsAborted(out var aborted);
            if (aborted) { throw new IOException("操作已取消或项目无法移入回收站。"); }
        }
        finally
        {
            if (operation is not null) { _ = Marshal.FinalReleaseComObject(operation); }
            if (item is not null) { _ = Marshal.FinalReleaseComObject(item); }
        }
    }

    private static Task<T> RunSta<T>(Func<T> operation)
    {
        var completion = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            try
            {
                completion.TrySetResult(operation());
            }
            catch (Exception exception)
            {
                completion.TrySetException(exception);
            }
        })
        {
            IsBackground = true,
            Name = "YTools Shell file operation"
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        return completion.Task;
    }

    private ActionExecutionResult BeginBackgroundOperation(Func<ActionExecutionResult> operation)
    {
        return BeginBackgroundOperation(() => Task.Run(operation));
    }

    private ActionExecutionResult BeginBackgroundOperation(Func<Task<ActionExecutionResult>> operation)
    {
        if (Interlocked.CompareExchange(ref _backgroundOperationActive, 1, 0) != 0)
        {
            ShowAlert("文件操作进行中", "请等待当前文件操作完成后再试。");
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        BusyStateChanged?.Invoke(this, EventArgs.Empty);
        var dispatcher = _ownerProvider()?.Dispatcher ?? Application.Current?.Dispatcher;
        Task<ActionExecutionResult> operationTask;
        try
        {
            operationTask = operation();
        }
        catch (Exception exception)
        {
            operationTask = Task.FromException<ActionExecutionResult>(exception);
        }

        _ = operationTask.ContinueWith(task =>
        {
            var result = task.IsCompletedSuccessfully
                ? task.Result
                : Failure("文件操作失败", task.Exception?.GetBaseException() ?? new IOException("未知错误。"));
            void Complete()
            {
                Interlocked.Exchange(ref _backgroundOperationActive, 0);
                BusyStateChanged?.Invoke(this, EventArgs.Empty);
                if (result.ErrorTitle is not null)
                {
                    ShowAlert(result.ErrorTitle, result.ErrorMessage ?? "未知错误。");
                }

                BackgroundOperationCompleted?.Invoke(this, result);
            }

            if (dispatcher is not null && !dispatcher.CheckAccess())
            {
                _ = dispatcher.BeginInvoke(Complete);
            }
            else
            {
                Complete();
            }
        }, CancellationToken.None, TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
        return new ActionExecutionResult(ActionExecutionOutcome.BackgroundStarted);
    }

    private static ActionExecutionResult Failure(string title, Exception exception)
    {
        return new ActionExecutionResult(
            ActionExecutionOutcome.KeepPanel,
            ErrorTitle: title,
            ErrorMessage: exception.Message);
    }

    private static bool SelectManyInExplorer(string folder, IReadOnlyList<string> paths)
    {
        var folderPidl = ILCreateFromPath(folder);
        if (folderPidl == IntPtr.Zero)
        {
            return false;
        }

        var absolutePidls = new List<IntPtr>();
        try
        {
            var children = new List<IntPtr>();
            foreach (var path in paths)
            {
                var pidl = ILCreateFromPath(path);
                if (pidl == IntPtr.Zero)
                {
                    return false;
                }

                absolutePidls.Add(pidl);
                children.Add(ILFindLastID(pidl));
            }

            return SHOpenFolderAndSelectItems(folderPidl, (uint)children.Count, children.ToArray(), 0) == 0;
        }
        finally
        {
            foreach (var pidl in absolutePidls)
            {
                ILFree(pidl);
            }

            ILFree(folderPidl);
        }
    }

    private static void CopyText(string text)
    {
        try
        {
            Clipboard.SetText(text);
        }
        catch
        {
            // Clipboard contention is transient; the launcher keeps running.
        }
    }

    private void ShowAlert(string title, string message)
    {
        MessageBox.Show(
            _ownerProvider(),
            message,
            title,
            MessageBoxButton.OK,
            MessageBoxImage.Warning);
    }

    private void ShowBatchFailure(string title, IReadOnlyList<string> failed)
    {
        var names = string.Join("\n", failed.Take(8).Select(Path.GetFileName));
        var remainder = failed.Count > 8 ? $"\n另有 {failed.Count - 8} 项" : "";
        ShowAlert(title, $"失败项目仍保留在文件缓冲区：\n{names}{remainder}");
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHEmptyRecycleBin(IntPtr hwnd, string? root, uint flags);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
    private static extern int SHCreateItemFromParsingName(
        string path,
        IntPtr bindContext,
        ref Guid interfaceId,
        [MarshalAs(UnmanagedType.Interface)] out IShellItem? item);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr ILCreateFromPath(string path);

    [DllImport("shell32.dll")]
    private static extern IntPtr ILFindLastID(IntPtr pidl);

    [DllImport("shell32.dll")]
    private static extern void ILFree(IntPtr pidl);

    [DllImport("shell32.dll")]
    private static extern int SHOpenFolderAndSelectItems(
        IntPtr folderPidl,
        uint itemCount,
        [MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 1)] IntPtr[] itemPidls,
        uint flags);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, int msg, int wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [ComImport]
    [Guid("3AD05575-8857-4850-9277-11B85BDB8E09")]
    private class FileOperation
    {
    }

    [ComImport]
    [Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem
    {
        void BindToHandler(IntPtr bindContext, ref Guid handlerId, ref Guid interfaceId, out IntPtr result);
        void GetParent([MarshalAs(UnmanagedType.Interface)] out IShellItem parent);
        void GetDisplayName(uint displayNameType, out IntPtr name);
        void GetAttributes(uint mask, out uint attributes);
        void Compare([MarshalAs(UnmanagedType.Interface)] IShellItem other, uint hint, out int order);
    }

    [ComImport]
    [Guid("947AAB5F-0A5C-4C13-B4D6-4BF7836FC9F8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileOperation
    {
        void Advise(IntPtr sink, out uint cookie);
        void Unadvise(uint cookie);
        void SetOperationFlags(uint flags);
        void SetProgressMessage([MarshalAs(UnmanagedType.LPWStr)] string message);
        void SetProgressDialog(IntPtr dialog);
        void SetProperties(IntPtr properties);
        void SetOwnerWindow(uint ownerWindow);
        void ApplyPropertiesToItem([MarshalAs(UnmanagedType.Interface)] IShellItem item);
        void ApplyPropertiesToItems(IntPtr items);
        void RenameItem([MarshalAs(UnmanagedType.Interface)] IShellItem item, [MarshalAs(UnmanagedType.LPWStr)] string name, IntPtr sink);
        void RenameItems(IntPtr items, [MarshalAs(UnmanagedType.LPWStr)] string name);
        void MoveItem([MarshalAs(UnmanagedType.Interface)] IShellItem item, [MarshalAs(UnmanagedType.Interface)] IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string? name, IntPtr sink);
        void MoveItems(IntPtr items, [MarshalAs(UnmanagedType.Interface)] IShellItem destination);
        void CopyItem([MarshalAs(UnmanagedType.Interface)] IShellItem item, [MarshalAs(UnmanagedType.Interface)] IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string? name, IntPtr sink);
        void CopyItems(IntPtr items, [MarshalAs(UnmanagedType.Interface)] IShellItem destination);
        void DeleteItem([MarshalAs(UnmanagedType.Interface)] IShellItem item, IntPtr sink);
        void DeleteItems(IntPtr items);
        void NewItem([MarshalAs(UnmanagedType.Interface)] IShellItem destination, uint attributes, [MarshalAs(UnmanagedType.LPWStr)] string name, [MarshalAs(UnmanagedType.LPWStr)] string? templateName, IntPtr sink);
        void PerformOperations();
        void GetAnyOperationsAborted([MarshalAs(UnmanagedType.Bool)] out bool aborted);
    }

    [ComImport]
    [Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
    private class ApplicationActivationManager
    {
    }

    [ComImport]
    [Guid("2e941141-7f97-4756-ba1d-9decde894a3d")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IApplicationActivationManager
    {
        void ActivateApplication(
            [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            [MarshalAs(UnmanagedType.LPWStr)] string? arguments,
            uint options,
            out uint processId);

        void ActivateForFile(
            [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            IntPtr itemArray,
            [MarshalAs(UnmanagedType.LPWStr)] string? verb,
            out uint processId);

        void ActivateForProtocol(
            [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            IntPtr itemArray,
            out uint processId);
    }
}
