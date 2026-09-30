using System.IO;
using YTools.Core;

namespace YTools.Services;

public sealed class FileTransferService
{
    private sealed record Entry(string Path, string RelativePath, bool Directory, long Size, DateTime Modified, DateTime Created, FileAttributes Attributes);
    public Task PerformAsync(bool move, string source, string destinationDirectory,
        IProgress<FileTransferProgress>? progress = null, CancellationToken cancellationToken = default) =>
        Task.Run(() => PerformOnWorkerAsync(move, source, destinationDirectory, progress, cancellationToken), cancellationToken);

    private static async Task PerformOnWorkerAsync(bool move, string source, string directory,
        IProgress<FileTransferProgress>? progress, CancellationToken token)
    {
        if (!LocalPathPolicy.TryNormalize(source, out source) || !LocalPathPolicy.TryNormalize(directory, out directory)
            || !Directory.Exists(directory)) { throw new IOException("只允许使用本机磁盘上的完整绝对路径。"); }
        RejectReparseAncestors(source);
        RejectReparseAncestors(directory);
        var destination = Path.Combine(directory, Path.GetFileName(source));
        if (Exists(destination)) { throw new IOException("目标已存在，未覆盖任何文件。"); }
        if (Directory.Exists(source) && (directory.Equals(source, StringComparison.OrdinalIgnoreCase)
            || directory.StartsWith(source.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)))
        { throw new IOException("目标目录不能位于源目录内部。"); }
        progress?.Report(new(0, 0, FileTransferPhase.Scanning));
        var entries = Plan(source, token);
        var total = entries.Sum(entry => entry.Size);
        token.ThrowIfCancellationRequested();
        if (move && string.Equals(Path.GetPathRoot(source), Path.GetPathRoot(directory), StringComparison.OrdinalIgnoreCase))
        {
            progress?.Report(new(0, total, FileTransferPhase.Committing));
            token.ThrowIfCancellationRequested();
            Commit(source, destination, entries[0].Directory);
            progress?.Report(new(total, total, FileTransferPhase.Completed));
            return;
        }
        var stage = Path.Combine(directory, ".ytools-transfer-" + Guid.NewGuid().ToString("N"));
        try
        {
            long completed = 0;
            var lastProgress = System.Diagnostics.Stopwatch.StartNew();
            foreach (var entry in entries)
            {
                token.ThrowIfCancellationRequested();
                var output = entry.RelativePath.Length == 0 ? stage : Path.Combine(stage, entry.RelativePath);
                if (entry.Directory) { Directory.CreateDirectory(output); continue; }
                {
                await using var input = new FileStream(entry.Path, FileMode.Open, FileAccess.Read, FileShare.Read, 262_144, FileOptions.Asynchronous | FileOptions.SequentialScan);
                await using var writer = new FileStream(output, FileMode.CreateNew, FileAccess.Write, FileShare.None, 262_144, FileOptions.Asynchronous | FileOptions.SequentialScan);
                var buffer = new byte[262_144];
                long written = 0;
                int count;
                while ((count = await input.ReadAsync(buffer, token).ConfigureAwait(false)) > 0)
                {
                    await writer.WriteAsync(buffer.AsMemory(0, count), token).ConfigureAwait(false);
                    written += count;
                    completed += count;
                    if (completed == count || lastProgress.ElapsedMilliseconds >= 100 || completed >= total)
                    { progress?.Report(new(completed, total, FileTransferPhase.Copying)); lastProgress.Restart(); }
                }
                await writer.FlushAsync(token).ConfigureAwait(false);
                writer.Flush(flushToDisk: true);
                if (written != entry.Size) { throw ChangedSource(); }
                }
                File.SetLastWriteTimeUtc(output, entry.Modified);
                File.SetCreationTimeUtc(output, entry.Created);
            }
            token.ThrowIfCancellationRequested();
            var current = Plan(source, token);
            var previous = entries.ToDictionary(entry => entry.RelativePath, StringComparer.OrdinalIgnoreCase);
            if (current.Count != entries.Count || current.Any(entry => !previous.TryGetValue(entry.RelativePath, out var old)
                || entry.Directory != old.Directory || entry.Size != old.Size || entry.Modified != old.Modified)) { throw ChangedSource(); }
            foreach (var entry in entries.AsEnumerable().Reverse())
            {
                var output = entry.RelativePath.Length == 0 ? stage : Path.Combine(stage, entry.RelativePath);
                if (entry.Directory) { Directory.SetLastWriteTimeUtc(output, entry.Modified); Directory.SetCreationTimeUtc(output, entry.Created); }
                var attributes = entry.Attributes & (FileAttributes.ReadOnly | FileAttributes.Hidden | FileAttributes.System | FileAttributes.Archive | FileAttributes.NotContentIndexed);
                File.SetAttributes(output, attributes == 0 ? FileAttributes.Normal : attributes);
            }
            progress?.Report(new(completed, total, FileTransferPhase.Committing));
            token.ThrowIfCancellationRequested();
            Commit(stage, destination, entries[0].Directory);
            // After commit the complete target is retained, even if removing the source fails.
            if (move) { if (entries[0].Directory) { Directory.Delete(source, recursive: true); } else { File.Delete(source); } }
            progress?.Report(new(total, total, FileTransferPhase.Completed));
        }
        finally
        {
            if (Directory.Exists(stage))
            {
                foreach (var file in Directory.EnumerateFiles(stage, "*", SearchOption.AllDirectories))
                { File.SetAttributes(file, File.GetAttributes(file) & ~FileAttributes.ReadOnly); }
                foreach (var child in Directory.EnumerateDirectories(stage, "*", SearchOption.AllDirectories))
                { File.SetAttributes(child, File.GetAttributes(child) & ~FileAttributes.ReadOnly); }
                File.SetAttributes(stage, File.GetAttributes(stage) & ~FileAttributes.ReadOnly);
                Directory.Delete(stage, recursive: true);
            }
            else if (File.Exists(stage)) { File.SetAttributes(stage, File.GetAttributes(stage) & ~FileAttributes.ReadOnly); File.Delete(stage); }
        }
    }
    private static List<Entry> Plan(string source, CancellationToken token)
    {
        var result = new List<Entry>();
        void Visit(string path)
        {
            token.ThrowIfCancellationRequested();
            var attributes = File.GetAttributes(path);
            if ((attributes & FileAttributes.ReparsePoint) != 0) { throw new IOException("文件传输不跟随符号链接或目录联接。"); }
            var directory = (attributes & FileAttributes.Directory) != 0;
            var info = directory ? (FileSystemInfo)new DirectoryInfo(path) : new FileInfo(path);
            result.Add(new(path, path == source ? "" : Path.GetRelativePath(source, path), directory,
                directory ? 0 : ((FileInfo)info).Length, info.LastWriteTimeUtc, info.CreationTimeUtc, attributes));
            if (directory) { foreach (var child in Directory.EnumerateFileSystemEntries(path)) { Visit(child); } }
        }
        Visit(source);
        return result;
    }
    private static void RejectReparseAncestors(string path)
    {
        for (var current = path; !string.IsNullOrEmpty(current); current = Path.GetDirectoryName(current))
        {
            if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
            { throw new IOException("文件传输不跟随符号链接或目录联接。"); }
        }
    }
    private static bool Exists(string path) { try { _ = File.GetAttributes(path); return true; } catch (FileNotFoundException) { return false; } catch (DirectoryNotFoundException) { return false; } }
    private static IOException ChangedSource() => new("源项目在传输中发生变化，请重试；源文件未删除。");
    private static void Commit(string source, string destination, bool directory)
    { if (directory) { Directory.Move(source, destination); } else { File.Move(source, destination, overwrite: false); } }
}
