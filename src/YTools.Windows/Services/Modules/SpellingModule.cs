using YTools.ModuleKit;

namespace YTools.Services.Modules;

public sealed class SpellingModule : IYToolsModule
{
    private readonly SpellingService _spelling;

    public SpellingModule(SpellingService spelling)
    {
        _spelling = spelling;
    }

    public ModuleDescriptor Descriptor { get; } = new("spelling", "拼写检查");

    public Task<IReadOnlyList<LauncherResult>> SearchAsync(ModuleSearchRequest request)
    {
        var trimmed = request.Query.Trim();
        var prefixes = new[] { "spell", "拼写" };
        var prefix = prefixes.FirstOrDefault(candidate =>
            trimmed.StartsWith(candidate + " ", StringComparison.OrdinalIgnoreCase));
        if (prefix is null)
        {
            return Task.FromResult<IReadOnlyList<LauncherResult>>([]);
        }

        var word = trimmed[prefix.Length..].Trim();
        if (string.IsNullOrEmpty(word))
        {
            return Task.FromResult<IReadOnlyList<LauncherResult>>([]);
        }

        var outcome = _spelling.Check(word);
        if (outcome.IsCorrect)
        {
            return Task.FromResult<IReadOnlyList<LauncherResult>>(
            [
                new LauncherResult(
                    $"spelling:correct:{word}",
                    Descriptor.Id,
                    word,
                    "拼写正确 · 回车复制",
                    new ResultIcon.System("checkmark.seal"),
                    1_050,
                    new ResultAction.Copy(word))
            ]);
        }

        var results = outcome.Suggestions.Select((suggestion, index) =>
            new LauncherResult(
                $"spelling:{word}:{suggestion}",
                Descriptor.Id,
                suggestion,
                $"“{word}” 的拼写建议 · 回车复制",
                new ResultIcon.System("textformat.abc.dottedunderline"),
                1_050 - index,
                new ResultAction.Copy(suggestion))).Cast<LauncherResult>().ToList();
        return Task.FromResult<IReadOnlyList<LauncherResult>>(results);
    }
}
