using System.Text;
using YTools.ModuleKit;

namespace YTools.Services.Modules;

public sealed class TextStatisticsModule : IYToolsModule
{
    public ModuleDescriptor Descriptor { get; } = new("text-statistics", "文本统计");

    public Task<IReadOnlyList<LauncherResult>> SearchAsync(ModuleSearchRequest request)
    {
        var trimmed = request.Query.Trim();
        var prefix = new[] { "stats ", "统计 ", "字数 " }
            .FirstOrDefault(candidate => trimmed.StartsWith(candidate, StringComparison.OrdinalIgnoreCase));
        if (prefix is null)
        {
            return Task.FromResult<IReadOnlyList<LauncherResult>>([]);
        }

        var text = trimmed[prefix.Length..];
        if (string.IsNullOrEmpty(text))
        {
            return Task.FromResult<IReadOnlyList<LauncherResult>>([]);
        }

        var characters = text.Length;
        var words = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
        var lines = text.Split('\n').Length;
        var bytes = Encoding.UTF8.GetByteCount(text);
        var summary = $"{characters} 字符 · {words} 词 · {lines} 行 · {bytes} 字节";
        return Task.FromResult<IReadOnlyList<LauncherResult>>(
        [
            new LauncherResult(
                $"text-statistics:{StableIdentifier(text)}",
                Descriptor.Id,
                summary,
                "本机文本统计 · 回车复制",
                new ResultIcon.System("textformat.123"),
                1_030,
                new ResultAction.Copy(summary))
        ]);
    }

    private static string StableIdentifier(string value)
    {
        ulong hash = 14_695_981_039_346_656_037;
        foreach (var b in Encoding.UTF8.GetBytes(value))
        {
            hash ^= b;
            hash *= 1_099_511_628_211;
        }

        return hash.ToString("x");
    }
}
