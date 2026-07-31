using YTools.ModuleKit;

namespace YTools.Services.Modules;

public sealed class SettingsModule : IYToolsModule
{
    public ModuleDescriptor Descriptor { get; } = new("settings", "设置");

    public Task<IReadOnlyList<LauncherResult>> SearchAsync(ModuleSearchRequest request)
    {
        var term = request.Query.Trim().ToLowerInvariant();
        var keywords = new[] { "settings", "preferences", "设置", "偏好设置" };
        if (string.IsNullOrEmpty(term) || !keywords.Any(keyword => keyword.StartsWith(term) || term.StartsWith(keyword)))
        {
            return Task.FromResult<IReadOnlyList<LauncherResult>>([]);
        }

        return Task.FromResult<IReadOnlyList<LauncherResult>>(
        [
            new LauncherResult(
                "settings:open",
                Descriptor.Id,
                "YTools 设置",
                "外观、快捷键、剪贴板和隐私",
                new ResultIcon.System("gearshape.fill"),
                880,
                new ResultAction.OpenSettings())
        ]);
    }
}
