using System.Diagnostics;
using System.IO;
using System.Media;
using System.Runtime.InteropServices;
using System.Windows;
using Microsoft.VisualBasic.FileIO;
using YTools.Models;
using YTools.ModuleKit;

namespace YTools.Services;

public enum ActionExecutionOutcome
{
    HidePanel,
    KeepPanel,
    Navigate,
    Preview,
    ClearFileBufferAndHide
}

public sealed record ActionExecutionResult(ActionExecutionOutcome Outcome, string? Path = null);

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
                if (!Path.IsPathRooted(open.Path))
                {
                    ShowAlert("已阻止外部链接", "YTools 只允许打开本机文件和应用。");
                    return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
                }

                return OpenLocal(open.Path);
            case ResultAction.ActivateApplication application:
                return ActivateApplication(application.AppUserModelId);
            case ResultAction.Reveal reveal:
                if (Path.IsPathRooted(reveal.Path))
                {
                    RevealInExplorer(reveal.Path);
                }

                break;
            case ResultAction.Navigate navigate:
                return new ActionExecutionResult(ActionExecutionOutcome.Navigate, navigate.Path);
            case ResultAction.EditQuery editQuery:
                return new ActionExecutionResult(ActionExecutionOutcome.Navigate, editQuery.Text);
            case ResultAction.HideApplication hide:
                HideApplication(hide.ProcessName);
                break;
            case ResultAction.QuitApplication quit:
                QuitApplication(quit.ProcessName);
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
                if (!_snippets.Save(text))
                {
                    ShowAlert("无法保存文本片段", _snippets.SaveError ?? "加密存储当前不可用。");
                    return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
                }

                SystemSounds.Asterisk.Play();
                break;
            case LauncherActionKind.Preview when action.Payload is string path:
                return new ActionExecutionResult(ActionExecutionOutcome.Preview, path);
            case LauncherActionKind.OpenWith when action.Payload is string path:
                OpenWithDialog(path);
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
                RevealMany(paths);
                return new ActionExecutionResult(ActionExecutionOutcome.ClearFileBufferAndHide);
            case LauncherActionKind.CopyPaths when action.Payload is List<string> paths:
                CopyText(string.Join("\n", paths));
                break;
        }

        return new ActionExecutionResult(ActionExecutionOutcome.HidePanel);
    }

    public void Reveal(string path)
    {
        if (Path.IsPathRooted(path))
        {
            RevealInExplorer(path);
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
        if (!File.Exists(source))
        {
            ShowAlert("项目已不存在", source);
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

        var destination = Path.Combine(dialog.FolderName, Path.GetFileName(source));
        if (File.Exists(destination))
        {
            ShowAlert(move ? "移动失败" : "复制失败", "目标目录已存在同名项目，未覆盖任何文件。");
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        try
        {
            if (move)
            {
                File.Move(source, destination);
            }
            else
            {
                File.Copy(source, destination);
            }

            return new ActionExecutionResult(ActionExecutionOutcome.HidePanel);
        }
        catch (Exception exception)
        {
            ShowAlert(move ? "移动失败" : "复制失败", exception.Message);
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }
    }

    private ActionExecutionResult MoveToTrash(string path)
    {
        if (!File.Exists(path))
        {
            ShowAlert("项目已不存在", path);
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        var owner = _ownerProvider();
        var confirmation = MessageBox.Show(
            owner,
            $"将“{Path.GetFileName(path)}”移入回收站？\n\nYTools 不会永久删除项目。你仍可从回收站恢复。",
            "移入回收站",
            MessageBoxButton.OKCancel,
            MessageBoxImage.Warning);
        if (confirmation != MessageBoxResult.OK)
        {
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        try
        {
            FileSystem.DeleteFile(
                path,
                UIOption.OnlyErrorDialogs,
                RecycleOption.SendToRecycleBin,
                UICancelOption.DoNothing);
            return new ActionExecutionResult(ActionExecutionOutcome.HidePanel);
        }
        catch (Exception exception)
        {
            ShowAlert("无法移入回收站", exception.Message);
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }
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

        const uint noProgressUi = 0x0002;
        const uint noSound = 0x0004;
        var result = SHEmptyRecycleBin(IntPtr.Zero, null, noProgressUi | noSound);
        if (result != 0)
        {
            ShowAlert("无法清空回收站", $"系统返回错误 {result}。");
            return new ActionExecutionResult(ActionExecutionOutcome.KeepPanel);
        }

        return new ActionExecutionResult(ActionExecutionOutcome.HidePanel);
    }

    private ActionExecutionResult OpenMany(IReadOnlyList<string> paths)
    {
        var failed = new List<string>();
        foreach (var path in paths)
        {
            if (!File.Exists(path) && !Directory.Exists(path))
            {
                failed.Add(path);
                continue;
            }

            try
            {
                Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
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

    private static void RevealMany(IReadOnlyList<string> paths)
    {
        var existing = paths.Where(path => File.Exists(path) || Directory.Exists(path)).ToList();
        if (existing.Count == 0)
        {
            return;
        }

        RevealInExplorer(existing[0]);
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

    private static void RevealInExplorer(string path)
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
        }
        catch
        {
            // Explorer failures are non-fatal for the launcher.
        }
    }

    private static void HideApplication(string processName)
    {
        foreach (var process in Process.GetProcessesByName(processName))
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
    }

    private static void QuitApplication(string processName)
    {
        foreach (var process in Process.GetProcessesByName(processName))
        {
            try
            {
                if (!process.CloseMainWindow())
                {
                    process.Kill();
                    continue;
                }

                if (!process.WaitForExit(3_000))
                {
                    process.Kill();
                }
            }
            catch
            {
                // The process may have exited already.
            }
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
