using YTools.Models;
using YTools.ModuleKit;

namespace YTools.Services.Modules;

/// <summary>
/// A fixed native allowlist. User-editable keywords select a compiled action;
/// they are never used as executable paths, shell input, URLs or arguments.
/// </summary>
public sealed class SystemCommandsModule : IYToolsModule
{
    private readonly SystemCommandConfiguration _configuration;

    public SystemCommandsModule(SystemCommandConfiguration configuration)
    {
        _configuration = configuration;
    }

    public ModuleDescriptor Descriptor { get; } = new("system-commands", "系统命令");

    public Task<IReadOnlyList<LauncherResult>> SearchAsync(ModuleSearchRequest request)
    {
        var term = request.Query.Trim().ToLowerInvariant();
        if (string.IsNullOrEmpty(term))
        {
            return Task.FromResult<IReadOnlyList<LauncherResult>>([]);
        }

        var results = Commands
            .Where(command => _configuration.Enabled.Contains(command.Id))
            .Select(command =>
            {
                var keyword = (_configuration.Keywords.TryGetValue(command.Id, out var stored)
                        ? stored
                        : command.Id.DefaultKeyword())
                    .Trim()
                    .ToLowerInvariant();
                var keywordMatches = !string.IsNullOrEmpty(keyword)
                    && (keyword.StartsWith(term) || term.StartsWith(keyword));
                var titleMatches = command.Id.Title().Contains(term, StringComparison.OrdinalIgnoreCase);
                return keywordMatches || titleMatches
                    ? command.Result.WithScore(term == keyword ? 1_300 : command.Result.Score)
                    : null;
            })
            .Where(result => result is not null)
            .Cast<LauncherResult>()
            .ToList();

        return Task.FromResult<IReadOnlyList<LauncherResult>>(results);
    }

    private IReadOnlyList<(SystemCommandID Id, LauncherResult Result)> Commands =>
    [
        (
            SystemCommandID.EmptyTrash,
            Command(
                SystemCommandID.EmptyTrash,
                "由系统清空回收站；执行前需要确认",
                "trash.slash",
                1_220,
                new ResultAction.EmptyTrash())
        ),
        (
            SystemCommandID.ShowTrash,
            Command(
                SystemCommandID.ShowTrash,
                "打开回收站；不会删除文件",
                "trash",
                1_150,
                new ResultAction.ShowTrash())
        ),
        (
            SystemCommandID.ScreenSaver,
            Command(
                SystemCommandID.ScreenSaver,
                "启动 Windows 屏幕保护程序",
                "sparkles.rectangle.stack",
                1_120,
                new ResultAction.StartScreenSaver())
        ),
        (
            SystemCommandID.SleepDisplays,
            Command(
                SystemCommandID.SleepDisplays,
                "让所有显示器立即睡眠；不会退出应用",
                "display.trianglebadge.exclamationmark",
                1_180,
                new ResultAction.SleepDisplays())
        ),
        (
            SystemCommandID.FocusSettings,
            Command(
                SystemCommandID.FocusSettings,
                "打开勿扰模式与专注模式设置",
                "moon.fill",
                1_080,
                new ResultAction.OpenFocusSettings())
        ),
        (
            SystemCommandID.AppearanceSettings,
            Command(
                SystemCommandID.AppearanceSettings,
                "打开系统深浅主题与强调色设置",
                "circle.lefthalf.filled",
                1_080,
                new ResultAction.OpenAppearanceSettings())
        )
    ];

    private static LauncherResult Command(
        SystemCommandID id,
        string subtitle,
        string icon,
        int score,
        ResultAction action)
    {
        return new LauncherResult(
            $"system:{id}",
            "system-commands",
            id.Title(),
            subtitle,
            new ResultIcon.System(icon),
            score,
            action);
    }
}
