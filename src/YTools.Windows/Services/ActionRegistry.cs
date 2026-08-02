using System.IO;
using YTools.Models;
using YTools.ModuleKit;

namespace YTools.Services;

public sealed class ActionRegistry
{
    public IReadOnlyList<LauncherAction> ActionsFor(LauncherResult result)
    {
        var actions = new List<LauncherAction>();
        var resourcePath = result.ResourcePath;
        if (resourcePath is not null)
        {
            var isApplication = result.IsApplication;
            var isDirectory = Directory.Exists(resourcePath);

            if (isDirectory)
            {
                actions.Add(Action(
                    "browse",
                    "在 YTools 中浏览",
                    "进入该目录并继续键盘导航",
                    "arrow.right.circle",
                    LauncherActionKind.Perform,
                    new ResultAction.Navigate(NavigationQuery(resourcePath))));
            }

            actions.Add(Action(
                "open",
                isApplication ? "启动应用" : "打开",
                "使用系统默认方式打开",
                "arrow.up.forward.app",
                LauncherActionKind.Perform,
                new ResultAction.Open(resourcePath)));
            actions.Add(Action(
                "reveal",
                "在资源管理器中显示",
                "选择该项目并打开所在目录",
                "folder",
                LauncherActionKind.Perform,
                new ResultAction.Reveal(resourcePath)));
            actions.Add(Action(
                "copy-path",
                "复制路径",
                resourcePath,
                "doc.on.doc",
                LauncherActionKind.CopyPath,
                resourcePath));
            if (isApplication)
            {
                var processName = Path.GetFileNameWithoutExtension(resourcePath);
                actions.Add(Action(
                    "hide-application",
                    "隐藏应用",
                    "隐藏正在运行的应用窗口",
                    "eye.slash",
                    LauncherActionKind.Perform,
                    new ResultAction.HideApplication(processName)));
                actions.Add(Action(
                    "quit-application",
                    "退出应用",
                    "请求应用正常退出",
                    "xmark.circle",
                    LauncherActionKind.Perform,
                    new ResultAction.QuitApplication(processName)));
            }

            if (!isApplication)
            {
                actions.Add(Action(
                    "preview",
                    "快速预览",
                    "在 YTools 右侧显示预览",
                    "eye",
                    LauncherActionKind.Preview,
                    resourcePath));
                if (!isDirectory)
                {
                    actions.Add(Action(
                        "open-with",
                        "打开方式…",
                        "选择本机应用打开该文件",
                        "square.stack.3d.up",
                        LauncherActionKind.OpenWith,
                        resourcePath));
                }

                actions.Add(Action(
                    "copy-file",
                    "复制到…",
                    "选择本机目标目录；不会覆盖同名项目",
                    "doc.on.doc",
                    LauncherActionKind.CopyFile,
                    resourcePath));
                actions.Add(Action(
                    "move-file",
                    "移动到…",
                    "选择本机目标目录；不会覆盖同名项目",
                    "folder.badge.plus",
                    LauncherActionKind.MoveFile,
                    resourcePath));
                actions.Add(Action(
                    "trash-file",
                    "移入回收站…",
                    "需要确认；不提供永久删除",
                    "trash",
                    LauncherActionKind.Trash,
                    resourcePath));
            }
        }
        else
        {
            switch (result.Action)
            {
                case ResultAction.Copy copy:
                    actions.Add(Action(
                        "copy",
                        "复制",
                        "复制结果到剪贴板",
                        "doc.on.doc",
                        LauncherActionKind.CopyText,
                        copy.Text));
                    actions.Add(Action(
                        "large-type",
                        "大字显示",
                        "全屏清晰显示文本",
                        "textformat.size.larger",
                        LauncherActionKind.LargeType,
                        copy.Text));
                    actions.Add(Action(
                        "save-snippet",
                        "保存为文本片段",
                        "加密保存到默认分类",
                        "text.badge.plus",
                        LauncherActionKind.SaveSnippet,
                        copy.Text));
                    break;
                case ResultAction.OpenSettings:
                    actions.Add(Action(
                        "settings",
                        "打开设置",
                        result.Subtitle,
                        "gearshape",
                        LauncherActionKind.Perform,
                        new ResultAction.OpenSettings()));
                    break;
                case ResultAction.ActivateApplication activate:
                    actions.Add(Action(
                        "launch-registered-application",
                        "启动应用",
                        result.Subtitle,
                        "arrow.up.forward.app",
                        LauncherActionKind.Perform,
                        activate));
                    break;
                default:
                    if (!string.IsNullOrEmpty(result.Title))
                    {
                        actions.Add(Action(
                            "copy-title",
                            "复制标题",
                            result.Title,
                            "doc.on.doc",
                            LauncherActionKind.CopyText,
                            result.Title));
                    }

                    break;
            }
        }

        return actions;
    }

    public IReadOnlyList<LauncherAction> ActionsForBufferedPaths(IReadOnlyList<string> paths)
    {
        if (paths.Count == 0)
        {
            return [];
        }

        return
        [
            Action(
                "open-buffer",
                "打开全部",
                $"打开缓冲区中的 {paths.Count} 个项目",
                "arrow.up.forward.app",
                LauncherActionKind.OpenMany,
                paths.ToList()),
            Action(
                "reveal-buffer",
                "在资源管理器中显示",
                "在资源管理器中选择全部项目",
                "folder",
                LauncherActionKind.RevealMany,
                paths.ToList()),
            Action(
                "copy-buffer-paths",
                "复制全部路径",
                "每行一个完整路径",
                "doc.on.doc",
                LauncherActionKind.CopyPaths,
                paths.ToList())
        ];
    }

    private static LauncherAction Action(
        string id,
        string title,
        string subtitle,
        string icon,
        LauncherActionKind kind,
        object payload)
    {
        return new LauncherAction(id, title, subtitle, icon, kind, payload);
    }

    private static string NavigationQuery(string path)
    {
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var display = path.StartsWith(profile + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
            ? "~" + path[profile.Length..]
            : path;
        return display.EndsWith('\\') ? display : display + "\\";
    }
}
