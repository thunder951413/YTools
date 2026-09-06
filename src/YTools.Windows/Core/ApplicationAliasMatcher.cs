namespace YTools.Core;

/// <summary>
/// Parses and ranks user-defined application aliases without touching the
/// filesystem, so alias matching stays in the same fast local path as names.
/// </summary>
public sealed class ApplicationAliasMatcher
{
    private static readonly char[] Separators = { ',', '，', ';', '；', '\n' };
    private readonly SearchTextNormalizer _normalizer = new();

    public IReadOnlyList<string> Aliases(string rawValue)
    {
        return rawValue
            .Split(Separators, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(alias => !string.IsNullOrEmpty(alias))
            .ToList();
    }

    public int? Score(string query, IReadOnlyList<string> aliases)
    {
        var queryForms = _normalizer.Forms(query);
        if (string.IsNullOrEmpty(queryForms.Normalized))
        {
            return null;
        }

        return aliases
            .Select(alias => Score(queryForms, alias))
            .Where(score => score is not null)
            .DefaultIfEmpty(null)
            .Max();
    }

    private int? Score(SearchTextForms query, string alias)
    {
        var candidate = _normalizer.Forms(alias);
        if (candidate.Normalized == query.Normalized)
        {
            return 960;
        }

        if (candidate.Transliteration == query.Normalized)
        {
            return 940;
        }

        if (candidate.Normalized.StartsWith(query.Normalized, StringComparison.Ordinal))
        {
            return 880;
        }

        if (candidate.Transliteration.StartsWith(query.Normalized, StringComparison.Ordinal))
        {
            return 860;
        }

        if (candidate.Abbreviation.StartsWith(query.Normalized, StringComparison.Ordinal)
            || candidate.TransliterationInitials.StartsWith(query.Normalized, StringComparison.Ordinal))
        {
            return 830;
        }

        if (candidate.Normalized.Contains(query.Normalized, StringComparison.Ordinal)
            || candidate.Transliteration.Contains(query.Normalized, StringComparison.Ordinal))
        {
            return 760;
        }

        if (query.Normalized.Length < 2)
        {
            return null;
        }

        var normalizedFuzzy = _normalizer.FuzzyScore(query.Normalized, candidate.Normalized);
        var transliteratedFuzzy = _normalizer.FuzzyScore(query.Normalized, candidate.Transliteration);
        var best = new[] { normalizedFuzzy, transliteratedFuzzy }.Where(score => score is not null).Max();
        return best is { } fuzzy ? 620 + fuzzy : null;
    }
}
