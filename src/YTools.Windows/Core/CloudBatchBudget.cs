namespace YTools.Core;

public static class CloudBatchBudget
{
    public const int MaximumUploadEvents = 50;
    public const int MaximumPullEvents = 200;
    public const int MaximumBytes = 16 * 1024 * 1024;
    public static bool CanInclude(int count, int bytes, int nextBytes, int eventLimit = MaximumUploadEvents) =>
        count >= 0 && count < eventLimit && bytes >= 0 && bytes <= MaximumBytes && nextBytes >= 0 && nextBytes <= MaximumBytes - bytes;
}
