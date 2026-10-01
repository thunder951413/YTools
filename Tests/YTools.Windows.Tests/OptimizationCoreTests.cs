using YTools.Core;

namespace YTools.Windows.Tests;

public sealed class OptimizationCoreTests
{
    [Fact]
    public void BatchBudgetHonorsCountAndBytesWithoutOverflow()
    {
        Assert.True(CloudBatchBudget.CanInclude(49, CloudBatchBudget.MaximumBytes - 100, 100));
        Assert.False(CloudBatchBudget.CanInclude(50, 0, 1));
        Assert.False(CloudBatchBudget.CanInclude(49, CloudBatchBudget.MaximumBytes - 100, 101));
        Assert.False(CloudBatchBudget.CanInclude(0, int.MaxValue, int.MaxValue));
    }
    [Fact]
    public void DiagnosticsRejectsVersionContentAndContainsOnlyFixedState()
    {
        var report = LocalDiagnosticReport.Text("secret-user-content", DiagnosticPlatform.Windows, DiagnosticFileBackend.FileNameScan,
            -1, 2, 3, true, false, true, true, false);
        Assert.DoesNotContain("secret-user-content", report);
        Assert.Contains("剪贴板记录：0", report);
        Assert.Contains("剪贴板存储：需处理", report);
        Assert.DoesNotContain("http", report);
    }
    [Fact]
    public void TransferProgressAccountsForEmptyDirectories()
    {
        Assert.Equal(50, new FileTransferProgress(20, 40, FileTransferPhase.Copying).Percentage);
        Assert.Equal(100, new FileTransferProgress(50, 40, FileTransferPhase.Copying).Percentage);
        Assert.Equal(100, new FileTransferProgress(0, 0, FileTransferPhase.Completed).Percentage);
    }
}
