using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using YTools.Core;
using YTools.Models;
using YTools.Services.Storage;

namespace YTools.Services;

/// <summary>
/// Endpoint presets offered in settings. Every preset only fills the editable
/// fields; requests always go to the base URL the user saved.
/// </summary>
public enum AITranslationProvider
{
    OpenAI,
    DeepSeek,
    Qwen,
    Moonshot,
    Zhipu,
    OpenRouter,
    Anthropic,
    Ollama,
    Custom
}

public static class AITranslationProviderInfo
{
    public static string Title(this AITranslationProvider provider) => provider switch
    {
        AITranslationProvider.OpenAI => "OpenAI",
        AITranslationProvider.DeepSeek => "DeepSeek",
        AITranslationProvider.Qwen => "通义千问（阿里云百炼）",
        AITranslationProvider.Moonshot => "Kimi（Moonshot）",
        AITranslationProvider.Zhipu => "智谱 GLM",
        AITranslationProvider.OpenRouter => "OpenRouter",
        AITranslationProvider.Anthropic => "Anthropic Claude",
        AITranslationProvider.Ollama => "Ollama（本机）",
        _ => "自定义"
    };

    public static TranslationApiFormat Format(this AITranslationProvider provider) =>
        provider == AITranslationProvider.Anthropic ? TranslationApiFormat.Anthropic : TranslationApiFormat.OpenAICompatible;

    public static string BaseUrl(this AITranslationProvider provider) => provider switch
    {
        AITranslationProvider.OpenAI => "https://api.openai.com/v1",
        AITranslationProvider.DeepSeek => "https://api.deepseek.com/v1",
        AITranslationProvider.Qwen => "https://dashscope.aliyuncs.com/compatible-mode/v1",
        AITranslationProvider.Moonshot => "https://api.moonshot.cn/v1",
        AITranslationProvider.Zhipu => "https://open.bigmodel.cn/api/paas/v4",
        AITranslationProvider.OpenRouter => "https://openrouter.ai/api/v1",
        AITranslationProvider.Anthropic => "https://api.anthropic.com",
        AITranslationProvider.Ollama => "http://localhost:11434/v1",
        _ => ""
    };

    public static string DefaultModel(this AITranslationProvider provider) => provider switch
    {
        AITranslationProvider.OpenAI => "gpt-4o-mini",
        AITranslationProvider.DeepSeek => "deepseek-chat",
        AITranslationProvider.Qwen => "qwen-plus",
        AITranslationProvider.Moonshot => "moonshot-v1-8k",
        AITranslationProvider.Zhipu => "glm-4-flash",
        AITranslationProvider.OpenRouter => "openai/gpt-4o-mini",
        AITranslationProvider.Anthropic => "claude-haiku-5-5",
        AITranslationProvider.Ollama => "qwen2.5:7b",
        _ => ""
    };

    /// <summary>Local models usually run without a key.</summary>
    public static bool RequiresKey(this AITranslationProvider provider) => provider != AITranslationProvider.Ollama;
}

public sealed record AITranslationOutput(string Text, TranslationLanguage Target);

/// <summary>A translation failure with a message ready to show to the user.</summary>
public sealed class AITranslationException(string message) : Exception(message)
{
    public static AITranslationException Disabled() =>
        new("AI 翻译尚未启用，请在“设置 › AI 翻译”中开启。");

    public static AITranslationException MissingKey() =>
        new("尚未保存 API Key，请在“设置 › AI 翻译”中填写。");

    public static AITranslationException Http(int status, string? detail)
    {
        var suffix = detail is null ? "" : $"：{detail}";
        return new(status switch
        {
            401 or 403 => $"API Key 无效或没有权限（HTTP {status}）{suffix}",
            404 => $"接口地址或模型名称不存在（HTTP 404）{suffix}",
            429 => $"请求过于频繁或额度不足（HTTP 429）{suffix}",
            >= 300 and < 400 => $"接口要求重定向（HTTP {status}），已拒绝；请填写最终的接口地址。",
            _ => $"接口返回 HTTP {status}{suffix}"
        });
    }
}

/// <summary>
/// Sends translation requests to the endpoint the user configured. This is
/// the only networked code besides the Jianguoyun synchronizer: one HttpClient,
/// no redirects, no cookies, no proxy credentials, HTTPS (or loopback HTTP)
/// only, a 30 s timeout and a 2 MB reply cap.
/// </summary>
public sealed class AITranslationService
{
    private const int MaximumResponseBytes = 2_000_000;
    private const int MaximumCacheEntries = 100;

    public static AITranslationService Shared { get; } = new(new SecureCodableStore("ai-translation-credentials"));

    private sealed record Credentials(string ApiKey);

    private sealed record CacheKey(string Text, TranslationLanguage Target, string Model, Uri Url);

    private readonly SecureCodableStore _credentialStore;
    private readonly object _cacheGate = new();
    private readonly Dictionary<CacheKey, string> _cache = [];
    private readonly LinkedList<CacheKey> _cacheOrder = new();
    private readonly HttpClient _client = new(new SocketsHttpHandler
    {
        AllowAutoRedirect = false,
        UseCookies = false,
        PreAuthenticate = false,
        Credentials = null,
        AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate
    })
    {
        Timeout = TimeSpan.FromSeconds(30),
        MaxResponseContentBufferSize = MaximumResponseBytes
    };

