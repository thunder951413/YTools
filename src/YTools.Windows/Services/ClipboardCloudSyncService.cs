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
    internal const int MaximumEventBytes = 8 * 1024 * 1024;
    private const int EnvelopeBytes = 49;
    private const int MaximumPullEvents = 200;
    private const int MaximumHeadBytes = 4 * 1024;
    private readonly AppPreferences _preferences;
    private readonly SecureCodableStore _credentialStore = new("clipboard-cloud-credentials");
    private readonly SecureCodableStore _stateStore = new("clipboard-cloud-state");
    private readonly SemaphoreSlim _syncGate = new(1, 1);
    private readonly object _stateLock = new();
    private ClipboardCloudState _state;
    private System.Threading.Timer? _pullTimer;
    private string? _createdRemoteRoot;
    private volatile string? _stateError;
    private volatile bool _disposed;
    private volatile bool _hasCredentials;
    private readonly Task _initialize;
    private ClipboardCloudBatch? _publishedInbox;
    private IReadOnlyDictionary<Guid, DateTimeOffset> _publishedTombstones = new Dictionary<Guid, DateTimeOffset>();

    public ClipboardCloudSyncService(AppPreferences preferences)
    {
        _preferences = preferences;
        _state = new ClipboardCloudState { DeviceId = Guid.NewGuid() };
        _initialize = Task.Run(() =>
        {
            lock (_stateLock)
            {
                _state = LoadState();
                PublishSnapshots();
                _hasCredentials = _credentialStore.Load<ClipboardCloudCredentials>().Kind == SecureStoreLoadResultKind.Loaded;
            }
        });
    }

    public bool HasCredentials => _hasCredentials;
    public Task InitializeAsync() => _initialize;

    public Task<string?> SaveCredentialsAsync(string username, string appPassword, string syncPassphrase) => Task.Run(async () =>
    {
        await _initialize;
        return SaveCredentials(username, appPassword, syncPassphrase);
    });

    private string? SaveCredentials(string username, string appPassword, string syncPassphrase)
    {
        if (string.IsNullOrWhiteSpace(username) || string.IsNullOrWhiteSpace(appPassword) || syncPassphrase.Length < 12)
        {
            return "请填写坚果云用户名、应用密码和至少 12 个字符的同步口令。";
        }

        if (!_credentialStore.Save(new ClipboardCloudCredentials(username.Trim(), appPassword, syncPassphrase)))
        {
            return "无法加密保存坚果云凭据。";
        }

        _hasCredentials = true;
        return null;
    }

    public void StartPeriodicPull(Func<IReadOnlyList<ClipboardHistoryItem>> items, Action<ClipboardCloudSyncResult> completed)
    {
        _pullTimer?.Dispose();
        if (_disposed || !_preferences.ClipboardCloudSyncEnabled)
        {
            return;
        }

        var period = TimeSpan.FromMinutes(_preferences.ClipboardCloudSyncIntervalMinutes);
        _pullTimer = new System.Threading.Timer(
            _ => _ = Task.Run(() => SynchronizeAsync([], completed)),
            null,
            period,
            period);
    }

    public Task SyncNowAsync(IReadOnlyList<ClipboardHistoryItem> items, Action<ClipboardCloudSyncResult> completed) =>
        Task.Run(() => SynchronizeAsync(items, completed));

    public Task PublishChangedItemAsync(ClipboardHistoryItem item, Action<ClipboardCloudSyncResult> completed) =>
        PublishAsync((sequence, device) => ClipboardCloudEvent.Upsert(sequence, device, item), completed);

    public Task PublishDeletedAsync(IEnumerable<Guid> ids, Action<ClipboardCloudSyncResult> completed, DateTimeOffset? timestamp = null)
    {
        var list = ids.Distinct().ToList();
        var deletedAt = timestamp ?? DateTimeOffset.UtcNow;
        return list.Count == 0 ? Task.CompletedTask : PublishAsync(
            (sequence, device) => ClipboardCloudEvent.Delete(sequence, device, list, deletedAt), completed);
    }

    private Task PublishAsync(Func<long, Guid, ClipboardCloudEvent> create, Action<ClipboardCloudSyncResult> completed) => Task.Run(async () =>
    {
        await _initialize;
        if (_disposed || !_preferences.ClipboardCloudSyncEnabled) { return; }
        try
        {
            lock (_stateLock)
            {
                if (_stateError is not null) { throw new SecureStorageException(_stateError); }
                BindScope(CredentialsOrThrow());
                var entry = create(_state.NextSequence, _state.DeviceId);
                if (JsonSerializer.SerializeToUtf8Bytes(entry).Length > MaximumEventBytes - EnvelopeBytes)
                { throw new InvalidDataException("剪贴板同步记录过大，未加入上传队列。"); }
                _state.NextSequence += 1;
                EnqueueLocked(entry);
            }
            await SynchronizeAsync([], completed, pullRemote: false);
        }
        catch (Exception exception) { Complete(completed, ClipboardCloudSyncResult.Failed(exception.Message)); }
    });

    internal IReadOnlyList<ClipboardHistoryItem> MergeRemote(IReadOnlyList<ClipboardHistoryItem> current,
        ClipboardCloudBatch batch, IReadOnlyDictionary<Guid, DateTimeOffset> localDeletions)
    {
        Dictionary<Guid, DateTimeOffset> deleted;
        deleted = new(Volatile.Read(ref _publishedTombstones));
        foreach (var pair in localDeletions)
        { if (!deleted.TryGetValue(pair.Key, out var date) || pair.Value > date) { deleted[pair.Key] = pair.Value; } }
        return ApplyEvents(current, batch.Events, deleted);
    }

    internal ClipboardCloudBatch? PendingBatch
    {
        get => Volatile.Read(ref _publishedInbox);
    }

    internal Task AcknowledgeAsync(ClipboardCloudBatch batch) => Task.Run(() =>
    {
        lock (_stateLock)
        {
            var received = batch.Events.Select(entry => (entry.DeviceId, entry.Sequence)).ToHashSet();
            _state.Inbox.RemoveAll(entry => received.Contains((entry.DeviceId, entry.Sequence)));
            SaveState();
        }
    });

    public void Dispose()
    {
        _pullTimer?.Dispose();
        _disposed = true; // In-flight work owns the gate until completion.
    }

    private async Task SynchronizeAsync(
        IReadOnlyList<ClipboardHistoryItem> local,
        Action<ClipboardCloudSyncResult> completed,
        bool pullRemote = true)
    {
        await _initialize;
        await _syncGate.WaitAsync();
        try
        {
            if (_disposed || !_preferences.ClipboardCloudSyncEnabled)
            {
                Complete(completed, ClipboardCloudSyncResult.Skipped());
                return;
            }

            if (_stateError is not null) { throw new SecureStorageException(_stateError); }
            var credentials = CredentialsOrThrow();
            lock (_stateLock) { BindScope(credentials); }
            using IClient client = CreateClient(credentials);
            using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(45));
            var folders = await EnsureFoldersAsync(client, cancellation.Token);
            await PublishPendingAsync(client, folders, credentials.SyncPassphrase, cancellation.Token);
            if (!pullRemote)
            {
                Complete(completed, ClipboardCloudSyncResult.Succeeded(null, "剪贴板变更已加密上传。"));
                return;
            }

            if (PendingBatch is null) { _ = await PullChangedEventsAsync(client, folders, credentials.SyncPassphrase, cancellation.Token); }
            List<ClipboardCloudEvent> inbox;
            lock (_stateLock) { inbox = _state.Inbox.ToList(); }
            Complete(completed, ClipboardCloudSyncResult.Succeeded(null, inbox.Count == 0 ? "坚果云无新的剪贴板变更。" : "正在保存收到的剪贴板变更…")
                with { Batch = inbox.Count == 0 ? null : new ClipboardCloudBatch(inbox) });
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

    private void BindScope(ClipboardCloudCredentials credentials)
    {
        var scope = credentials.Username.Trim().ToLowerInvariant() + "/" + string.Join('/', ValidateRemoteFolder(_preferences.ClipboardCloudSyncFolder));
        if (_state.Scope == scope) { return; }
        if (_state.Scope is not null)
        {
            if (_state.Pending.Count > 0 || _state.Inbox.Count > 0)
            { throw new InvalidOperationException("旧同步目录仍有待处理变更，请先恢复原账号和目录完成同步。"); }
            _state.DeviceId = Guid.NewGuid();
            _state.NextSequence = 1;
            _state.KnownSequences.Clear();
        }
        _state.Scope = scope;
        _createdRemoteRoot = null;
        SaveState();
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
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            // Verify the collection exists before treating failed MKCOL as
            // harmless; authorization/network failures must remain retryable.
            _ = await client.List(parent.TrimEnd('/') + "/" + name, depth: 0, cancellationToken: cancellationToken);
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
            if (clear.Length > MaximumEventBytes - EnvelopeBytes)
            {
                throw new InvalidDataException("单条剪贴板同步记录超过 8 MB 上限。");
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
        var advances = new Dictionary<Guid, long>();
        var receivedBytes = 0;
        var heads = await client.List(folders.Heads, depth: 1, cancellationToken: cancellationToken);
        foreach (var file in heads.Where(item => !item.IsCollection && item.Href.EndsWith(".head", StringComparison.OrdinalIgnoreCase)))
        {
            var name = Path.GetFileName(file.Href.TrimEnd('/'));
            if (!Guid.TryParseExact(Path.GetFileNameWithoutExtension(name), "N", out var fileDevice)) { continue; }
            var head = await DownloadJsonAsync<ClipboardCloudHead>(client, folders.Heads + "/" + name, MaximumHeadBytes, cancellationToken);
            if (head.Version != 2 || head.DeviceId != fileDevice || head.DeviceId == Guid.Empty || head.LastSequence < 0)
            {
                throw new InvalidDataException("坚果云同步标记格式不正确。");
            }

            long known;
            lock (_stateLock)
            {
                known = _state.KnownSequences.TryGetValue(head.DeviceId, out var sequence) ? sequence : 0;
            }

            if (head.DeviceId == _state.DeviceId || head.LastSequence <= known)
            {
                continue;
            }

            var eventFolder = folders.Events + "/" + head.DeviceId.ToString("N");
            for (var next = known + 1; next <= head.LastSequence && events.Count < MaximumPullEvents; next += 1)
            {
                using var stream = await client.Download(eventFolder + "/" + EventName(next), cancellationToken);
                var encrypted = await ReadBoundedAsync(stream, MaximumEventBytes, cancellationToken);
                receivedBytes += encrypted.Length;
                var clear = ClipboardCloudCryptography.Open(encrypted, syncPassphrase);
                var entry = JsonSerializer.Deserialize<ClipboardCloudEvent>(clear)
                    ?? throw new InvalidDataException("远端剪贴板同步记录为空。");
                if (entry.Sequence != next || entry.DeviceId != head.DeviceId)
                {
                    throw new InvalidDataException("远端剪贴板同步记录与标记不一致。");
                }

                ValidateEvent(entry);
                events.Add(entry);
                advances[head.DeviceId] = next;
                if (receivedBytes >= 16 * 1024 * 1024 || next == head.LastSequence) { break; }
            }

            if (events.Count >= MaximumPullEvents || receivedBytes >= 16 * 1024 * 1024) { break; }
        }

        if (events.Count > 0)
        {
            lock (_stateLock)
            {
                _state.Inbox.AddRange(events);
                foreach (var entry in events) { RememberDeletion(entry); }
                foreach (var pair in advances) { _state.KnownSequences[pair.Key] = pair.Value; }
                // The durable inbox makes cursor advancement replayable until
                // the history store acknowledges its own successful commit.
                SaveState();
            }
        }

        return events;
    }

    private static async Task<T> DownloadJsonAsync<T>(IClient client, string path, int maximumBytes, CancellationToken cancellationToken)
    {
        using var stream = await client.Download(path, cancellationToken);
        var bytes = await ReadBoundedAsync(stream, maximumBytes, cancellationToken);
        return JsonSerializer.Deserialize<T>(bytes)
            ?? throw new InvalidDataException("坚果云同步标记为空。");
    }

    internal static async Task<byte[]> ReadBoundedAsync(Stream stream, int maximumBytes, CancellationToken cancellationToken)
    {
        using var memory = new MemoryStream();
        var buffer = new byte[16 * 1024];
        int count;
        while ((count = await stream.ReadAsync(buffer.AsMemory(0, Math.Min(buffer.Length, maximumBytes + 1 - (int)memory.Length)), cancellationToken)) > 0)
        {
            memory.Write(buffer, 0, count);
            if (memory.Length > maximumBytes) { throw new InvalidDataException("远端同步数据超过允许大小。"); }
        }
        return memory.ToArray();
    }

    private static void ValidateEvent(ClipboardCloudEvent entry)
    {
        if (entry.Sequence <= 0 || entry.DeviceId == Guid.Empty || !Enum.IsDefined(entry.Kind)
            || entry.DeletedIds is null || entry.DeletedIds.Contains(Guid.Empty)
            || (entry.Kind == ClipboardCloudEventKind.Upsert && (entry.Item is null
                || entry.Item.Id == Guid.Empty || !Enum.IsDefined(entry.Item.Kind) || entry.Item.Payload is null)))
        { throw new InvalidDataException("远端剪贴板事件无效。"); }
    }

    internal static IReadOnlyList<ClipboardHistoryItem> ApplyEvents(
        IReadOnlyList<ClipboardHistoryItem> local,
        IReadOnlyList<ClipboardCloudEvent> events,
        IReadOnlyDictionary<Guid, DateTimeOffset>? deleted = null)
    {
        var items = local.ToDictionary(item => item.Id);
        var tombstones = deleted is null ? new Dictionary<Guid, DateTimeOffset>() : new Dictionary<Guid, DateTimeOffset>(deleted);
        foreach (var entry in events.OrderBy(item => item.Timestamp).ThenBy(item => item.DeviceId.ToString("N"), StringComparer.Ordinal).ThenBy(item => item.Sequence))
        {
            if (entry.Kind == ClipboardCloudEventKind.Delete)
            {
                foreach (var id in entry.DeletedIds)
                {
                    if (!tombstones.TryGetValue(id, out var priorDelete) || entry.Timestamp > priorDelete) { tombstones[id] = entry.Timestamp; }
                    if (items.TryGetValue(id, out var current) && current.EffectiveUpdatedAt <= tombstones[id]) { items.Remove(id); }
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
                    || item.EffectiveUpdatedAt > previous.EffectiveUpdatedAt
                    || (item.EffectiveUpdatedAt == previous.EffectiveUpdatedAt
                        && StringComparer.Ordinal.Compare(TieKey(item), TieKey(previous)) > 0))
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

    private static string TieKey(ClipboardHistoryItem item) => string.Join("\0",
        item.IsPinned ? "1" : "0", item.ContentHash?.ToLowerInvariant() ?? "", item.SourceApplication ?? "", string.Join("\0", item.Payload));

    private void EnqueueLocked(ClipboardCloudEvent entry)
    {
        _state.Pending.Add(entry);
        RememberDeletion(entry);
        SaveState();
    }

    private void RememberDeletion(ClipboardCloudEvent entry)
    {
        if (entry.Kind != ClipboardCloudEventKind.Delete) { return; }
        foreach (var id in entry.DeletedIds)
        {
            if (!_state.Tombstones.TryGetValue(id, out var prior) || entry.Timestamp > prior)
            { _state.Tombstones[id] = entry.Timestamp; }
        }
    }

    private ClipboardCloudState LoadState()
    {
        var result = _stateStore.Load<ClipboardCloudState>();
        if (result.Kind == SecureStoreLoadResultKind.Loaded && result.Value is { } state && state.DeviceId != Guid.Empty)
        {
            state.NextSequence = Math.Max(1, state.NextSequence);
            return state;
        }

        if (result.Kind != SecureStoreLoadResultKind.Missing)
        {
            _stateError = result.Message ?? "同步状态不可读，已锁定，原密文保留。";
            return new ClipboardCloudState { DeviceId = Guid.NewGuid() };
        }
        var created = new ClipboardCloudState { DeviceId = Guid.NewGuid() };
        if (!_stateStore.Save(created)) { _stateError = "无法保存加密同步状态。"; }
        return created;
    }

    private void SaveState()
    {
        if (!_stateStore.Save(_state))
        {
            _stateError = "同步状态保存失败；同步已暂停，原密文保留。";
            throw new SecureStorageException(_stateError);
        }
        PublishSnapshots();
    }

    private void PublishSnapshots()
    {
        Volatile.Write(ref _publishedInbox, _state.Inbox.Count == 0 ? null : new ClipboardCloudBatch(_state.Inbox.ToList()));
        Volatile.Write(ref _publishedTombstones, new Dictionary<Guid, DateTimeOffset>(_state.Tombstones));
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
        public string? Scope { get; set; }

        public long NextSequence { get; set; } = 1;

        public Dictionary<Guid, long> KnownSequences { get; set; } = [];

        public List<ClipboardCloudEvent> Pending { get; set; } = [];
        public List<ClipboardCloudEvent> Inbox { get; set; } = [];
        public Dictionary<Guid, DateTimeOffset> Tombstones { get; set; } = [];
    }

    private sealed record RemoteFolders(string Root, string Heads, string Events, string DeviceEvents);

    private sealed record ClipboardCloudHead(int Version, Guid DeviceId, long LastSequence, DateTimeOffset UpdatedAt);

    internal sealed class ClipboardCloudEvent
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

    internal enum ClipboardCloudEventKind
    {
        Upsert,
        Delete
    }

    internal sealed class ClipboardCloudRecord
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

internal sealed record ClipboardCloudBatch(IReadOnlyList<ClipboardCloudSyncService.ClipboardCloudEvent> Events);

public sealed record ClipboardCloudSyncResult(bool Success, bool WasSkipped, IReadOnlyList<ClipboardHistoryItem>? Items, string? Message)
{
    internal ClipboardCloudBatch? Batch { get; init; }

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
