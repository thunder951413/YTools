using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;

namespace YTools.Services;

public sealed record DictionaryEntry(
    string Traditional,
    string Simplified,
    string Pinyin,
    IReadOnlyList<string> Definitions)
{
    public string Summary
    {
        get
        {
            var compact = string.Join("；", Definitions.Take(3));
            var singleLine = Regex.Replace(compact, @"\s+", " ").Trim();
            return singleLine.Length <= 72 ? singleLine : singleLine[..72] + "…";
        }
    }
}

/// <summary>
/// Offline Chinese-English dictionary backed by the bundled CC-CEDICT data
/// (CC BY-SA 4.0). No network access; all indexes are built in memory once.
/// </summary>
public sealed class DictionaryService
{
    private readonly Lazy<DictionaryIndex> _index = new(
        BuildIndex,
        LazyThreadSafetyMode.ExecutionAndPublication);

    public bool IsReady => _index.IsValueCreated;

    public IReadOnlyList<DictionaryEntry> Search(string query, int limit)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return [];
        }

        var index = _index.Value;
        var term = query.Trim().ToLowerInvariant();
        var results = new List<DictionaryEntry>();
        var seen = new HashSet<string>();

        void AddMatches(IEnumerable<DictionaryEntry> entries)
        {
            foreach (var entry in entries)
            {
                if (seen.Add(entry.Simplified))
                {
                    results.Add(entry);
                    if (results.Count >= limit)
                    {
                        return;
                    }
                }
            }
        }

        if (term.Any(char.IsLetter) && !term.Any(IsChinese))
        {
            // Latin query: pinyin prefix first, then English word prefix.
            AddMatches(index.ByPinyin.TryGetValue(term, out var pinyinMatches) ? pinyinMatches : []);
            if (results.Count < limit)
            {
                AddMatches(SearchEnglish(index, term));
            }
        }
        else
        {
            AddMatches(index.BySimplified.TryGetValue(term, out var simplified) ? simplified : []);
            if (results.Count < limit)
            {
                AddMatches(SearchChinesePrefix(index, term));
            }
        }

        return results.Take(limit).ToList();
    }

    private static bool IsChinese(char character)
    {
        return character >= 0x4E00 && character <= 0x9FFF;
    }

    private static IEnumerable<DictionaryEntry> SearchEnglish(DictionaryIndex index, string term)
    {
        var matches = new List<DictionaryEntry>();
        foreach (var (word, entries) in index.English)
        {
            if (!word.StartsWith(term, StringComparison.Ordinal))
            {
                continue;
            }

            foreach (var entry in entries)
            {
                matches.Add(entry);
                if (matches.Count >= 20)
                {
                    return matches;
                }
            }
        }

        return matches;
    }

    private static IEnumerable<DictionaryEntry> SearchChinesePrefix(DictionaryIndex index, string term)
    {
        var matches = new List<DictionaryEntry>();
        foreach (var (key, entries) in index.BySimplified)
        {
            if (key.Length >= term.Length && key.StartsWith(term, StringComparison.Ordinal))
            {
                matches.AddRange(entries);
                if (matches.Count >= 20)
                {
                    break;
                }
            }
        }

        return matches;
    }

    private static DictionaryIndex BuildIndex()
    {
        var assembly = Assembly.GetExecutingAssembly();
        using var stream = assembly.GetManifestResourceStream("YTools.Resources.cedict_ts.u8")
            ?? throw new InvalidOperationException("词典数据缺失");
        using var reader = new StreamReader(stream, Encoding.UTF8);
        var bySimplified = new Dictionary<string, List<DictionaryEntry>>();
        var byPinyin = new Dictionary<string, List<DictionaryEntry>>();
        var english = new Dictionary<string, List<DictionaryEntry>>();

        while (reader.ReadLine() is { } line)
        {
            if (line.Length == 0 || line[0] == '#')
            {
                continue;
            }

            var entry = ParseLine(line);
            if (entry is null)
            {
                continue;
            }

            Add(bySimplified, entry.Simplified, entry);
            Add(byPinyin, NormalizePinyin(entry.Pinyin), entry);
            foreach (var word in EnglishWords(entry))
            {
                Add(english, word, entry);
            }
        }

        return new DictionaryIndex(bySimplified, byPinyin, english);
    }

    private static DictionaryEntry? ParseLine(string line)
    {
        var separator = line.IndexOf(' ');
        if (separator <= 0)
        {
            return null;
        }

        var traditional = line[..separator];
        var rest = line[(separator + 1)..];
        var secondSeparator = rest.IndexOf(' ');
        if (secondSeparator <= 0)
        {
            return null;
        }

        var simplified = rest[..secondSeparator];
        rest = rest[(secondSeparator + 1)..];
        if (!rest.StartsWith('['))
        {
            return null;
        }

        var bracketEnd = rest.IndexOf(']');
        if (bracketEnd < 0)
        {
            return null;
        }

        var pinyin = rest[1..bracketEnd];
        var definitions = rest[(bracketEnd + 1)..]
            .Split('/', StringSplitOptions.RemoveEmptyEntries)
            .Select(definition => definition.Trim())
            .Where(definition => !string.IsNullOrEmpty(definition))
            .ToList();
        if (definitions.Count == 0)
        {
            return null;
        }

        return new DictionaryEntry(traditional, simplified, pinyin, definitions);
    }

    private static IEnumerable<string> EnglishWords(DictionaryEntry entry)
    {
        var words = new HashSet<string>();
        foreach (var definition in entry.Definitions)
        {
            foreach (var match in Regex.Matches(definition, @"[A-Za-z][A-Za-z'\-]{1,39}").Cast<Match>())
            {
                var word = match.Value.ToLowerInvariant();
                if (word.Length >= 2 && word.Length <= 40)
                {
                    words.Add(word);
                }
            }
        }

        return words;
    }

    private static string NormalizePinyin(string pinyin)
    {
        return Regex.Replace(pinyin, @"[\s\d]", "").ToLowerInvariant();
    }

    private static void Add(Dictionary<string, List<DictionaryEntry>> index, string key, DictionaryEntry entry)
    {
        if (string.IsNullOrEmpty(key))
        {
            return;
        }

        if (!index.TryGetValue(key, out var list))
        {
            list = [];
            index[key] = list;
        }

        list.Add(entry);
    }

    private sealed record DictionaryIndex(
        IReadOnlyDictionary<string, List<DictionaryEntry>> BySimplified,
        IReadOnlyDictionary<string, List<DictionaryEntry>> ByPinyin,
        IReadOnlyDictionary<string, List<DictionaryEntry>> English);
}
