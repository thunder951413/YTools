using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using YTools.Infrastructure;

namespace YTools.Services.Storage;

/// <summary>
/// Windows equivalent of the macOS Keychain: a random 32-byte key protected by
/// DPAPI (CurrentUser). Encryption formats stay owned by the stores.
/// </summary>
public static class DpapiKeyAccessor
{
    private static readonly object KeyGate = new();

    public static byte[] Key(bool createIfMissing)
    {
        lock (KeyGate) { return ReadOrCreate(createIfMissing); }
    }

    private static byte[] ReadOrCreate(bool createIfMissing)
    {
        if (File.Exists(AppPaths.KeyFile))
        {
            var protectedBytes = File.ReadAllBytes(AppPaths.KeyFile);
            try
            {
                return ProtectedData.Unprotect(protectedBytes, null, DataProtectionScope.CurrentUser);
            }
            catch (CryptographicException exception)
            {
                throw new SecureStorageException($"密钥无法解密：{exception.Message}");
            }
        }

        if (!createIfMissing || (Directory.Exists(AppPaths.VaultDirectory)
            && Directory.EnumerateFiles(AppPaths.VaultDirectory, "*.enc", SearchOption.AllDirectories).Any()))
        {
            throw new SecureStorageException("加密文件存在，但密钥缺失；为防止覆盖，存储已锁定。");
        }

        var key = RandomNumberGenerator.GetBytes(32);
        var encrypted = ProtectedData.Protect(key, null, DataProtectionScope.CurrentUser);
        try
        {
            AppPaths.EnsureDirectories();
            AtomicWrite(AppPaths.KeyFile, encrypted);
            AppPaths.RestrictFile(AppPaths.KeyFile);
        }
        catch (Exception exception)
        {
            throw new SecureStorageException($"无法写入密钥文件：{exception.Message}");
        }

        return key;
    }
    internal static void AtomicWrite(string path, byte[] bytes)
    {
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                stream.Write(bytes);
                stream.Flush(flushToDisk: true);
            }
            AppPaths.RestrictFile(temporary);
            File.Move(temporary, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary)) { File.Delete(temporary); }
        }
    }

}

public static class AesGcmBox
{
    private const int NonceSize = 12;
    private const int TagSize = 16;

    public static byte[] Seal(byte[] plaintext, byte[] key)
    {
        var nonce = RandomNumberGenerator.GetBytes(NonceSize);
        var ciphertext = new byte[plaintext.Length];
        var tag = new byte[TagSize];
        using var aes = new AesGcm(key, TagSize);
        aes.Encrypt(nonce, plaintext, ciphertext, tag);

        var combined = new byte[NonceSize + ciphertext.Length + TagSize];
        Buffer.BlockCopy(nonce, 0, combined, 0, NonceSize);
        Buffer.BlockCopy(ciphertext, 0, combined, NonceSize, ciphertext.Length);
        Buffer.BlockCopy(tag, 0, combined, NonceSize + ciphertext.Length, TagSize);
        return combined;
    }

    public static byte[] Open(byte[] combined, byte[] key)
    {
        if (combined.Length < NonceSize + TagSize)
        {
            throw new CryptographicException("密文长度无效");
        }

        var nonce = new byte[NonceSize];
        var ciphertext = new byte[combined.Length - NonceSize - TagSize];
        var tag = new byte[TagSize];
        Buffer.BlockCopy(combined, 0, nonce, 0, NonceSize);
        Buffer.BlockCopy(combined, NonceSize, ciphertext, 0, ciphertext.Length);
        Buffer.BlockCopy(combined, NonceSize + ciphertext.Length, tag, 0, TagSize);

        using var aes = new AesGcm(key, TagSize);
        var plaintext = new byte[ciphertext.Length];
        aes.Decrypt(nonce, ciphertext, tag, plaintext);
        return plaintext;
    }
}

public sealed class SecureStorageException : Exception
{
    public SecureStorageException(string message)
        : base(message)
    {
    }
}

public enum SecureStoreLoadResultKind
{
    Missing,
    Loaded,
    Unavailable,
    Corrupted
}

public sealed record SecureStoreLoadResult<T>(SecureStoreLoadResultKind Kind, T? Value, string? Message)
{
    public static SecureStoreLoadResult<T> Missing() => new(SecureStoreLoadResultKind.Missing, default, null);

    public static SecureStoreLoadResult<T> Loaded(T value) =>
        new(SecureStoreLoadResultKind.Loaded, value, null);

    public static SecureStoreLoadResult<T> Unavailable(string message) =>
        new(SecureStoreLoadResultKind.Unavailable, default, message);

    public static SecureStoreLoadResult<T> Corrupted(string message) =>
        new(SecureStoreLoadResultKind.Corrupted, default, message);
}

/// <summary>Small JSON vault encrypted with AES-GCM + DPAPI key.</summary>
public sealed class SecureCodableStore
{
    private readonly string _filePath;
    private readonly Func<bool, byte[]> _key;
    private readonly object _gate = new();
    private bool _locked;

    public SecureCodableStore(string name)
    {
        _filePath = Path.Combine(AppPaths.VaultDirectory, $"{name}.v1.enc");
        _key = DpapiKeyAccessor.Key;
    }

    internal SecureCodableStore(string filePath, Func<bool, byte[]> key)
    {
        _filePath = filePath;
        _key = key;
    }

    public SecureStoreLoadResult<T> Load<T>()
    {
        lock (_gate)
        {
            var result = LoadCore<T>();
            if (result.Kind is SecureStoreLoadResultKind.Unavailable or SecureStoreLoadResultKind.Corrupted) { _locked = true; }
            return result;
        }
    }

    private SecureStoreLoadResult<T> LoadCore<T>()
    {
        if (!File.Exists(_filePath))
        {
            return SecureStoreLoadResult<T>.Missing();
        }

        byte[] key;
        try
        {
            key = _key(false);
        }
        catch (Exception exception)
        {
            return SecureStoreLoadResult<T>.Unavailable(exception.Message);
        }

        byte[] encrypted;
        try
        {
            encrypted = File.ReadAllBytes(_filePath);
        }
        catch (Exception exception)
        {
            return SecureStoreLoadResult<T>.Unavailable($"无法读取加密文件：{exception.Message}");
        }

        try
        {
            var clear = AesGcmBox.Open(encrypted, key);
            var value = JsonSerializer.Deserialize<T>(clear);
            return value is null
                ? SecureStoreLoadResult<T>.Corrupted("加密数据解码失败。")
                : SecureStoreLoadResult<T>.Loaded(value);
        }
        catch (Exception exception)
        {
            return SecureStoreLoadResult<T>.Corrupted($"加密数据验证或解码失败：{exception.Message}");
        }
    }

    public bool Save<T>(T value)
    {
        lock (_gate)
        {
            if (_locked) { return false; }
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
                var exists = File.Exists(_filePath);
                var key = _key(!exists);
                // An existing archive must authenticate before any replacement,
                // even when the caller did not load it first.
                if (exists) { _ = AesGcmBox.Open(File.ReadAllBytes(_filePath), key); }
                var clear = JsonSerializer.SerializeToUtf8Bytes(value);
                DpapiKeyAccessor.AtomicWrite(_filePath, AesGcmBox.Seal(clear, key));
                return true;
            }
            catch
            {
                _locked = true;
                return false;
            }
        }
    }
}
