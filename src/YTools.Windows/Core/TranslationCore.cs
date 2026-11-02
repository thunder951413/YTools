using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace YTools.Core;

/// <summary>Languages offered by the AI translator. The enum name is stored in settings.</summary>
public enum TranslationLanguage
{
    ChineseSimplified,
    ChineseTraditional,
    English,
    Japanese,
    Korean,
    French,
    German,
    Spanish,
    Russian
}

internal enum TranslationScript
{
    Han,
    Kana,
    Hangul,
    Cyrillic,
    Latin
}

public static class TranslationLanguageInfo
{
    public static string Title(this TranslationLanguage language) => language switch
    {
        TranslationLanguage.ChineseSimplified => "简体中文",
        TranslationLanguage.ChineseTraditional => "繁體中文",
        TranslationLanguage.English => "English",
        TranslationLanguage.Japanese => "日本語",
        TranslationLanguage.Korean => "한국어",
        TranslationLanguage.French => "Français",
        TranslationLanguage.German => "Deutsch",
        TranslationLanguage.Spanish => "Español",
        TranslationLanguage.Russian => "Русский",
        _ => language.ToString()
    };

    /// <summary>The name used inside the model prompt.</summary>
    public static string PromptName(this TranslationLanguage language) => language switch
    {
        TranslationLanguage.ChineseSimplified => "Simplified Chinese",
        TranslationLanguage.ChineseTraditional => "Traditional Chinese",
        TranslationLanguage.English => "English",
        TranslationLanguage.Japanese => "Japanese",
        TranslationLanguage.Korean => "Korean",
        TranslationLanguage.French => "French",
        TranslationLanguage.German => "German",
        TranslationLanguage.Spanish => "Spanish",
        TranslationLanguage.Russian => "Russian",
        _ => "English"
    };

    /// <summary>Script family used by the offline direction guess.</summary>
    internal static TranslationScript Script(this TranslationLanguage language) => language switch
    {
        TranslationLanguage.ChineseSimplified or TranslationLanguage.ChineseTraditional => TranslationScript.Han,
        TranslationLanguage.Japanese => TranslationScript.Kana,
        TranslationLanguage.Korean => TranslationScript.Hangul,
        TranslationLanguage.Russian => TranslationScript.Cyrillic,
        _ => TranslationScript.Latin
    };
}

/// <summary>
/// Picks the target language for a pair: text written in the primary
/// language goes to the secondary one, anything else goes to the primary.
/// </summary>
public static class TranslationDirection
{
    public static TranslationLanguage Target(string text, TranslationLanguage primary, TranslationLanguage secondary)
    {
        if (DominantScript(text) is not { } script) { return secondary; }
        if (script == primary.Script()) { return secondary; }
        if (script == secondary.Script()) { return primary; }
        return primary;
    }

    internal static TranslationScript? DominantScript(string text)
    {
        int han = 0, kana = 0, hangul = 0, cyrillic = 0, latin = 0;
        foreach (var rune in text.EnumerateRunes())
        {
            switch (rune.Value)
            {
                case >= 0x3040 and <= 0x30FF:
                case >= 0x31F0 and <= 0x31FF:
                    kana++;
                    break;
                case >= 0x4E00 and <= 0x9FFF:
                case >= 0x3400 and <= 0x4DBF:
                case >= 0xF900 and <= 0xFAFF:
                case >= 0x20000 and <= 0x2FA1F:
                    han++;
                    break;
                case >= 0xAC00 and <= 0xD7AF:
                case >= 0x1100 and <= 0x11FF:
                case >= 0x3130 and <= 0x318F:
                    hangul++;
                    break;
                case >= 0x0400 and <= 0x04FF:
                    cyrillic++;
                    break;
                case >= 0x41 and <= 0x5A:
                case >= 0x61 and <= 0x7A:
                case >= 0xC0 and <= 0x24F:
                    latin++;
                    break;
            }
        }

        // Any kana marks Japanese even when Han characters outnumber it.
        if (kana > 0 && kana * 5 >= han) { return TranslationScript.Kana; }
        // CJK characters carry more meaning per character than Latin letters.
        (TranslationScript Script, int Weight)[] candidates =
        [
            (TranslationScript.Han, han * 3),
            (TranslationScript.Hangul, hangul * 3),
            (TranslationScript.Cyrillic, cyrillic),
            (TranslationScript.Latin, latin)
        ];
        var best = candidates[0];
        foreach (var candidate in candidates.Skip(1))
        {
            if (candidate.Weight > best.Weight) { best = candidate; }
        }

        return best.Weight > 0 ? best.Script : null;
    }
}

/// <summary>
/// <c>fy hello</c> style launcher queries. Returns the text after the keyword,
/// an empty string when only the keyword was typed, or null when no keyword matches.
/// </summary>
public static class TranslationQuery
{
    public const int MaximumCharacters = 5_000;