    internal AITranslationService(SecureCodableStore credentialStore)
    {
        _credentialStore = credentialStore;
    }

    public bool HasApiKey
    {
        get
        {
            var result = _credentialStore.Load<Credentials>();
            return result.Kind == SecureStoreLoadResultKind.Loaded && !string.IsNullOrEmpty(result.Value?.ApiKey);
        }
    }

    /// <summary>Saves (or with an empty key, clears) the API key. Returns an error message.</summary>
    public Task<string?> SaveApiKeyAsync(string key) => Task.Run(() =>
    {
        var trimmed = key.Trim();
        if (trimmed.Length > 512 || trimmed.Any(char.IsControl)) { return "API Key 格式不正确。"; }
        if (!_credentialStore.Save(new Credentials(trimmed)))
        {
            return "无法加密保存 API Key，Windows 数据保护或本机存储当前不可用。";
        }

        ClearCache();
        return (string?)null;
    });

    public async Task<AITranslationOutput> TranslateAsync(
        string text,
        AITranslationSettings settings,
        TranslationLanguage? requestedTarget = null,
        CancellationToken cancellationToken = default)
    {
        if (!settings.Enabled) { throw AITranslationException.Disabled(); }
        var source = text.Trim();
        if (source.Length > TranslationQuery.MaximumCharacters) { source = source[..TranslationQuery.MaximumCharacters]; }
        var target = requestedTarget ?? settings.Target(source);
        if (source.Length == 0) { return new AITranslationOutput("", target); }
        if (!TranslationEndpointPolicy.TryCreateRequestUri(settings.BaseUrl, settings.Format, out var url, out var rejection))
        {
            throw new AITranslationException(rejection.Message());
        }

        var model = settings.Model.Trim();
        var key = new CacheKey(source, target, model, url);
        lock (_cacheGate)
        {
            if (_cache.TryGetValue(key, out var cached)) { return new AITranslationOutput(cached, target); }
        }

        var apiKey = await Task.Run(LoadApiKey, cancellationToken);
        if (apiKey.Length == 0 && settings.Provider.RequiresKey()) { throw AITranslationException.MissingKey(); }

        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new ByteArrayContent(TranslationPayload.Body(settings.Format, model, source, target))
        };
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        switch (settings.Format)
        {
            case TranslationApiFormat.Anthropic:
                request.Headers.TryAddWithoutValidation("x-api-key", apiKey);
                request.Headers.TryAddWithoutValidation("anthropic-version", "2023-06-01");
                break;
            default:
                if (apiKey.Length > 0) { request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey); }
                break;
        }

        var (status, data) = await SendAsync(request, cancellationToken);
        cancellationToken.ThrowIfCancellationRequested();
        if (status is < 200 or >= 300)
        {
            throw AITranslationException.Http(status, TranslationPayload.ErrorMessage(data));
        }

        var parsed = TranslationPayload.Translation(data, settings.Format);
        if (parsed.Error is { } error) { throw new AITranslationException(error.Message); }
        Remember(key, parsed.Text!);
        return new AITranslationOutput(parsed.Text!, target);
    }

    private async Task<(int Status, byte[] Data)> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        try
        {
            using var response = await _client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            if (response.Content.Headers.ContentLength > MaximumResponseBytes) { throw TooLarge(); }
            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var buffer = new MemoryStream();
            var chunk = new byte[16 * 1024];
            int read;
            while ((read = await stream.ReadAsync(chunk, cancellationToken)) > 0)
            {
                if (buffer.Length + read > MaximumResponseBytes) { throw TooLarge(); }
                buffer.Write(chunk, 0, read);
            }

            return ((int)response.StatusCode, buffer.ToArray());
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (TaskCanceledException)
        {
            throw new AITranslationException("翻译接口在 30 秒内没有响应。");
        }
        catch (HttpRequestException exception)
        {
            throw new AITranslationException($"无法连接翻译接口：{exception.Message}");
        }
        catch (IOException exception)
        {
            throw new AITranslationException($"读取翻译结果失败：{exception.Message}");
        }
    }

    private static AITranslationException TooLarge() => new("接口返回的内容过大，已停止读取。");

    private string LoadApiKey()
    {
        var result = _credentialStore.Load<Credentials>();
        return result.Kind == SecureStoreLoadResultKind.Loaded ? result.Value?.ApiKey ?? "" : "";
    }

    private void Remember(CacheKey key, string translation)
    {
        lock (_cacheGate)
        {
            if (!_cache.ContainsKey(key)) { _cacheOrder.AddLast(key); }
            _cache[key] = translation;
            while (_cacheOrder.Count > MaximumCacheEntries)
            {
                _cache.Remove(_cacheOrder.First!.Value);
                _cacheOrder.RemoveFirst();
            }
        }
    }

    private void ClearCache()
    {
        lock (_cacheGate)
        {
            _cache.Clear();
            _cacheOrder.Clear();
        }
    }
}
