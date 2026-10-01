namespace YTools.Core;

public readonly struct ClipboardTextPolicy
{
    public ClipboardTextPolicy(int maximumCharacters)
    {
        MaximumCharacters = Math.Max(1, maximumCharacters);
    }

    public int MaximumCharacters { get; }

    public bool ShouldStore(string text)
    {
        return !string.IsNullOrEmpty(text) && text.Length <= MaximumCharacters;
    }
}
