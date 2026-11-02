using System.IO;
using System.Text;
using System.Text.Json;
using YTools.Core;
using YTools.Models;
using YTools.ModuleKit;
using YTools.Services;
using YTools.Services.Modules;
using YTools.Services.Storage;

namespace YTools.Windows.Tests;

public sealed class TranslationCoreTests
{
    [Theory]
    [InlineData("今天天气很好", TranslationLanguage.ChineseSimplified, TranslationLanguage.English, TranslationLanguage.English)]
    [InlineData("The weather is nice", TranslationLanguage.ChineseSimplified, TranslationLanguage.English, TranslationLanguage.ChineseSimplified)]
    // Mostly Chinese with an English product name stays Chinese → English.
    [InlineData("我在用 YTools 翻译", TranslationLanguage.ChineseSimplified, TranslationLanguage.English, TranslationLanguage.English)]
    // A third language goes to the primary language.
    [InlineData("Привет", TranslationLanguage.ChineseSimplified, TranslationLanguage.English, TranslationLanguage.ChineseSimplified)]
    [InlineData("こんにちは世界", TranslationLanguage.English, TranslationLanguage.Japanese, TranslationLanguage.English)]
    [InlineData("1234 !!", TranslationLanguage.ChineseSimplified, TranslationLanguage.English, TranslationLanguage.English)]
    public void DirectionFollowsLanguagePair(string text, TranslationLanguage primary, TranslationLanguage secondary, TranslationLanguage expected)
    {
        Assert.Equal(expected, TranslationDirection.Target(text, primary, secondary));
    }

    [Fact]
    public void KeywordParsing()
    {
        Assert.Equal("hello world", TranslationQuery.Parse("fy hello world", ["fy", "tr"]));
        Assert.Equal("你好", TranslationQuery.Parse("TR  你好 ", ["fy", "tr"]));
        Assert.Equal("good", TranslationQuery.Parse("翻译 good", ["翻译"]));
        Assert.Equal("", TranslationQuery.Parse("fy", ["fy"]));
        Assert.Null(TranslationQuery.Parse("fyi", ["fy"]));
        Assert.Null(TranslationQuery.Parse("safari", ["fy"]));
        Assert.Equal(TranslationQuery.MaximumCharacters, TranslationQuery.Parse("fy " + new string('a', 6_000), ["fy"])!.Length);
        Assert.Equal(new[] { "fy", "tr", "翻译" }, TranslationQuery.Keywords("fy, tr，翻译 fy"));
        Assert.Equal(new[] { "a", "b", "c", "d", "e" }, TranslationQuery.Keywords("a b c d e f toolongkeyword1"));
    }

    [Theory]
    [InlineData("https://api.openai.com/v1", TranslationApiFormat.OpenAICompatible, "https://api.openai.com/v1/chat/completions")]
    [InlineData("https://api.openai.com/v1/chat/completions", TranslationApiFormat.OpenAICompatible, "https://api.openai.com/v1/chat/completions")]
    [InlineData("  https://API.deepseek.com/v1/ ", TranslationApiFormat.OpenAICompatible, "https://api.deepseek.com/v1/chat/completions")]
    [InlineData("http://localhost:11434/v1", TranslationApiFormat.OpenAICompatible, "http://localhost:11434/v1/chat/completions")]
    [InlineData("http://127.0.0.1:8080", TranslationApiFormat.OpenAICompatible, "http://127.0.0.1:8080/chat/completions")]
    [InlineData("https://api.anthropic.com", TranslationApiFormat.Anthropic, "https://api.anthropic.com/v1/messages")]
    [InlineData("https://proxy.example.com/v1", TranslationApiFormat.Anthropic, "https://proxy.example.com/v1/messages")]
    [InlineData("https://proxy.example.com:8443/v1/messages", TranslationApiFormat.Anthropic, "https://proxy.example.com:8443/v1/messages")]
    public void EndpointPolicyBuildsRequestUrl(string raw, TranslationApiFormat format, string expected)
    {
        Assert.True(TranslationEndpointPolicy.TryCreateRequestUri(raw, format, out var url, out _));
        Assert.Equal(expected, url.AbsoluteUri);
    }

    [Theory]
    [InlineData("http://api.example.com/v1", TranslationEndpointRejection.InsecureScheme)]
    [InlineData("http://localhost.example.com/v1", TranslationEndpointRejection.InsecureScheme)]
    [InlineData("ftp://api.example.com", TranslationEndpointRejection.InsecureScheme)]
    [InlineData("file:///C:/Windows/win.ini", TranslationEndpointRejection.Invalid)]
    [InlineData("https://user:pass@api.example.com/v1", TranslationEndpointRejection.EmbeddedCredentials)]
    [InlineData("https://api.example.com/v1?key=1", TranslationEndpointRejection.QueryOrFragment)]
    [InlineData("https://api.example.com/v1#x", TranslationEndpointRejection.QueryOrFragment)]
    [InlineData("https://api.example.com/v1?", TranslationEndpointRejection.QueryOrFragment)]
    [InlineData("api.example.com", TranslationEndpointRejection.Invalid)]
    [InlineData("https://api.example.com/v 1", TranslationEndpointRejection.Invalid)]
    [InlineData("", TranslationEndpointRejection.Invalid)]
    public void EndpointPolicyRejectsUnsafeUrls(string raw, TranslationEndpointRejection expected)
    {
        Assert.False(TranslationEndpointPolicy.TryCreateRequestUri(raw, TranslationApiFormat.OpenAICompatible, out _, out var rejection));
        Assert.Equal(expected, rejection);
        Assert.False(string.IsNullOrEmpty(rejection.Message()));
    }

