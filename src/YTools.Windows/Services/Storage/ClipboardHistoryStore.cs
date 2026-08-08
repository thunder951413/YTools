using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using YTools.Infrastructure;
using YTools.Models;

namespace YTools.Services.Storage;

public enum ClipboardStoreLoadResultKind
{
    Missing,
    Loaded,
    Unavailable,
    Corrupted
}

public sealed record ClipboardStoreLoadResult(
    ClipboardStoreLoadResultKind Kind,
    IReadOnlyList<ClipboardHistoryItem>? Items,
    string? Warning)
{
    public static ClipboardStoreLoadResult Missing() =>
        new(ClipboardStoreLoadResultKind.Missing, null, null);

    public static ClipboardStoreLoadResult Loaded(IReadOnlyList<ClipboardHistoryItem> items, string? warning) =>
        new(ClipboardStoreLoadResultKind.Loaded, items, warning);

    public static ClipboardStoreLoadResult Unavailable(string message) =>
        new(ClipboardStoreLoadResultKind.Unavailable, null, message);

    public static ClipboardStoreLoadResult Corrupted(string message) =>
        new(ClipboardStoreLoadResultKind.Corrupted, null, message);
}

/// <summary>
/// Incremental encrypted clipboard vault: a small manifest plus independently
/// encrypted immutable record payloads and image thumbnails.
/// </summary>
public sealed class ClipboardHistoryStore
{
    private const int MaximumEncryptedBytes = 200 * 1024 * 1024;

    private readonly string _vaultDirectory;
    private readonly string _manifestFile;
    private readonly string _recordsDirectory;
    private readonly string _thumbnailsDirectory;

    public ClipboardHistoryStore()
    {
        AppPaths.EnsureDirectories();
        _vaultDirectory = Path.Combine(AppPaths.VaultDirectory, "clipboard-vault-v2");
        _manifestFile = Path.Combine(_vaultDirectory, "manifest.enc");
        _recordsDirectory = Path.Combine(_vaultDirectory, "records");
        _thumbnailsDirectory = Path.Combine(_vaultDirectory, "thumbnails");
        Directory.CreateDirectory(_vaultDirectory);
        Directory.CreateDirectory(_recordsDirectory);
        Directory.CreateDirectory(_thumbnailsDirectory);
    }

    public ClipboardStoreLoadResult Load()
    {
        if (!File.Exists(_manifestFile))
        {
            return ClipboardStoreLoadResult.Missing();
        }

        byte[] key;
        try
        {
            key = DpapiKeyAccessor.Key(createIfMissing: false);
        }
        catch (Exception exception)
        {
            return ClipboardStoreLoadResult.Unavailable(exception.Message);
        }

        Manifest manifest;
        try
        {
            var encrypted = File.ReadAllBytes(_manifestFile);
            var clear = AesGcmBox.Open(encrypted, key);
            manifest = JsonSerializer.Deserialize<Manifest>(clear)
                ?? throw new InvalidDataException("清单为空");
            if (manifest.Version != 2)
            {
                return ClipboardStoreLoadResult.Corrupted(
                    $"不支持的剪贴板存储版本：{manifest.Version}");
            }
        }
        catch (Exception exception)
        {
            return ClipboardStoreLoadResult.Corrupted(
                $"剪贴板清单验证失败；原文件未被覆盖：{exception.Message}");
        }

        var items = new List<ClipboardHistoryItem>();
        var skipped = 0;
        foreach (var entry in manifest.Entries)
        {
            try
            {
                IReadOnlyList<string> payload;
                byte[]? thumbnail = null;
                switch (entry.Kind)
                {
                    case ClipboardItemKind.Image:
                        payload = [entry.DisplayText];
                        thumbnail = LoadThumbnail(entry.Id, key);
                        break;
                    case ClipboardItemKind.Text:
                    case ClipboardItemKind.Files:
                        var encrypted = File.ReadAllBytes(RecordFile(entry.Id));
                        var clear = AesGcmBox.Open(encrypted, key);
                        var record = JsonSerializer.Deserialize<Record>(clear)
                            ?? throw new InvalidDataException("记录为空");
                        payload = record.Payload;
                        break;
                    default:
                        throw new InvalidDataException("未知记录类型");
                }

                items.Add(new ClipboardHistoryItem(
                    entry.Id,
                    entry.Kind,
                    payload,
                    entry.CreatedAt,
                    entry.SourceApplication,
                    thumbnail,
                    entry.ContentHash,
                    entry.IsPinned,
                    entry.UpdatedAt,
                    Math.Max(1, entry.CopyCount)));
            }
            catch
            {
                skipped += 1;
            }
        }

        var warning = skipped == 0 ? null : $"有 {skipped} 条剪贴板记录损坏，已跳过但未覆盖原密文。";
        return ClipboardStoreLoadResult.Loaded(items, warning);
    }