    public static string? Parse(string query, IReadOnlyList<string> keywords)
    {
        var trimmedLeading = query.TrimStart();
        foreach (var keyword in keywords)
        {
            if (string.IsNullOrEmpty(keyword)
                || !trimmedLeading.StartsWith(keyword, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var rest = trimmedLeading[keyword.Length..];
            if (rest.Length == 0) { return ""; }
            if (!char.IsWhiteSpace(rest[0])) { continue; }
            var text = rest.Trim();
            return text.Length > MaximumCharacters ? text[..MaximumCharacters] : text;
        }

        return null;
    }

    /// <summary>Splits a comma/space separated keyword setting into clean keywords.</summary>
    public static IReadOnlyList<string> Keywords(string setting)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        return setting
            .SplitWhere(character => character is ',' or '，' || char.IsWhiteSpace(character))
            .Where(part => part.Length is > 0 and <= 12 && seen.Add(part))
            .Take(5)
            .ToList();
    }

    private static IEnumerable<string> SplitWhere(this string value, Func<char, bool> isSeparator)
    {
        var start = 0;
        for (var index = 0; index <= value.Length; index++)
        {
            if (index < value.Length && !isSeparator(value[index])) { continue; }
            if (index > start) { yield return value[start..index]; }
            start = index + 1;
        }
    }
}

/// <summary>Wire format spoken by the configured endpoint.</summary>
public enum TranslationApiFormat
{
    /// <summary><c>POST …/chat/completions</c> (OpenAI, DeepSeek, Qwen, Moonshot, Ollama …).</summary>
    OpenAICompatible,
    /// <summary><c>POST …/v1/messages</c> (Anthropic Claude).</summary>
    Anthropic
}

public enum TranslationEndpointRejection
{
    Invalid,
    InsecureScheme,
    EmbeddedCredentials,
    QueryOrFragment
}

/// <summary>
/// Validates the user-entered base URL before any request is built.
/// HTTPS is required; plain HTTP is accepted only for a model on this PC.
/// </summary>
public static class TranslationEndpointPolicy
{
    private static readonly HashSet<string> LoopbackHosts = new(StringComparer.OrdinalIgnoreCase)
    {
        "localhost", "127.0.0.1", "::1", "[::1]"
    };

    public static string Message(this TranslationEndpointRejection rejection) => rejection switch
    {
        TranslationEndpointRejection.InsecureScheme => "接口地址必须使用 https；http 仅允许 localhost / 127.0.0.1 上的本机模型。",
        TranslationEndpointRejection.EmbeddedCredentials => "接口地址中不能包含用户名或密码，请把 API Key 填到单独的输入框。",
        TranslationEndpointRejection.QueryOrFragment => "接口地址中不能包含 ? 查询参数或 # 片段。",
        _ => "接口地址无效，请填写以 https:// 开头的完整地址。"
    };

    /// <summary>
    /// Builds the full request URL for the format, appending the standard
    /// path unless the user already entered it.
    /// </summary>
    public static bool TryCreateRequestUri(
        string raw,
        TranslationApiFormat format,
        out Uri requestUri,
        out TranslationEndpointRejection rejection)
    {
        requestUri = null!;
        rejection = TranslationEndpointRejection.Invalid;
        var trimmed = raw.Trim();
        if (trimmed.Length == 0 || trimmed.Length > 512
            || trimmed.Any(character => char.IsControl(character) || char.IsWhiteSpace(character))
            || !Uri.TryCreate(trimmed, UriKind.Absolute, out var parsed)
            || string.IsNullOrEmpty(parsed.Host))
        {
            return false;
        }

        if (!string.IsNullOrEmpty(parsed.UserInfo))
        {
            rejection = TranslationEndpointRejection.EmbeddedCredentials;
            return false;
        }

        // Checked on the raw text: an empty "?" or "#" does not show up in Uri.Query.
        if (trimmed.Contains('?') || trimmed.Contains('#'))
        {
            rejection = TranslationEndpointRejection.QueryOrFragment;
            return false;
        }

        var scheme = parsed.Scheme.ToLowerInvariant();
        if (scheme != "https" && !(scheme == "http" && LoopbackHosts.Contains(parsed.Host)))
        {
            rejection = TranslationEndpointRejection.InsecureScheme;
            return false;
        }

        var path = parsed.AbsolutePath.TrimEnd('/');
        switch (format)
        {
            case TranslationApiFormat.Anthropic:
                if (!path.EndsWith("/messages", StringComparison.Ordinal))
                {
                    path += path.EndsWith("/v1", StringComparison.Ordinal) ? "/messages" : "/v1/messages";
                }

                break;
            default:
                if (!path.EndsWith("/chat/completions", StringComparison.Ordinal)) { path += "/chat/completions"; }
                break;
        }

        var builder = new UriBuilder(scheme, parsed.Host, parsed.IsDefaultPort ? -1 : parsed.Port, path);
        requestUri = builder.Uri;
        return true;
    }
}

public enum TranslationParseErrorKind
{
    Server,
    EmptyReply,
    Malformed
}

public sealed record TranslationParseError(TranslationParseErrorKind Kind, string Detail = "")
{
    public string Message => Kind switch
    {
        TranslationParseErrorKind.Server => $"接口返回错误：{Detail}",
        TranslationParseErrorKind.EmptyReply => "接口没有返回译文。",
        _ => "无法解析接口返回的内容。"
    };
}

public readonly record struct TranslationParseResult(string? Text, TranslationParseError? Error);

/// <summary>
/// Builds request bodies and reads replies for both wire formats. Kept free
/// of networking so it can be tested offline.
/// </summary>
public static class TranslationPayload
{
    public static string SystemPrompt(TranslationLanguage target)
    {
        var name = target.PromptName();
        return $"You are a professional translation engine. Translate the user's text into {name}. "
            + "Preserve meaning, tone, line breaks, Markdown, code, numbers and proper nouns. "
            + $"If the text is already in {name}, polish it lightly instead. "
            + "Reply with the translation only: no quotes, notes, explanations or language labels.";
    }

