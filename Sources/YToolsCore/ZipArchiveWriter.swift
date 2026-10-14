import Compression
import Foundation

/// Minimal ZIP writer (deflate or stored, UTF-8 names, no ZIP64) used by the
/// "压缩为 ZIP" file action. It never follows symbolic links, never overwrites
/// an existing archive and writes through a temporary file that is moved into
/// place only after the archive is complete.
public enum ZipArchiveWriter {
    public enum ZipError: Error, Equatable, LocalizedError {
        case tooLarge
        case unreadable(String)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .tooLarge: "单个文件或压缩包超过 4 GB，暂不支持。"
            case let .unreadable(name): "无法读取“\(name)”。"
            case .cancelled: "压缩已取消。"
            }
        }
    }

    private struct CentralEntry {
        let name: Data
        let crc: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let method: UInt16
        let dosTime: UInt16
        let dosDate: UInt16
        let offset: UInt32
        let isDirectory: Bool
    }

    /// `source` → `<parent>/<name>.zip` (or `<name> 2.zip` …). Returns the archive URL.
    @discardableResult
    public static func archive(_ source: URL, fileManager: FileManager = .default) throws -> URL {
        let parent = source.deletingLastPathComponent()
        let destination = availableURL(for: source.lastPathComponent, in: parent, fileManager: fileManager)
        let temporary = parent.appendingPathComponent(".ytools-zip-\(UUID().uuidString)")
        guard fileManager.createFile(atPath: temporary.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: temporary) else {
            throw ZipError.unreadable(parent.lastPathComponent)
        }
        var completed = false
        defer {
            try? handle.close()
            if !completed { try? fileManager.removeItem(at: temporary) }
        }

        var entries: [CentralEntry] = []
        var offset: UInt64 = 0
        for item in try plan(source, fileManager: fileManager) {
            try Task.checkCancellation()
            let name = Data(item.archivePath.utf8)
            let data: Data
            if item.isDirectory {
                data = Data()
            } else {
                guard let read = try? Data(contentsOf: item.url, options: .alwaysMapped) else {
                    throw ZipError.unreadable(item.url.lastPathComponent)
                }
                guard read.count < Int(UInt32.max) else { throw ZipError.tooLarge }
                data = read
            }
            let crc = CRC32.checksum(data)
            let deflated = item.isDirectory ? nil : deflate(data)
            let payload = deflated ?? data
            let method: UInt16 = deflated == nil ? 0 : 8
            let (dosTime, dosDate) = dosDateTime(item.modified)
            guard offset < UInt64(UInt32.max) else { throw ZipError.tooLarge }

            var header = Data()
            header.append(le32: 0x0403_4B50)
            header.append(le16: 20)
            header.append(le16: 0x0800) // UTF-8 file names
            header.append(le16: method)
            header.append(le16: dosTime)
            header.append(le16: dosDate)
            header.append(le32: crc)
            header.append(le32: UInt32(payload.count))
            header.append(le32: UInt32(data.count))
            header.append(le16: UInt16(name.count))
            header.append(le16: 0)
            header.append(name)
            try handle.write(contentsOf: header)
            try handle.write(contentsOf: payload)
            entries.append(CentralEntry(name: name, crc: crc, compressedSize: UInt32(payload.count),
                                        uncompressedSize: UInt32(data.count), method: method, dosTime: dosTime,
                                        dosDate: dosDate, offset: UInt32(offset), isDirectory: item.isDirectory))
            offset += UInt64(header.count + payload.count)
        }

        var central = Data()
        for entry in entries {
            central.append(le32: 0x0201_4B50)
            central.append(le16: 0x031E) // made by: Unix, spec 3.0
            central.append(le16: 20)
            central.append(le16: 0x0800)
            central.append(le16: entry.method)
            central.append(le16: entry.dosTime)
            central.append(le16: entry.dosDate)
            central.append(le32: entry.crc)
            central.append(le32: entry.compressedSize)
            central.append(le32: entry.uncompressedSize)
            central.append(le16: UInt16(entry.name.count))
            central.append(le16: 0) // extra
            central.append(le16: 0) // comment
            central.append(le16: 0) // disk
            central.append(le16: 0) // internal attributes
            central.append(le32: entry.isDirectory ? (0o040755 << 16) | 0x10 : (0o100644 << 16))
            central.append(le32: entry.offset)
            central.append(entry.name)
        }
        guard entries.count < Int(UInt16.max), offset + UInt64(central.count) < UInt64(UInt32.max) else { throw ZipError.tooLarge }
        var end = Data()
        end.append(le32: 0x0605_4B50)
        end.append(le16: 0)
        end.append(le16: 0)
        end.append(le16: UInt16(entries.count))
        end.append(le16: UInt16(entries.count))
        end.append(le32: UInt32(central.count))
        end.append(le32: UInt32(offset))
        end.append(le16: 0)
        try handle.write(contentsOf: central)
        try handle.write(contentsOf: end)
        try handle.synchronize()
        try handle.close()
        try fileManager.moveItem(at: temporary, to: destination)
        completed = true
        return destination
    }

    struct PlannedItem {
        let url: URL
        let archivePath: String
        let isDirectory: Bool
        let modified: Date
    }

    static func plan(_ source: URL, fileManager: FileManager) throws -> [PlannedItem] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .contentModificationDateKey]
        let root = source.lastPathComponent
        let values = try source.resourceValues(forKeys: keys)
        guard values.isSymbolicLink != true else { throw ZipError.unreadable(root) }
        guard values.isDirectory == true else {
            return [PlannedItem(url: source, archivePath: root, isDirectory: false, modified: values.contentModificationDate ?? Date())]
        }
        var items = [PlannedItem(url: source, archivePath: root + "/", isDirectory: true, modified: values.contentModificationDate ?? Date())]
        // Enumerate from the resolved path so relative names stay correct when an
        // ancestor is a symbolic link (e.g. /var → /private/var).
        let base = source.resolvingSymlinksInPath().standardizedFileURL
        let baseComponents = base.pathComponents
        guard let enumerator = fileManager.enumerator(at: base, includingPropertiesForKeys: Array(keys)) else { return items }
        for case let url as URL in enumerator {
            let itemValues = try url.resourceValues(forKeys: keys)
            if itemValues.isSymbolicLink == true { continue }
            let components = url.standardizedFileURL.pathComponents
            guard components.count > baseComponents.count,
                  Array(components.prefix(baseComponents.count)) == baseComponents else { continue }
            let relative = components.dropFirst(baseComponents.count).joined(separator: "/")
            let isDirectory = itemValues.isDirectory == true
            guard isDirectory || itemValues.isRegularFile == true else { continue }
            items.append(PlannedItem(url: url, archivePath: root + "/" + relative + (isDirectory ? "/" : ""),
                                     isDirectory: isDirectory, modified: itemValues.contentModificationDate ?? Date()))
        }
        return items
    }

    static func availableURL(for name: String, in directory: URL, fileManager: FileManager) -> URL {
        var candidate = directory.appendingPathComponent(name + ".zip")
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name) \(index).zip")
            index += 1
        }
        return candidate
    }

    /// Raw deflate (RFC 1951); nil when compression does not make the data smaller.
    static func deflate(_ data: Data) -> Data? {
        guard data.count > 64 else { return nil }
        let capacity = data.count + data.count / 16 + 1_024
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0, written < data.count else { return nil }
        output.count = written
        return output
    }

    static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max((parts.year ?? 1980) - 1980, 0)
        let time = UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2)
        let day = UInt16(min(year, 127) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
        return (time, day)
    }
}

/// IEEE 802.3 CRC-32 as used by ZIP.
public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    public static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { buffer in
            for byte in buffer.bindMemory(to: UInt8.self) {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(le32 value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
