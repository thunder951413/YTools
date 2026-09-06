namespace YTools.Core;

public static class SearchPublicationPolicy
{
    public static bool CanPublish(
        string currentQuery,
        string requestedQuery,
        long currentGeneration,
        long requestedGeneration,
        CancellationToken cancellationToken)
    {
        return !cancellationToken.IsCancellationRequested
            && currentGeneration == requestedGeneration
            && string.Equals(currentQuery, requestedQuery, StringComparison.Ordinal);
    }
}