    public List<ClipboardHistoryItem> Persist(
        IReadOnlyList<ClipboardHistoryItem> requestedItems,
        IReadOnlyDictionary<Guid, byte[]> originalImages)
    {
        var key = DpapiKeyAccessor.Key(createIfMissing: true);
        var existing = CurrentManifest(key);
        var existingById = existing.Entries.ToDictionary(entry => entry.Id);
        var candidateEntries = new List<Entry>();
        var normalizedById = new Dictionary<Guid, ClipboardHistoryItem>();
        var newlyWrittenIds = new HashSet<Guid>();

        try
        {
            foreach (var item in requestedItems)
            {
                if (existingById.TryGetValue(item.Id, out var old))
                {
                    candidateEntries.Add(new Entry(
                        old.Id,
                        old.Kind,
                        item.DisplayText,
                        old.CreatedAt,
                        item.SourceApplication,
                        item.ContentHash ?? old.ContentHash,
                        old.EncryptedByteCount,
                        item.IsPinned,
                        item.UpdatedAt ?? old.UpdatedAt,
                        Math.Max(1, item.CopyCount)));
                    normalizedById[item.Id] = item;
                    continue;
                }

                var originalImage = item.Kind == ClipboardItemKind.Image
                    ? (originalImages.TryGetValue(item.Id, out var image) ? image : item.BinaryData)
                    : null;
                var record = new Record(item.Payload.ToList(), originalImage);
                var clear = JsonSerializer.SerializeToUtf8Bytes(record);
                var encrypted = AesGcmBox.Seal(clear, key);
                WriteProtected(encrypted, RecordFile(item.Id));
                newlyWrittenIds.Add(item.Id);

                var normalized = item;
                byte[]? thumbnail = null;
                if (item.Kind == ClipboardItemKind.Image && originalImage is not null)
                {
                    thumbnail = MakeThumbnail(originalImage);
                    if (thumbnail is { Length: > 0 })
                    {
                        WriteProtected(AesGcmBox.Seal(thumbnail, key), ThumbnailFile(item.Id));
                    }

                    normalized = item with { BinaryData = thumbnail is { Length: > 0 } ? thumbnail : null };
                }

                normalizedById[item.Id] = normalized;
                candidateEntries.Add(new Entry(
                    item.Id,
                    item.Kind,
                    item.DisplayText,
                    item.CreatedAt,
                    item.SourceApplication,
                    item.ContentHash ?? Hash(clear),
                    encrypted.Length,
                    item.IsPinned,
                    item.UpdatedAt,
                    Math.Max(1, item.CopyCount)));
            }

            var retainedEntries = new List<Entry>();
            var totalBytes = 0L;
            foreach (var entry in candidateEntries)
            {
                if (totalBytes + entry.EncryptedByteCount > MaximumEncryptedBytes)
                {
                    continue;
                }

                retainedEntries.Add(entry);
                totalBytes += entry.EncryptedByteCount;
            }

            var retainedIds = retainedEntries.Select(entry => entry.Id).ToHashSet();
            var manifest = new Manifest { Entries = retainedEntries };
            var manifestData = JsonSerializer.SerializeToUtf8Bytes(manifest);
            WriteProtected(AesGcmBox.Seal(manifestData, key), _manifestFile);

            var obsoleteIds = existing.Entries.Select(entry => entry.Id)
                .Union(newlyWrittenIds)
                .Where(id => !retainedIds.Contains(id))
                .ToList();
            foreach (var id in obsoleteIds)
            {
                RemovePayloadFiles(id);
            }

            return retainedEntries
                .Select(entry => normalizedById[entry.Id])
                .ToList();
        }
        catch
        {
            foreach (var id in newlyWrittenIds)
            {
                RemovePayloadFiles(id);
            }

            throw;
        }
    }

    public byte[]? ImageData(Guid id)
    {
        try
        {
            var key = DpapiKeyAccessor.Key(createIfMissing: false);
            var encrypted = File.ReadAllBytes(RecordFile(id));
            var clear = AesGcmBox.Open(encrypted, key);
            var record = JsonSerializer.Deserialize<Record>(clear);
            return record?.ImageData;
        }
        catch
        {
            return null;
        }
    }