    /// <summary>UTF-8 JSON body with keys in sorted order, matching the macOS encoder.</summary>
    public static byte[] Body(TranslationApiFormat format, string model, string text, TranslationLanguage target)
    {
        var system = SystemPrompt(target);
        JsonObject body = format == TranslationApiFormat.Anthropic
            ? new JsonObject
            {
                ["max_tokens"] = 4_096,
                ["messages"] = new JsonArray(Message("user", text)),
                ["model"] = model,
                ["system"] = system
            }
            : new JsonObject
            {
                ["messages"] = new JsonArray(Message("system", system), Message("user", text)),
                ["model"] = model,
                ["stream"] = false,
                ["temperature"] = 0.2
            };
        return Encoding.UTF8.GetBytes(body.ToJsonString());
    }

    public static TranslationParseResult Translation(ReadOnlySpan<byte> data, TranslationApiFormat format)
    {
        JsonNode? root;
        try { root = JsonNode.Parse(data.ToArray()); }
        catch (JsonException) { return Failure(TranslationParseErrorKind.Malformed); }

        if (root is not JsonObject json) { return Failure(TranslationParseErrorKind.Malformed); }
        if (ErrorMessage(json) is { } message)
        {
            return new TranslationParseResult(null, new TranslationParseError(TranslationParseErrorKind.Server, message));
        }

        string? text;
        try
        {
            text = format == TranslationApiFormat.Anthropic
                ? AnthropicText(json["content"])
                : (json["choices"] as JsonArray)?.FirstOrDefault()?["message"]?["content"] is JsonValue content
                  && content.TryGetValue<string>(out var value) ? value : null;
        }
        catch (InvalidOperationException)
        {
            text = null;
        }

        if (text is null) { return Failure(TranslationParseErrorKind.Malformed); }
        var cleaned = text.Trim();
        return cleaned.Length == 0
            ? Failure(TranslationParseErrorKind.EmptyReply)
            : new TranslationParseResult(cleaned, null);
    }

    /// <summary>Error text from a non-2xx reply, if the body carries one.</summary>
    public static string? ErrorMessage(ReadOnlySpan<byte> data)
    {
        try { return JsonNode.Parse(data.ToArray()) is JsonObject json ? ErrorMessage(json) : null; }
        catch (JsonException) { return null; }
    }

    private static string? ErrorMessage(JsonObject json)
    {
        var message = json["error"] switch
        {
            JsonObject error when error["message"] is JsonValue value && value.TryGetValue<string>(out var text) => text,
            JsonValue value when value.TryGetValue<string>(out var text) => text,
            _ => null
        };
        return message is null ? null : message.Length > 300 ? message[..300] : message;
    }

    private static string? AnthropicText(JsonNode? content)
    {
        if (content is not JsonArray blocks) { return null; }
        var builder = new StringBuilder();
        foreach (var block in blocks.OfType<JsonObject>())
        {
            if (block["type"] is JsonValue type && type.TryGetValue<string>(out var kind) && kind == "text"
                && block["text"] is JsonValue text && text.TryGetValue<string>(out var value))
            {
                builder.Append(value);
            }
        }

        return builder.ToString();
    }

    private static JsonObject Message(string role, string content) => new()
    {
        ["content"] = content,
        ["role"] = role
    };

    private static TranslationParseResult Failure(TranslationParseErrorKind kind) =>
        new(null, new TranslationParseError(kind));
}
