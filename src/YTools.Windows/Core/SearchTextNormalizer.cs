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
        var containsNonAscii = false;
        foreach (var ch in value)
        {
            if (ch > 127)
            {
                containsNonAscii = true;
                break;
            }
        }

        if (!containsNonAscii)
        {
            var asciiInitials = ExtractAsciiAbbreviation(value);
            return new SearchTextForms(
                normalizedValue,
                asciiInitials,
                normalizedValue,
                ExtractWordInitials(value));
        }

        var latin = ToLatin(value);
        var latinInitials = ExtractWordInitials(latin);
        return new SearchTextForms(
            normalizedValue,
            latinInitials,
            Normalized(latin),
            latinInitials);
    }

    public string Normalized(string value)
    {
        var allAscii = true;
        foreach (var ch in value)
        {
            if (ch > 127)
            {
                allAscii = false;
                break;
            }
        }

        if (allAscii)
        {
            var asciiBuilder = new StringBuilder(value.Length);
            foreach (var ch in value)
            {
                if (char.IsAsciiLetterOrDigit(ch))
                {
                    asciiBuilder.Append(char.ToLowerInvariant(ch));
                }
            }

            return asciiBuilder.ToString();
        }

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
        return FuzzyScoreNormalized(Normalized(query), Normalized(candidate));
    }

    public int? FuzzyScoreNormalized(ReadOnlySpan<char> queryCharacters, ReadOnlySpan<char> candidateCharacters)
    {
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
            var relative = candidateCharacters[searchStart..].IndexOf(character);
            if (relative < 0)
            {
                return null;
            }

            var match = searchStart + relative;
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

    private string ExtractWordInitials(string value)
    {
        var initials = new StringBuilder(8);
        var inWord = false;
        foreach (var ch in value)
        {
            if (char.IsLetterOrDigit(ch))
            {
                if (!inWord)
                {
                    initials.Append(ch);
                    inWord = true;
                }
            }
            else
            {
                inWord = false;
            }
        }

        return Normalized(initials.ToString());
    }

    private string ExtractAsciiAbbreviation(string value)
    {
        var wordInitials = new StringBuilder(8);
        var wordCount = 0;
        var inWord = false;
        foreach (var ch in value)
        {
            if (char.IsLetterOrDigit(ch))
            {
                if (!inWord)
                {
                    wordInitials.Append(char.ToLowerInvariant(ch));
                    wordCount++;
                    inWord = true;
                }
            }
            else
            {
                inWord = false;
            }
        }

        if (wordCount > 1)
        {
            return wordInitials.ToString();
        }

        var camel = new StringBuilder(8);
        for (var i = 0; i < value.Length; i++)
        {
            var ch = value[i];
            if ((char.IsUpper(ch) || i == 0) && char.IsLetterOrDigit(ch))
            {
                camel.Append(char.ToLowerInvariant(ch));
            }
        }

        return camel.ToString();
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
                    if (builder.Length > 0 && builder[^1] != ' ')
                    {
                        builder.Append(' ');
                    }

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
