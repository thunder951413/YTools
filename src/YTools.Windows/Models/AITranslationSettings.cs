using System.Text.Json.Serialization;
using YTools.Core;
using YTools.Services;

namespace YTools.Models;

/// <summary>
/// Optional AI translation through an API the user configures. Off until the
/// user enables it and saves a key; the key itself lives in the encrypted vault.
/// </summary>
public sealed record AITranslationSettings
{
    public const int MinimumLiveDelayMilliseconds = 200;
    public const int MaximumLiveDelayMilliseconds = 3_000;

    public bool Enabled { get; init; }
    public AITranslationProvider Provider { get; init; } = AITranslationProvider.OpenAI;
    public TranslationApiFormat Format { get; init; } = TranslationApiFormat.OpenAICompatible;
    public string BaseUrl { get; init; } = AITranslationProvider.OpenAI.BaseUrl();
    public string Model { get; init; } = AITranslationProvider.OpenAI.DefaultModel();
    public TranslationLanguage PrimaryLanguage { get; init; } = TranslationLanguage.ChineseSimplified;
    public TranslationLanguage SecondaryLanguage { get; init; } = TranslationLanguage.English;
    /// <summary>Launcher keywords, comma separated: <c>fy hello</c>.</summary>
    public string Keywords { get; init; } = "fy, tr, 翻译";
    /// <summary>Pause after typing before a request is sent.</summary>
    public int LiveDelayMilliseconds { get; init; } = 600;

    public static AITranslationSettings Default { get; } = new();

    [JsonIgnore]
    public IReadOnlyList<string> KeywordList => TranslationQuery.Keywords(Keywords);

    public TranslationLanguage Target(string text) =>
        TranslationDirection.Target(text, PrimaryLanguage, SecondaryLanguage);

    /// <summary>Clamps values read from disk or typed in settings.</summary>
    public AITranslationSettings Normalized()
    {
        return this with
        {
            Provider = Enum.IsDefined(Provider) ? Provider : AITranslationProvider.Custom,
            Format = Enum.IsDefined(Format) ? Format : TranslationApiFormat.OpenAICompatible,
            BaseUrl = Truncate((BaseUrl ?? "").Trim(), 512),
            Model = Truncate((Model ?? "").Trim(), 200),
            PrimaryLanguage = Enum.IsDefined(PrimaryLanguage) ? PrimaryLanguage : TranslationLanguage.ChineseSimplified,
            SecondaryLanguage = Enum.IsDefined(SecondaryLanguage) ? SecondaryLanguage : TranslationLanguage.English,
            Keywords = Truncate(Keywords ?? Default.Keywords, 100),
            LiveDelayMilliseconds = Math.Clamp(LiveDelayMilliseconds, MinimumLiveDelayMilliseconds, MaximumLiveDelayMilliseconds)
        };
    }

    private static string Truncate(string value, int length) => value.Length > length ? value[..length] : value;
}
