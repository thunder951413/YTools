using System.Globalization;
using System.Text;
using TinyPinyin;

namespace YTools.Core;

public readonly record struct SearchTextForms(
    string Normalized,
    string Abbreviation,
    string Transliteration,
    string TransliterationInitials);

/// <summary>
/// Port of the macOS SearchTextNormalizer. Chinese text is transliterated to
/// pinyin with TinyPinyin; Latin text is case/diacritic folded with the
/// invariant culture so ranking is stable across system locales.
/// </summary>
public sealed class SearchTextNormalizer
{
    public SearchTextForms Forms(string value)
    {
        var normalizedValue = Normalized(value);
        var latin = ToLatin(value);
        var latinWords = SplitWords(latin);
        var latinInitials = Normalized(string.Concat(latinWords.Select(word => word[0])));
        var nativeWords = SplitWords(value);
        var wordInitials = nativeWords.Select(word => word[0]);

        string nativeAbbreviation;
        if (nativeWords.Count > 1)
        {
            nativeAbbreviation = Normalized(string.Concat(wordInitials));
        }
        else
        {
            nativeAbbreviation = Normalized(string.Concat(
                value.Select((character, index) => char.IsUpper(character) || index == 0 ? character.ToString() : "")));
        }

        var containsNonASCII = value.Any(character => character > 127);
        return new SearchTextForms(
            normalizedValue,
            containsNonASCII ? latinInitials : nativeAbbreviation,
            Normalized(latin),
            latinInitials);
    }

    public string Normalized(string value)
    {
        var decomposed = value.Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(decomposed.Length);
        foreach (var character in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(character) == UnicodeCategory.NonSpacingMark)
            {
                continue;
            }

            if (char.IsLetterOrDigit(character))
            {
                builder.Append(char.ToLowerInvariant(character));
            }
        }

        return builder.ToString();
    }

    /// <summary>
    /// Scores an ordered, non-contiguous match such as `slk` → `Slack`.
    /// Prefix and substring matches should still be ranked separately by callers.
    /// </summary>
    public int? FuzzyScore(string query, string candidate)
    {
        var queryCharacters = Normalized(query).ToCharArray();
        var candidateCharacters = Normalized(candidate).ToCharArray();
        if (queryCharacters.Length == 0 || queryCharacters.Length > candidateCharacters.Length)
        {
            return null;
        }

        var searchStart = 0;
        int? previousMatch = null;
        int? firstMatch = null;
        var score = 0;

        foreach (var character in queryCharacters)
        {
            var match = Array.IndexOf(candidateCharacters, character, searchStart);
            if (match < 0)
            {
                return null;
            }

            firstMatch ??= match;
            score += 12;
            if (previousMatch is { } previous)
            {
                var gap = match - previous - 1;
                score += gap == 0 ? 8 : -Math.Min(gap * 2, 12);
            }

            previousMatch = match;
            searchStart = match + 1;
        }

        var coverage = queryCharacters.Length * 30 / candidateCharacters.Length;
        var startPenalty = Math.Min((firstMatch ?? 0) * 2, 20);
        return Math.Max(1, Math.Min(99, score + coverage - startPenalty));
    }

    private static List<string> SplitWords(string value)
    {
        var words = new List<string>();
        var current = new StringBuilder();
        foreach (var character in value)
        {
            if (char.IsLetterOrDigit(character))
            {
                current.Append(character);
            }
            else if (current.Length > 0)
            {
                words.Add(current.ToString());
                current.Clear();
            }
        }

        if (current.Length > 0)
        {
            words.Add(current.ToString());
        }

        return words;
    }

    private static string ToLatin(string value)
    {
        var builder = new StringBuilder(value.Length + 8);
        foreach (var character in value)
        {
            if (character <= 127)
            {
                if (char.IsLetterOrDigit(character))
                {
                    builder.Append(character);
                }
                else
                {
                    builder.Append(' ');
                }

                continue;
            }

            if (PinyinHelper.IsChinese(character))
            {
                var pinyin = PinyinHelper.GetPinyin(character);
                if (!string.IsNullOrEmpty(pinyin))
                {
                    builder.Append(pinyin);
                    builder.Append(' ');
                }
                else
                {
                    builder.Append(' ');
                }

                continue;
            }

            builder.Append(char.IsLetterOrDigit(character) ? character : ' ');
        }

        return builder.ToString();
    }
}
