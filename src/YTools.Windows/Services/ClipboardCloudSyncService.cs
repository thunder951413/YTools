using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using WebDAVClient;
using YTools.Models;
using YTools.Services.Storage;

namespace YTools.Services;

/// <summary>
/// Incremental Jianguoyun synchronization. Each changed clipboard item becomes
/// one immutable encrypted event. Per-device plaintext heads expose only a
/// sequence number, so the 15-minute pull downloads no encrypted records when
/// no device has changed.
/// </summary>
public sealed class ClipboardCloudSyncService : IDisposable
{
    private const string Server = "https://dav.jianguoyun.com";
    private const int MaximumEventBytes = 6 * 1024 * 1024;
    private const int MaximumHeadBytes = 4 * 1024;
    private readonly AppPreferences _preferences;
    private readonly SecureCodableStore _credentialStore = new("clipboard-cloud-credentials");
    private readonly SecureCodableStore _stateStore = new("clipboard-cloud-state");
    private readonly SemaphoreSlim _syncGate = new(1, 1);
    private readonly object _stateLock = new();
    private ClipboardCloudState _state;
    private System.Threading.Timer? _pullTimer;
    private string? _createdRemoteRoot;

    public ClipboardCloudSyncService(AppPreferences preferences)
    {
        _preferences = preferences;
        _state = LoadState();
    }

    public bool HasCredentials => _credentialStore.Load<ClipboardCloudCredentials>().Kind == SecureStoreLoadResultKind.Loaded;

    public bool SaveCredentials(string username, string appPassword, string syncPassphrase, out string? error)
    {
        if (string.IsNullOrWhiteSpace(username) || string.IsNullOrWhiteSpace(appPassword) || syncPassphrase.Length < 12)
        {
            error = "请填写坚果云用户名、应用密码和至少 12 个字符的同步口令。";
            return false;
        }

        if (!_credentialStore.Save(new ClipboardCloudCredentials(username.Trim(), appPassword, syncPassphrase)))
        {
            error = "无法加密保存坚果云凭据。";
            return false;
        }

        error = null;
        return true;
    }

    public void StartPeriodicPull(Func<IReadOnlyList<ClipboardHistoryItem>> items, Action<ClipboardCloudSyncResult> completed)
    {
        _pullTimer?.Dispose();
        if (!_preferences.ClipboardCloudSyncEnabled)
        {
            return;
        }

        var period = TimeSpan.FromMinutes(_preferences.ClipboardCloudSyncIntervalMinutes);
        _pullTimer = new System.Threading.Timer(
            _ => _ = SynchronizeAsync(items(), completed),
            null,
            period,
            period);
    }

    public Task SyncNowAsync(IReadOnlyList<ClipboardHistoryItem> items, Action<ClipboardCloudSyncResult> completed) =>
        SynchronizeAsync(items, completed);

    public Task PublishChangedItemAsync(ClipboardHistoryItem item, Action<ClipboardCloudSyncResult> completed)
    {
        if (!_preferences.ClipboardCloudSyncEnabled)
        {
            Complete(completed, ClipboardCloudSyncResult.Skipped());
            return Task.CompletedTask;
        }

        lock (_stateLock)
        {
            EnqueueLocked(ClipboardCloudEvent.Upsert(NextSequenceLocked(), _state.DeviceId, item));
        }

        return SynchronizeAsync([], completed, pullRemote: false);
    }

    public Task PublishDeletedAsync(IEnumerable<Guid> ids, Action<ClipboardCloudSyncResult> completed)
    {
        if (!_preferences.ClipboardCloudSyncEnabled)
        {
            Complete(completed, ClipboardCloudSyncResult.Skipped());
            return Task.CompletedTask;
        }

        var list = ids.Distinct().ToList();
        if (list.Count == 0)
        {
            return Task.CompletedTask;
        }

        lock (_stateLock)
        {
            EnqueueLocked(ClipboardCloudEvent.Delete(NextSequenceLocked(), _state.DeviceId, list, DateTimeOffset.UtcNow));
        }

        return SynchronizeAsync([], completed, pullRemote: false);
    }

    public void Dispose()
    {
        _pullTimer?.Dispose();
        _syncGate.Dispose();
    }

