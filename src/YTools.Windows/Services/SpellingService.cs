using System.IO;
using System.Reflection;
using WeCantSpell.Hunspell;

namespace YTools.Services;

/// <summary>
/// Offline English spelling suggestions via the managed Hunspell port with the
/// bundled en_US dictionary. Chinese input is intentionally not checked.
/// </summary>
public sealed class SpellingService
{
    private readonly Lazy<WordList> _wordList = new(
        LoadWordList,
        LazyThreadSafetyMode.ExecutionAndPublication);

    public bool IsReady => _wordList.IsValueCreated;

    public SpellingResult Check(string word)
    {
        if (string.IsNullOrWhiteSpace(word) || word.Any(character => character >= 0x4E00 && character <= 0x9FFF))
        {
            return new SpellingResult(true, []);
        }

        var list = _wordList.Value;
        var isCorrect = list.Check(word);
        return isCorrect
            ? new SpellingResult(true, [])
            : new SpellingResult(false, list.Suggest(word).Take(8).ToList());
    }

    private static WordList LoadWordList()
    {
        var assembly = Assembly.GetExecutingAssembly();
        using var affStream = assembly.GetManifestResourceStream("YTools.Resources.en_US.aff")
            ?? throw new InvalidOperationException("拼写词典数据缺失");
        using var dicStream = assembly.GetManifestResourceStream("YTools.Resources.en_US.dic")
            ?? throw new InvalidOperationException("拼写词典数据缺失");
        try
        {
            return WordList.CreateFromStreams(dicStream, affStream);
        }
        catch (Exception exception)
        {
            throw new InvalidOperationException($"拼写词典加载失败：{exception.Message}", exception);
        }
    }
}

public sealed record SpellingResult(bool IsCorrect, IReadOnlyList<string> Suggestions);
