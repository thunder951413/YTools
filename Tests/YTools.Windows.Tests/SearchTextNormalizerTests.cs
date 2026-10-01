using YTools.Core;

namespace YTools.Windows.Tests;

public class SearchTextNormalizerTests
{
    private readonly SearchTextNormalizer _normalizer = new();

    [Fact]
    public void Forms_ChineseName_ProducesPinyinAndInitials()
    {
        var forms = _normalizer.Forms("微信");

        Assert.Equal("微信", forms.Normalized);
        Assert.Equal("weixin", forms.Transliteration);
        Assert.Equal("wx", forms.TransliterationInitials);
        Assert.Equal("wx", forms.Abbreviation);
    }

    [Fact]
    public void Forms_LatinMultiWord_ProducesInitials()
    {
        var forms = _normalizer.Forms("Visual Studio Code");

        Assert.Equal("vsc", forms.Abbreviation);
    }

    [Fact]
    public void Forms_LatinSingleWord_PreservesUppercaseInitials()
    {
        var forms = _normalizer.Forms("VSCode");

        Assert.Equal("vsc", forms.Abbreviation);
    }

    [Fact]
    public void Normalized_FoldsDiacriticsAndCase()
    {
        Assert.Equal("eclair", _normalizer.Normalized("Éclair"));
        Assert.Equal("abc123", _normalizer.Normalized("ABC 123"));
    }

    [Fact]
    public void FuzzyScore_SlkMatchesSlack()
    {
        var score = _normalizer.FuzzyScore("slk", "Slack");

        Assert.NotNull(score);
        Assert.InRange(score!.Value, 1, 99);
    }

    [Fact]
    public void FuzzyScore_NonContiguousCharactersFails()
    {
        Assert.Null(_normalizer.FuzzyScore("xyz", "abc"));
    }
}
