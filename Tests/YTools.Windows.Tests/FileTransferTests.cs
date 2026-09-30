using System.IO;
using YTools.Core;
using YTools.Services;

namespace YTools.Windows.Tests;

public sealed class FileTransferTests
{
    [Fact]
    public async Task CancellationCleansStageAndPreservesSource()
    {
        var root = Root();
        try
        {
            var source = Path.Combine(root, "fixture.dat");
            var destination = Directory.CreateDirectory(Path.Combine(root, "destination")).FullName;
            File.WriteAllBytes(source, Enumerable.Repeat((byte)42, 2 * 1024 * 1024).ToArray());
            using var cancellation = new CancellationTokenSource();
            var received = new List<FileTransferProgress>();
            var progress = new InlineProgress(value =>
            {
                received.Add(value);
                if (value.Phase == FileTransferPhase.Copying && value.CompletedBytes > 0) { cancellation.Cancel(); }
            });
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => new FileTransferService().PerformAsync(false, source, destination, progress, cancellation.Token));
            Assert.Equal(2 * 1024 * 1024, new FileInfo(source).Length);
            Assert.Empty(Directory.GetFileSystemEntries(destination));
            Assert.Contains(received, value => value.CompletedBytes > 0 && value.CompletedBytes < value.TotalBytes);
        }
        finally { Directory.Delete(root, recursive: true); }
    }
    [Fact]
    public async Task DestinationCreatedDuringCopyCannotBeOverwritten()
    {
        var root = Root();
        try
        {
            var source = Path.Combine(root, "fixture.txt");
            var directory = Directory.CreateDirectory(Path.Combine(root, "destination")).FullName;
            var destination = Path.Combine(directory, "fixture.txt");
            File.WriteAllText(source, "source");
            var progress = new InlineProgress(value => { if (value.Phase == FileTransferPhase.Committing) { File.WriteAllText(destination, "competing-file"); } });
            await Assert.ThrowsAsync<IOException>(() => new FileTransferService().PerformAsync(false, source, directory, progress));
            Assert.Equal("source", File.ReadAllText(source));
            Assert.Equal("competing-file", File.ReadAllText(destination));
            Assert.Single(Directory.GetFileSystemEntries(directory));
        }
        finally { Directory.Delete(root, recursive: true); }
    }
    [Fact]
    public async Task DirectoryCopyAndMoveReportExactTotalBytes()
    {
        var root = Root();
        try
        {
            var source = Directory.CreateDirectory(Path.Combine(root, "source")).FullName;
            Directory.CreateDirectory(Path.Combine(source, "empty"));
            File.WriteAllBytes(Path.Combine(source, "one.dat"), new byte[23]);
            File.WriteAllBytes(Path.Combine(source, "empty", "two.dat"), new byte[45]);
            var target = Directory.CreateDirectory(Path.Combine(root, "target")).FullName;
            var moved = Directory.CreateDirectory(Path.Combine(root, "moved")).FullName;
            FileTransferProgress? latest = null;
            var progress = new InlineProgress(value => latest = value);
            var service = new FileTransferService();
            await service.PerformAsync(false, source, target, progress);
            Assert.Equal(68, latest!.TotalBytes);
            Assert.Equal(68, latest.CompletedBytes);
            Assert.Equal(100, latest.Percentage);
            await service.PerformAsync(true, source, moved, progress);
            Assert.False(Directory.Exists(source));
            Assert.Equal(45, new FileInfo(Path.Combine(moved, "source", "empty", "two.dat")).Length);
            Assert.Equal(FileTransferPhase.Completed, latest.Phase);
        }
        finally { Directory.Delete(root, recursive: true); }
    }
    private sealed class InlineProgress(Action<FileTransferProgress> report) : IProgress<FileTransferProgress>
    { public void Report(FileTransferProgress value) => report(value); }
    private static string Root()
    {
        var path = Path.Combine(Path.GetTempPath(), "ytools-transfer-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }
}
