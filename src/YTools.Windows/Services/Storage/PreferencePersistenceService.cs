using System.IO;
using System.Text.Json;
using YTools.Infrastructure;

namespace YTools.Services.Storage;

/// <summary>Serializes and atomically replaces non-secret preferences on a worker.</summary>
internal sealed class PreferencePersistenceService(string path, JsonSerializerOptions options)
{
    private readonly OrderedBackgroundWriter _writer = new();
    public Task<bool> SaveAsync<T>(T snapshot, bool preserveUnreadable) => _writer.Enqueue(() =>
    {
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            if (preserveUnreadable && File.Exists(path))
            {
                var backup = path + ".unreadable-" + Guid.NewGuid().ToString("N") + ".bak";
                File.Copy(path, backup, overwrite: false);
                AppPaths.RestrictFile(backup);
            }
            var bytes = JsonSerializer.SerializeToUtf8Bytes(snapshot, options);
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { stream.Write(bytes); stream.Flush(flushToDisk: true); }
            AppPaths.RestrictFile(temporary);
            if (File.Exists(path)) { File.Replace(temporary, path, destinationBackupFileName: null); }
            else { File.Move(temporary, path); }
            return true;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
        { return false; }
        finally { try { File.Delete(temporary); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
    });
    public Task DrainAsync() => _writer.DrainAsync();
}
