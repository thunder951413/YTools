namespace YTools.Core;

public enum FileTransferPhase { Scanning, Copying, Committing, Completed }
public sealed record FileTransferProgress(long CompletedBytes, long TotalBytes, FileTransferPhase Phase)
{
    public int Percentage => TotalBytes > 0 ? (int)Math.Clamp((double)CompletedBytes / TotalBytes * 100, 0, 100) : Phase == FileTransferPhase.Completed ? 100 : 0;
    public string Detail => Phase switch
    {
        FileTransferPhase.Scanning => "正在统计文件…",
        FileTransferPhase.Committing => "正在提交文件…",
        FileTransferPhase.Completed => "已完成",
        _ => $"{Percentage}% · {FormatBytes(CompletedBytes)} / {FormatBytes(TotalBytes)}"
    };
    private static string FormatBytes(long value) => value switch
    {
        >= 1_073_741_824 => $"{value / 1_073_741_824d:0.0} GB",
        >= 1_048_576 => $"{value / 1_048_576d:0.0} MB",
        >= 1024 => $"{value / 1024d:0.0} KB",
        _ => $"{value} B"
    };
}
