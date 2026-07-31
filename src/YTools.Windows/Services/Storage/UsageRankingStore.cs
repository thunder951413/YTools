using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using YTools.Infrastructure;

namespace YTools.Services.Storage;

/// <summary>
/// Stores only SHA-256 hashes of result identifiers, so usage learning does
/// not create a second plaintext index of private file paths.
/// </summary>
public sealed class UsageRankingStore
{
    private readonly object _lock = new();
    private readonly string _filePath;
    private Dictionary<string, Entry> _entries;
    private Dictionary<string, Latch> _latches;

    public UsageRankingStore()
    {
        AppPaths.EnsureDirectories();
        _filePath = AppPaths.UsageRankingFile;
        (_entries, _latches) = Load();
        Prune();
    }

    public void Record(string identifier, string query)
    {
        lock (_lock)
        {
            var key = Hash(identifier);
            _entries[key] = new Entry(
                Math.Min((_entries.TryGetValue(key, out var old) ? old.Count : 0) + 1, 10_000),
                DateTimeOffset.UtcNow);
            var normalizedQuery = Normalize(query);
            if (!string.IsNullOrEmpty(normalizedQuery))
            {
                var queryHash = Hash(normalizedQuery);
                var confirmations = _latches.TryGetValue(queryHash, out var oldLatch)
                    && oldLatch.ResultHash == key
                    ? Math.Min(oldLatch.Confirmations + 1, 20)
                    : 1;
                _latches[queryHash] = new Latch(key, confirmations, DateTimeOffset.UtcNow);
            }

            Prune();
            Save();
        }
    }

    public int Boost(string identifier, string query)
    {
        lock (_lock)
        {
            var resultHash = Hash(identifier);
            var frequency = _entries.TryGetValue(resultHash, out var entry)
                ? (int)(Math.Log2(entry.Count + 1) * 24)
                : 0;
            var age = _entries.TryGetValue(resultHash, out var entry2)
                ? DateTimeOffset.UtcNow - entry2.LastUsed
                : TimeSpan.MaxValue;
            var recency = age < TimeSpan.FromHours(1) ? 45
                : age < TimeSpan.FromDays(1) ? 30
                : age < TimeSpan.FromDays(7) ? 15
                : 0;

            var normalizedQuery = Normalize(query);
            var latchBoost = 0;
            if (!string.IsNullOrEmpty(normalizedQuery)
                && _latches.TryGetValue(Hash(normalizedQuery), out var latch)
                && latch.ResultHash == resultHash
                && DateTimeOffset.UtcNow - latch.LastUsed < TimeSpan.FromDays(28))
            {
                latchBoost = Math.Min(180, 55 + latch.Confirmations * 25);
            }

            return frequency + recency + latchBoost;
        }
    }

    public void Clear()
    {
        lock (_lock)
        {
            _entries.Clear();
            _latches.Clear();
            try
            {
                File.Delete(_filePath);
            }
            catch
            {
                // Ranking is optional and must never prevent launching a result.
            }
        }
    }

    private void Prune()
    {
        var cutoff = DateTimeOffset.UtcNow.AddDays(-28);
        _entries = _entries.Where(pair => pair.Value.LastUsed >= cutoff)
            .ToDictionary(pair => pair.Key, pair => pair.Value);
        _latches = _latches.Where(pair => pair.Value.LastUsed >= cutoff)
            .ToDictionary(pair => pair.Key, pair => pair.Value);
    }

    private void Save()
    {
        try
        {
            var payload = new StoreData
            {
                Entries = _entries,
                Latches = _latches
            };
            var json = JsonSerializer.SerializeToUtf8Bytes(payload);
            File.WriteAllBytes(_filePath, json);
            AppPaths.RestrictFile(_filePath);
        }
        catch
        {
            // Ranking is optional.
        }
    }

    private (Dictionary<string, Entry>, Dictionary<string, Latch>) Load()
    {
        if (!File.Exists(_filePath))
        {
            return ([], []);
        }

        try
        {
            var json = File.ReadAllBytes(_filePath);
            var data = JsonSerializer.Deserialize<StoreData>(json);
            if (data is not null)
            {
                return (data.Entries, data.Latches);
            }
        }
        catch
        {
            // Fall through to legacy or empty.
        }

        try
        {
            var json = File.ReadAllBytes(_filePath);
            var legacy = JsonSerializer.Deserialize<Dictionary<string, Entry>>(json);
            return legacy is null ? ([], []) : (legacy, []);
        }
        catch
        {
            return ([], []);
        }
    }

    private static string Hash(string value)
    {
        return Convert.ToHexString(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
    }

    private static string Normalize(string query)
    {
        return query.Trim().ToLowerInvariant();
    }

    private sealed record Entry(int Count, DateTimeOffset LastUsed);

    private sealed record Latch(string ResultHash, int Confirmations, DateTimeOffset LastUsed);

    private sealed class StoreData
    {
        public int Version { get; set; } = 2;

        public Dictionary<string, Entry> Entries { get; set; } = [];

        public Dictionary<string, Latch> Latches { get; set; } = [];
    }
}
