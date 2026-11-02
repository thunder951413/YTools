using YTools.Core;
using YTools.Models;
using YTools.ModuleKit;

namespace YTools.Services.Modules;

/// <summary>
/// <c>fy hello</c> / <c>tr 你好</c>: translates the text after the keyword
/// through the configured AI endpoint once typing pauses. The request itself is
/// made by <see cref="AITranslationService"/>; this module only shapes results.
/// </summary>
public sealed class AITranslationModule : IYToolsModule
{
    /// <summary>Typing pause plus the service's own 30 s request timeout.</summary>
    public static readonly TimeSpan SearchBudget = TimeSpan.FromSeconds(35);

    private readonly AITranslationSettings _settings;
    private readonly Func<string, AITranslationSettings, CancellationToken, Task<AITranslationOutput>> _translate;

    public AITranslationModule(
        AITranslationSettings settings,
        Func<string, AITranslationSettings, CancellationToken, Task<AITranslationOutput>>? translate = null)
    {
        _settings = settings;
        _translate = translate
            ?? ((text, current, token) => AITranslationService.Shared.TranslateAsync(text, current, cancellationToken: token));
    }

    public ModuleDescriptor Descriptor { get; } = new("ai-translation", "AI 翻译");

    public async Task<IReadOnlyList<LauncherResult>> SearchAsync(ModuleSearchRequest request)
    {
        var keywords = _settings.KeywordList;
        if (TranslationQuery.Parse(request.Query, keywords) is not { } text) { return []; }
        var keyword = keywords.FirstOrDefault() ?? "fy";
        if (!_settings.Enabled)
        {
            return [Result("setup", "AI 翻译尚未启用", $"回车打开设置，填写 API 后即可用 {keyword} 翻译",
                "gearshape", 900, new ResultAction.OpenSettings())];
        }

        if (text.Length == 0)
        {
            return [Result("window", "打开 AI 翻译窗口",
                $"或输入 {keyword} 加文字直接翻译 · {_settings.PrimaryLanguage.Title()} ⇄ {_settings.SecondaryLanguage.Title()}",
                "character.bubble", 1_100, new ResultAction.OpenTranslator(""))];
        }

        var openWindow = Result($"window:{StableId(text)}", "在翻译窗口中继续编辑", "边输入边翻译，可切换翻译方向",
            "macwindow", 1_090, new ResultAction.OpenTranslator(text));
        // Wait for a pause in typing; a new keystroke cancels this search.
        await Task.Delay(_settings.LiveDelayMilliseconds, request.CancellationToken);
        try
        {
            var output = await _translate(text, _settings, request.CancellationToken);
            request.CancellationToken.ThrowIfCancellationRequested();
            return
            [
                Result($"text:{StableId(text + output.Target)}", TitleText(output.Text),
                    $"AI 翻译 → {output.Target.Title()} · 回车复制译文",
                    "character.bubble", 1_100, new ResultAction.Copy(output.Text)),
                openWindow
            ];
        }
        catch (OperationCanceledException) when (request.CancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            var message = exception is AITranslationException ? exception.Message : $"翻译失败：{exception.Message}";
            return
            [
                Result($"error:{StableId(text)}", "翻译失败", message.Length > 300 ? message[..300] : message,
                    "exclamationmark.triangle", 1_100, new ResultAction.OpenTranslator(text)),
                openWindow
            ];
        }
    }

    private LauncherResult Result(string id, string title, string subtitle, string icon, int score, ResultAction action)
    {
        return new LauncherResult($"ai-translation:{id}", Descriptor.Id, title, subtitle,
            new ResultIcon.System(icon), score, action);
    }

    private static string TitleText(string text)
    {
        var singleLine = string.Join(' ', text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries));
        return singleLine.Length > 300 ? singleLine[..300] + "…" : singleLine;
    }

    private static string StableId(string text)
    {
        var hash = System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(text));
        return Convert.ToHexString(hash, 0, 8);
    }
}