    private async Task SynchronizeAsync(
        IReadOnlyList<ClipboardHistoryItem> local,
        Action<ClipboardCloudSyncResult> completed,
        bool pullRemote = true)
    {
        await _syncGate.WaitAsync();
        try
        {
            if (!_preferences.ClipboardCloudSyncEnabled)
            {
                Complete(completed, ClipboardCloudSyncResult.Skipped());
                return;
            }

            var credentials = CredentialsOrThrow();
            using IClient client = CreateClient(credentials);
            using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(45));
            var folders = await EnsureFoldersAsync(client, cancellation.Token);
            await PublishPendingAsync(client, folders, credentials.SyncPassphrase, cancellation.Token);
            if (!pullRemote)
            {
                Complete(completed, ClipboardCloudSyncResult.Succeeded(null, "剪贴板变更已加密上传。"));
                return;
            }

            var events = await PullChangedEventsAsync(client, folders, credentials.SyncPassphrase, cancellation.Token);
            var items = ApplyEvents(local, events);
            Complete(completed, ClipboardCloudSyncResult.Succeeded(items, events.Count == 0 ? "坚果云无新的剪贴板变更。" : "坚果云剪贴板已合并。"));
        }
        catch (Exception exception)
        {
            Complete(completed, ClipboardCloudSyncResult.Failed($"坚果云同步失败：{SafeMessage(exception)}"));
        }
        finally
        {
            _syncGate.Release();
        }
    }

    private ClipboardCloudCredentials CredentialsOrThrow()
    {
        var result = _credentialStore.Load<ClipboardCloudCredentials>();
        if (result.Kind != SecureStoreLoadResultKind.Loaded || result.Value is null)
        {
            throw new InvalidOperationException("尚未保存坚果云同步凭据。");
        }

        return result.Value;
    }

    private static IClient CreateClient(ClipboardCloudCredentials credentials)
    {
        IClient client = new Client(new NetworkCredential
        {
            UserName = credentials.Username,
            Password = credentials.AppPassword
        })
        {
            Server = Server,
            BasePath = "/dav/",
            UserAgent = "YTools"
        };
        return client;
    }

    private async Task<RemoteFolders> EnsureFoldersAsync(IClient client, CancellationToken cancellationToken)
    {
        var root = "/" + string.Join('/', ValidateRemoteFolder(_preferences.ClipboardCloudSyncFolder));
        var folders = new RemoteFolders(root, root + "/heads", root + "/events", root + "/events/" + _state.DeviceId.ToString("N"));
        if (string.Equals(root, _createdRemoteRoot, StringComparison.Ordinal))
        {
            return folders;
        }

        var current = "/";
        foreach (var segment in ValidateRemoteFolder(_preferences.ClipboardCloudSyncFolder))
        {
            await CreateFolderIfMissingAsync(client, current, segment, cancellationToken);
            current = current == "/" ? "/" + segment : current + "/" + segment;
        }

        await CreateFolderIfMissingAsync(client, current, "heads", cancellationToken);
        await CreateFolderIfMissingAsync(client, current, "events", cancellationToken);
        await CreateFolderIfMissingAsync(client, folders.Events, _state.DeviceId.ToString("N"), cancellationToken);
        _createdRemoteRoot = root;
        return folders;
    }

    private static async Task CreateFolderIfMissingAsync(IClient client, string parent, string name, CancellationToken cancellationToken)
    {
        try
        {
            await client.CreateDir(parent, name, cancellationToken: cancellationToken);
        }
        catch (Exception)
        {
            // MKCOL is intentionally attempted only during setup. Existing
            // folders are the normal result on every subsequent app launch.
        }
    }

    private async Task PublishPendingAsync(IClient client, RemoteFolders folders, string syncPassphrase, CancellationToken cancellationToken)
    {
        // Snapshot the pending batch up front. Events enqueued while this batch
        // uploads stay in Pending with higher sequences and go out next round;
        // the head therefore only ever advertises sequences that exist remotely.
        List<ClipboardCloudEvent> batch;
        lock (_stateLock)
        {
            if (_state.Pending.Count == 0)
            {
                return;
            }

            batch = _state.Pending.OrderBy(item => item.Sequence).ToList();
        }

        foreach (var entry in batch)
        {
            var clear = JsonSerializer.SerializeToUtf8Bytes(entry);
            if (clear.Length > MaximumEventBytes)
            {
                throw new InvalidDataException("单条剪贴板同步记录超过 6 MB 上限。");
            }

            var encrypted = ClipboardCloudCryptography.Seal(clear, syncPassphrase);
            using var stream = new MemoryStream(encrypted, writable: false);
            await client.Upload(folders.DeviceEvents, stream, EventName(entry.Sequence), cancellationToken: cancellationToken);
        }

        var latest = batch.Max(item => item.Sequence);
        var head = JsonSerializer.SerializeToUtf8Bytes(new ClipboardCloudHead(2, _state.DeviceId, latest, DateTimeOffset.UtcNow));
        using var streamHead = new MemoryStream(head, writable: false);
        await client.Upload(folders.Heads, streamHead, HeadName(_state.DeviceId), cancellationToken: cancellationToken);
        lock (_stateLock)
        {
            var uploaded = batch.Select(item => item.Sequence).ToHashSet();
            _state.Pending.RemoveAll(item => uploaded.Contains(item.Sequence));
            _state.KnownSequences[_state.DeviceId] = Math.Max(
                _state.KnownSequences.TryGetValue(_state.DeviceId, out var known) ? known : 0,
                latest);
            SaveState();
        }
    }

    private async Task<IReadOnlyList<ClipboardCloudEvent>> PullChangedEventsAsync(
        IClient client,
        RemoteFolders folders,
        string syncPassphrase,
        CancellationToken cancellationToken)
    {
        var events = new List<ClipboardCloudEvent>();
        var heads = await client.List(folders.Heads, depth: 1, cancellationToken: cancellationToken);
        foreach (var file in heads.Where(item => !item.IsCollection && item.Href.EndsWith(".head", StringComparison.OrdinalIgnoreCase)))
        {
            var head = await DownloadJsonAsync<ClipboardCloudHead>(client, file.Href, MaximumHeadBytes, cancellationToken);
            if (head.Version != 2 || head.DeviceId == Guid.Empty || head.LastSequence < 0)
            {
                throw new InvalidDataException("坚果云同步标记格式不正确。");
            }

            long known;
            lock (_stateLock)
            {
                known = _state.KnownSequences.TryGetValue(head.DeviceId, out var sequence) ? sequence : 0;
            }

            if (head.LastSequence <= known)
            {
                continue;
            }

            var eventFolder = folders.Events + "/" + head.DeviceId.ToString("N");
            for (var next = known + 1; next <= head.LastSequence; next += 1)
            {
                using var stream = await client.Download(eventFolder + "/" + EventName(next), cancellationToken);
                using var memory = new MemoryStream();
                await stream.CopyToAsync(memory, cancellationToken);
                if (memory.Length > MaximumEventBytes)
                {
                    throw new InvalidDataException("远端剪贴板同步记录超过 6 MB 上限。");
                }

                var clear = ClipboardCloudCryptography.Open(memory.ToArray(), syncPassphrase);
                var entry = JsonSerializer.Deserialize<ClipboardCloudEvent>(clear)
                    ?? throw new InvalidDataException("远端剪贴板同步记录为空。");
                if (entry.Sequence != next || entry.DeviceId != head.DeviceId)
                {
                    throw new InvalidDataException("远端剪贴板同步记录与标记不一致。");
                }

                events.Add(entry);
            }

            lock (_stateLock)
            {
                if (!_state.KnownSequences.TryGetValue(head.DeviceId, out var current)
                    || current < head.LastSequence)
                {
                    _state.KnownSequences[head.DeviceId] = head.LastSequence;
                    SaveState();
                }
            }
        }

        return events;
    }

    private static async Task<T> DownloadJsonAsync<T>(IClient client, string path, int maximumBytes, CancellationToken cancellationToken)
    {
        using var stream = await client.Download(path, cancellationToken);
        using var memory = new MemoryStream();
        await stream.CopyToAsync(memory, cancellationToken);
        if (memory.Length > maximumBytes)
        {
            throw new InvalidDataException("坚果云同步标记超过允许大小。");
        }

        return JsonSerializer.Deserialize<T>(memory.ToArray())
            ?? throw new InvalidDataException("坚果云同步标记为空。");
    }

    private static IReadOnlyList<ClipboardHistoryItem> ApplyEvents(
        IReadOnlyList<ClipboardHistoryItem> local,
        IReadOnlyList<ClipboardCloudEvent> events)
    {
        var items = local.ToDictionary(item => item.Id);
        var tombstones = new Dictionary<Guid, DateTimeOffset>();
        foreach (var entry in events.OrderBy(item => item.Timestamp))
        {
            if (entry.Kind == ClipboardCloudEventKind.Delete)
            {
                foreach (var id in entry.DeletedIds)
                {
                    tombstones[id] = entry.Timestamp;
                    items.Remove(id);
                }

                continue;
            }

            if (entry.Item is null)
            {
                throw new InvalidDataException("剪贴板新增记录缺少内容。");
            }

            var item = entry.Item.ToItem();
            if (!tombstones.TryGetValue(item.Id, out var deletedAt) || item.EffectiveUpdatedAt > deletedAt)
            {
                if (!items.TryGetValue(item.Id, out var previous)
                    || item.EffectiveUpdatedAt > previous.EffectiveUpdatedAt)
                {
                    // An upsert published without image bytes must not erase the
                    // receiver's stored copy of the same content.
                    if (item.BinaryData is null
                        && previous is { } kept
                        && string.Equals(kept.ContentHash, item.ContentHash, StringComparison.Ordinal))
                    {
                        item = item with { BinaryData = kept.BinaryData };
                    }

                    items[item.Id] = item;
                }
            }
        }

        return items.Values
            .OrderByDescending(item => item.IsPinned)
            .ThenByDescending(item => item.CreatedAt)
            .ToList();
    }

    private long NextSequenceLocked()
    {
        var result = _state.NextSequence;
        _state.NextSequence += 1;
        return result;
    }

    private void EnqueueLocked(ClipboardCloudEvent entry)
    {
        _state.Pending.Add(entry);
        SaveState();
    }

    private ClipboardCloudState LoadState()
    {
        var result = _stateStore.Load<ClipboardCloudState>();
        if (result.Kind == SecureStoreLoadResultKind.Loaded && result.Value is { } state && state.DeviceId != Guid.Empty)
        {
            state.NextSequence = Math.Max(1, state.NextSequence);
            return state;
        }

        var created = new ClipboardCloudState { DeviceId = Guid.NewGuid() };
        _stateStore.Save(created);
        return created;
    }

    private void SaveState()
    {
        _stateStore.Save(_state);
    }

    private static IReadOnlyList<string> ValidateRemoteFolder(string value)
    {
        var parts = value.Replace('\\', '/').Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0 || parts.Length > 4 || parts.Any(part => part.Length > 64 || part is "." or ".." || !part.All(IsSafeFolderCharacter)))
        {
            throw new InvalidDataException("坚果云同步目录只能包含 1–4 个由字母、数字、点、下划线或连字符组成的层级。");
        }

        return parts;
    }

    private static bool IsSafeFolderCharacter(char value) => char.IsAsciiLetterOrDigit(value) || value is '.' or '_' or '-';

    private static string EventName(long sequence) => sequence.ToString("D20", System.Globalization.CultureInfo.InvariantCulture) + ".enc";

    private static string HeadName(Guid deviceId) => deviceId.ToString("N") + ".head";

    private static string SafeMessage(Exception exception) => exception.Message.Replace('\r', ' ').Replace('\n', ' ').Trim();

    private static void Complete(Action<ClipboardCloudSyncResult> completed, ClipboardCloudSyncResult result)
    {
        var dispatcher = Application.Current?.Dispatcher;
        if (dispatcher is null || dispatcher.CheckAccess())
        {
            completed(result);
            return;
        }

        _ = dispatcher.BeginInvoke(() => completed(result));
    }

    private sealed record ClipboardCloudCredentials(string Username, string AppPassword, string SyncPassphrase);

    private sealed class ClipboardCloudState
    {
        public Guid DeviceId { get; set; }

        public long NextSequence { get; set; } = 1;

        public Dictionary<Guid, long> KnownSequences { get; set; } = [];

        public List<ClipboardCloudEvent> Pending { get; set; } = [];
    }

    private sealed record RemoteFolders(string Root, string Heads, string Events, string DeviceEvents);

    private sealed record ClipboardCloudHead(int Version, Guid DeviceId, long LastSequence, DateTimeOffset UpdatedAt);

    private sealed class ClipboardCloudEvent
    {
        public long Sequence { get; set; }

        public Guid DeviceId { get; set; }

        public ClipboardCloudEventKind Kind { get; set; }

        public DateTimeOffset Timestamp { get; set; }

        public ClipboardCloudRecord? Item { get; set; }

        public List<Guid> DeletedIds { get; set; } = [];

        public static ClipboardCloudEvent Upsert(long sequence, Guid deviceId, ClipboardHistoryItem item) => new()
        {
            Sequence = sequence,
            DeviceId = deviceId,
            Kind = ClipboardCloudEventKind.Upsert,
            Timestamp = item.EffectiveUpdatedAt,
            Item = ClipboardCloudRecord.FromItem(item)
        };

        public static ClipboardCloudEvent Delete(long sequence, Guid deviceId, IReadOnlyList<Guid> ids, DateTimeOffset timestamp) => new()
        {
            Sequence = sequence,
            DeviceId = deviceId,
            Kind = ClipboardCloudEventKind.Delete,
            Timestamp = timestamp,
            DeletedIds = ids.ToList()
        };
    }

    private enum ClipboardCloudEventKind
    {
        Upsert,
        Delete
    }

    private sealed class ClipboardCloudRecord
    {
        public Guid Id { get; set; }
        public ClipboardItemKind Kind { get; set; }
        public List<string> Payload { get; set; } = [];
        public DateTimeOffset CreatedAt { get; set; }
        public DateTimeOffset UpdatedAt { get; set; }
        public string? SourceApplication { get; set; }
        public byte[]? BinaryData { get; set; }
        public string? ContentHash { get; set; }
        public bool IsPinned { get; set; }

        public static ClipboardCloudRecord FromItem(ClipboardHistoryItem item) => new()
        {
            Id = item.Id,
            Kind = item.Kind,
            Payload = item.Payload.ToList(),
            CreatedAt = item.CreatedAt,
            UpdatedAt = item.EffectiveUpdatedAt,
            SourceApplication = item.SourceApplication,
            BinaryData = item.BinaryData,
            ContentHash = item.ContentHash,
            IsPinned = item.IsPinned
        };

        public ClipboardHistoryItem ToItem() => new(Id, Kind, Payload, CreatedAt, SourceApplication, BinaryData, ContentHash, IsPinned, UpdatedAt);
    }
}

