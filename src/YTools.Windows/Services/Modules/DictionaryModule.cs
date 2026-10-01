using System.Text.RegularExpressions;
using YTools.ModuleKit;

namespace YTools.Services.Modules;

public sealed class DictionaryModule : IYToolsModule
{
    private readonly DictionaryService _dictionary;
    private readonly bool _includeAutomaticResults;

    public DictionaryModule(DictionaryService dictionary, bool includeAutomaticResults)
    {
        _dictionary = dictionary;
        _includeAutomaticResults = includeAutomaticResults;
    }

    public ModuleDescriptor Descriptor { get; } = new("dictionary", "系统词典");

    public Task<IReadOnlyList<LauncherResult>> SearchAsync(ModuleSearchRequest request)
    {
        var parsed = ParseRequest(request.Query);
        if (parsed is null || (parsed.Value.Explicit == false && !_includeAutomaticResults))
        {
            return Task.FromResult<IReadOnlyList<LauncherResult>>([]);
        }

        // Building CC-CEDICT takes noticeably longer than the launcher input
        // budget.  Do not let an implicit Latin query such as "we" hold the
        // application result batch behind that one-time initialization.  An
        // explicit dictionary request still waits and therefore remains
        // deterministic for the user.
        if (!parsed.Value.Explicit && !_dictionary.IsReady)
        {
            _ = _dictionary.WarmAsync();
            return Task.FromResult<IReadOnlyList<LauncherResult>>([]);
        }

        var entries = _dictionary.Search(parsed.Value.Word, 8);
        var results = entries.Select(entry =>
        {
            var definition = entry.Summary;
            return new LauncherResult(
                $"dictionary:{entry.Simplified.ToLowerInvariant()}",
                Descriptor.Id,
                entry.Simplified,
                $"系统词典 · {definition}",
                new ResultIcon.System("character.book.closed"),
                parsed.Value.Explicit ? 950 : 350,
                new ResultAction.Copy(definition));
        }).Cast<LauncherResult>().ToList();

        return Task.FromResult<IReadOnlyList<LauncherResult>>(results);
    }

    private static (string Word, bool Explicit)? ParseRequest(string query)
    {
        var trimmed = query.Trim();
        var prefixes = new[] { "define ", "dict ", "词典 ", "查词 " };
        foreach (var prefix in prefixes)
        {
            if (trimmed.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                var word = trimmed[prefix.Length..].Trim();
                return string.IsNullOrEmpty(word) ? null : (word, true);
            }
        }

        var isSingleLatinWord = Regex.IsMatch(trimmed, @"^[A-Za-z][A-Za-z'-]{1,40}$");
        return isSingleLatinWord ? (trimmed, false) : null;
    }
}