    [Fact]
    public void PayloadRoundTrip()
    {
        using var anthropic = JsonDocument.Parse(TranslationPayload.Body(TranslationApiFormat.Anthropic, "m", "hi", TranslationLanguage.ChineseSimplified));
        Assert.Equal("m", anthropic.RootElement.GetProperty("model").GetString());
        Assert.Contains("Simplified Chinese", anthropic.RootElement.GetProperty("system").GetString());
        Assert.Equal(4_096, anthropic.RootElement.GetProperty("max_tokens").GetInt32());
        Assert.Equal("hi", anthropic.RootElement.GetProperty("messages")[0].GetProperty("content").GetString());

        using var openAI = JsonDocument.Parse(TranslationPayload.Body(TranslationApiFormat.OpenAICompatible, "gpt", "你好", TranslationLanguage.English));
        Assert.Equal(new[] { "messages", "model", "stream", "temperature" },
            openAI.RootElement.EnumerateObject().Select(property => property.Name));
        Assert.False(openAI.RootElement.GetProperty("stream").GetBoolean());
        var messages = openAI.RootElement.GetProperty("messages");
        Assert.Equal("system", messages[0].GetProperty("role").GetString());
        Assert.Equal("你好", messages[1].GetProperty("content").GetString());

        Assert.Equal("你好", Parse("""{"choices":[{"message":{"content":" 你好\n"}}]}""", TranslationApiFormat.OpenAICompatible).Text);
        Assert.Equal("Hello world", Parse("""{"content":[{"type":"text","text":"Hello"},{"type":"tool_use"},{"type":"text","text":" world"}]}""", TranslationApiFormat.Anthropic).Text);
        var server = Parse("""{"error":{"message":"invalid key"}}""", TranslationApiFormat.OpenAICompatible).Error;
        Assert.Equal(new TranslationParseError(TranslationParseErrorKind.Server, "invalid key"), server);
        Assert.Equal(TranslationParseErrorKind.Server, Parse("""{"error":"quota"}""", TranslationApiFormat.Anthropic).Error?.Kind);
        Assert.Equal(TranslationParseErrorKind.Malformed, Parse("<html>", TranslationApiFormat.OpenAICompatible).Error?.Kind);
        Assert.Equal(TranslationParseErrorKind.Malformed, Parse("""{"choices":[{"message":"x"}]}""", TranslationApiFormat.OpenAICompatible).Error?.Kind);
        Assert.Equal(TranslationParseErrorKind.Malformed, Parse("[]", TranslationApiFormat.OpenAICompatible).Error?.Kind);
        Assert.Equal(TranslationParseErrorKind.EmptyReply, Parse("""{"content":[]}""", TranslationApiFormat.Anthropic).Error?.Kind);
        Assert.Equal("invalid key", TranslationPayload.ErrorMessage(Encoding.UTF8.GetBytes("""{"error":{"message":"invalid key"}}""")));
        Assert.Equal(300, TranslationPayload.ErrorMessage(Encoding.UTF8.GetBytes($$"""{"error":"{{new string('x', 400)}}"}"""))!.Length);
        Assert.Null(TranslationPayload.ErrorMessage(Encoding.UTF8.GetBytes("not json")));
    }

    [Fact]
    public void TranslatorActionPassesPolicy()
    {
        var policy = new ModuleResultPolicy();
        var descriptor = new ModuleDescriptor("ai-translation", "AI 翻译");
        var ok = new LauncherResult("a", "x", "t", "", new ResultIcon.System("character.bubble"), 1, new ResultAction.OpenTranslator("hello"));
        Assert.NotNull(policy.Sanitize(ok, descriptor));
        var huge = ok with { Action = new ResultAction.OpenTranslator(new string('a', 6_000)) };
        Assert.Null(policy.Sanitize(huge, descriptor));
    }

    [Fact]
    public async Task DisabledModuleOffersSetupInsteadOfTranslating()
    {
        var calls = 0;
        var module = new AITranslationModule(AITranslationSettings.Default, (_, _, _) =>
        {
            calls++;
            return Task.FromResult(new AITranslationOutput("x", TranslationLanguage.English));
        });
        var results = await module.SearchAsync(new ModuleSearchRequest("fy hello"));
        Assert.IsType<ResultAction.OpenSettings>(Assert.Single(results).Action);
        Assert.Empty(await module.SearchAsync(new ModuleSearchRequest("finder")));
        Assert.Equal(0, calls);
    }