    public void RemovePersistedHistory()
    {
        if (Directory.Exists(_vaultDirectory))
        {
            Directory.Delete(_vaultDirectory, recursive: true);
        }

        Directory.CreateDirectory(_vaultDirectory);
        Directory.CreateDirectory(_recordsDirectory);
        Directory.CreateDirectory(_thumbnailsDirectory);
    }

    public long DiskUsage()
    {
        if (!Directory.Exists(_vaultDirectory))
        {
            return 0;
        }

        try
        {
            return Directory.EnumerateFiles(_vaultDirectory, "*", SearchOption.AllDirectories)
                .Sum(path => new FileInfo(path).Length);
        }
        catch
        {
            return 0;
        }
    }

    private Manifest CurrentManifest(byte[] key)
    {
        if (!File.Exists(_manifestFile))
        {
            return new Manifest();
        }

        var clear = AesGcmBox.Open(File.ReadAllBytes(_manifestFile), key);
        return JsonSerializer.Deserialize<Manifest>(clear) ?? new Manifest();
    }

    private byte[]? LoadThumbnail(Guid id, byte[] key)
    {
        var file = ThumbnailFile(id);
        if (!File.Exists(file))
        {
            return null;
        }

        return AesGcmBox.Open(File.ReadAllBytes(file), key);
    }

    private void WriteProtected(byte[] data, string path)
    {
        File.WriteAllBytes(path, data);
        AppPaths.RestrictFile(path);
    }

    private string RecordFile(Guid id) => Path.Combine(_recordsDirectory, $"{id:N}.enc");

    private string ThumbnailFile(Guid id) => Path.Combine(_thumbnailsDirectory, $"{id:N}.enc");

    private void RemovePayloadFiles(Guid id)
    {
        try
        {
            File.Delete(RecordFile(id));
        }
        catch
        {
            // Best-effort cleanup.
        }

        try
        {
            File.Delete(ThumbnailFile(id));
        }
        catch
        {
            // Best-effort cleanup.
        }
    }

    private static byte[]? MakeThumbnail(byte[] data)
    {
        try
        {
            using var stream = new MemoryStream(data);
            using var image = Image.FromStream(stream);
            var maxSide = 192;
            var scale = Math.Min(1.0, maxSide / (double)Math.Max(image.Width, image.Height));
            var width = Math.Max(1, (int)(image.Width * scale));
            var height = Math.Max(1, (int)(image.Height * scale));
            using var thumbnail = new Bitmap(width, height);
            using (var graphics = Graphics.FromImage(thumbnail))
            {
                graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                graphics.SmoothingMode = SmoothingMode.HighQuality;
                graphics.DrawImage(image, 0, 0, width, height);
            }

            using var output = new MemoryStream();
            thumbnail.Save(output, ImageFormat.Png);
            return output.ToArray();
        }
        catch
        {
            return null;
        }
    }

    private static string Hash(byte[] data)
    {
        return Convert.ToHexString(SHA256.HashData(data)).ToLowerInvariant();
    }

    private sealed class Manifest
    {
        public int Version { get; set; } = 2;

        public List<Entry> Entries { get; set; } = [];
    }

    private sealed class Entry
    {
        public Entry()
        {
        }

        public Entry(
            Guid id,
            ClipboardItemKind kind,
            string displayText,
            DateTimeOffset createdAt,
            string? sourceApplication,
            string contentHash,
            int encryptedByteCount,
            bool isPinned,
            DateTimeOffset? updatedAt,
            int copyCount)
        {
            Id = id;
            Kind = kind;
            DisplayText = displayText;
            CreatedAt = createdAt;
            SourceApplication = sourceApplication;
            ContentHash = contentHash;
            EncryptedByteCount = encryptedByteCount;
            IsPinned = isPinned;
            UpdatedAt = updatedAt;
            CopyCount = copyCount;
        }

        public Guid Id { get; set; }

        public ClipboardItemKind Kind { get; set; }

        public string DisplayText { get; set; } = "";

        public DateTimeOffset CreatedAt { get; set; }

        public string? SourceApplication { get; set; }

        public string ContentHash { get; set; } = "";

        public int EncryptedByteCount { get; set; }

        public bool IsPinned { get; set; }

        public DateTimeOffset? UpdatedAt { get; set; }

        public int CopyCount { get; set; } = 1;
    }

    private sealed class Record
    {
        public Record()
        {
        }

        public Record(List<string> payload, byte[]? imageData)
        {
            Payload = payload;
            ImageData = imageData;
        }

        public List<string> Payload { get; set; } = [];

        public byte[]? ImageData { get; set; }
    }
}
