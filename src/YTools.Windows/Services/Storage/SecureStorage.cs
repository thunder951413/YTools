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
    public static byte[] Key(bool createIfMissing)
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

        if (!createIfMissing)
        {
            throw new SecureStorageException("加密文件存在，但密钥缺失；为防止覆盖，存储已锁定。");
        }

        var key = RandomNumberGenerator.GetBytes(32);
        var encrypted = ProtectedData.Protect(key, null, DataProtectionScope.CurrentUser);
        try
        {
            AppPaths.EnsureDirectories();
            File.WriteAllBytes(AppPaths.KeyFile, encrypted);
            AppPaths.RestrictFile(AppPaths.KeyFile);
        }
        catch (Exception exception)
        {
            throw new SecureStorageException($"无法写入密钥文件：{exception.Message}");
        }

        return key;
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

    public SecureCodableStore(string name)
    {
        AppPaths.EnsureDirectories();
        _filePath = Path.Combine(AppPaths.VaultDirectory, $"{name}.v1.enc");
    }

    public SecureStoreLoadResult<T> Load<T>()
    {
        if (!File.Exists(_filePath))
        {
            return SecureStoreLoadResult<T>.Missing();
        }

        byte[] key;
        try
        {
            key = DpapiKeyAccessor.Key(createIfMissing: false);
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
        try
        {
            AppPaths.EnsureDirectories();
            var key = DpapiKeyAccessor.Key(createIfMissing: true);
            var clear = JsonSerializer.SerializeToUtf8Bytes(value);
            var combined = AesGcmBox.Seal(clear, key);
            File.WriteAllBytes(_filePath, combined);
            AppPaths.RestrictFile(_filePath);
            return true;
        }
        catch
        {
            return false;
        }
    }
}