public sealed record ClipboardCloudSyncResult(bool Success, bool WasSkipped, IReadOnlyList<ClipboardHistoryItem>? Items, string? Message)
{
    public static ClipboardCloudSyncResult Succeeded(IReadOnlyList<ClipboardHistoryItem>? items, string message) => new(true, false, items, message);
    public static ClipboardCloudSyncResult Failed(string message) => new(false, false, null, message);
    public static ClipboardCloudSyncResult Skipped() => new(true, true, null, null);
}

internal static class ClipboardCloudCryptography
{
    private static readonly byte[] Magic = "YTCE2"u8.ToArray();
    private const int SaltLength = 16;
    private const int Iterations = 600_000;

    public static byte[] Seal(byte[] clear, string passphrase)
    {
        var salt = RandomNumberGenerator.GetBytes(SaltLength);
        var key = DeriveKey(passphrase, salt);
        try
        {
            var encrypted = AesGcmBox.Seal(clear, key);
            var output = new byte[Magic.Length + salt.Length + encrypted.Length];
            Buffer.BlockCopy(Magic, 0, output, 0, Magic.Length);
            Buffer.BlockCopy(salt, 0, output, Magic.Length, salt.Length);
            Buffer.BlockCopy(encrypted, 0, output, Magic.Length + salt.Length, encrypted.Length);
            return output;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
        }
    }

    public static byte[] Open(byte[] encrypted, string passphrase)
    {
        if (encrypted.Length < Magic.Length + SaltLength + 28 || !encrypted.AsSpan(0, Magic.Length).SequenceEqual(Magic))
        {
            throw new CryptographicException("远端内容不是 YTools 剪贴板同步密文。");
        }

        var key = DeriveKey(passphrase, encrypted.AsSpan(Magic.Length, SaltLength).ToArray());
        try
        {
            return AesGcmBox.Open(encrypted[(Magic.Length + SaltLength)..], key);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
        }
    }

    private static byte[] DeriveKey(string passphrase, byte[] salt) =>
        Rfc2898DeriveBytes.Pbkdf2(Encoding.UTF8.GetBytes(passphrase), salt, Iterations, HashAlgorithmName.SHA256, 32);
}