    [Fact]
    public async Task EnabledModuleTranslatesAfterThePause()
    {
        var settings = AITranslationSettings.Default with { Enabled = true, LiveDelayMilliseconds = 200 };
        var module = new AITranslationModule(settings, (text, _, _) =>
            Task.FromResult(new AITranslationOutput(text == "hello" ? "你好" : "?", TranslationLanguage.ChineseSimplified)));

        var keywordOnly = await module.SearchAsync(new ModuleSearchRequest("fy"));
        Assert.Equal(new ResultAction.OpenTranslator(""), Assert.Single(keywordOnly).Action);

        var results = await module.SearchAsync(new ModuleSearchRequest("tr hello"));
        Assert.Equal(2, results.Count);
        Assert.Equal("你好", results[0].Title);
        Assert.Equal(new ResultAction.Copy("你好"), results[0].Action);
        Assert.Equal(new ResultAction.OpenTranslator("hello"), results[1].Action);
        var policy = new ModuleResultPolicy();
        Assert.All(results, result => Assert.NotNull(policy.Sanitize(result, module.Descriptor)));
    }

    [Fact]
    public async Task ModuleReportsFailuresAndHonoursCancellation()
    {
        var settings = AITranslationSettings.Default with { Enabled = true, LiveDelayMilliseconds = 200 };
        var failing = new AITranslationModule(settings, (_, _, _) => throw new AITranslationException("bad key"));
        var results = await failing.SearchAsync(new ModuleSearchRequest("fy hello"));
        Assert.Equal("翻译失败", results[0].Title);
        Assert.Equal("bad key", results[0].Subtitle);

        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            failing.SearchAsync(new ModuleSearchRequest("fy hello", cancellationToken: cancellation.Token)));
    }

    [Fact]
    public void SettingsNormalizeStoredValues()
    {
        var stored = JsonSerializer.Deserialize<AITranslationSettings>(
            """{"Enabled":true,"LiveDelayMilliseconds":5,"Provider":"DeepSeek"}""",
            new JsonSerializerOptions { Converters = { new System.Text.Json.Serialization.JsonStringEnumConverter() } })!.Normalized();
        Assert.True(stored.Enabled);
        Assert.Equal(200, stored.LiveDelayMilliseconds);
        Assert.Equal(AITranslationProvider.DeepSeek, stored.Provider);
        Assert.Equal(new[] { "fy", "tr", "翻译" }, stored.KeywordList);
        Assert.Equal(TranslationLanguage.ChineseSimplified, stored.PrimaryLanguage);
        Assert.Equal(TranslationLanguage.English, stored.Target("你好"));
        Assert.False(AITranslationSettings.Default.Enabled);
    }

    [Fact]
    public void ProviderPresetsAreAcceptedByTheEndpointPolicy()
    {
        foreach (var provider in Enum.GetValues<AITranslationProvider>().Where(provider => provider != AITranslationProvider.Custom))
        {
            Assert.True(TranslationEndpointPolicy.TryCreateRequestUri(provider.BaseUrl(), provider.Format(), out _, out _), provider.ToString());
            Assert.False(string.IsNullOrEmpty(provider.DefaultModel()));
        }
    }

    [Fact]
    public async Task ServiceRefusesBeforeAnyRequest()
    {
        var root = Path.Combine(Path.GetTempPath(), "ytools-translation-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var service = new AITranslationService(new SecureCodableStore(Path.Combine(root, "key.enc"), _ => new byte[32]));
            var enabled = AITranslationSettings.Default with { Enabled = true };
            var disabled = await Assert.ThrowsAsync<AITranslationException>(() => service.TranslateAsync("hello", AITranslationSettings.Default));
            Assert.Contains("尚未启用", disabled.Message);
            var insecure = await Assert.ThrowsAsync<AITranslationException>(() =>
                service.TranslateAsync("hello", enabled with { BaseUrl = "http://api.example.com/v1" }));
            Assert.Equal(TranslationEndpointRejection.InsecureScheme.Message(), insecure.Message);
            var missingKey = await Assert.ThrowsAsync<AITranslationException>(() => service.TranslateAsync("hello", enabled));
            Assert.Contains("API Key", missingKey.Message);
            Assert.Equal("", (await service.TranslateAsync("   ", enabled)).Text);

            Assert.Null(await service.SaveApiKeyAsync(" sk-test "));
            Assert.True(service.HasApiKey);
            Assert.NotNull(await service.SaveApiKeyAsync("bad\nkey"));
            Assert.Null(await service.SaveApiKeyAsync(""));
            Assert.False(service.HasApiKey);
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    private static TranslationParseResult Parse(string json, TranslationApiFormat format) =>
        TranslationPayload.Translation(Encoding.UTF8.GetBytes(json), format);
}
