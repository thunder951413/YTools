import Darwin
import Foundation
import YToolsCore

/// File traversal, copying and commit all run on the service actor, away from UI.
actor FileOperationService {
    enum Operation { case copy, move }
    private struct Entry {
        let source: URL
        let relativePath: String
        let directory: Bool
        let size: Int64
        let modified: Date?
    }
    func perform(_ operation: Operation, source: URL, destinationDirectory: URL,
                 progress: @escaping @Sendable (FileTransferProgress) async -> Void = { _ in }) async throws {
        guard source.isFileURL, destinationDirectory.isFileURL else { throw CocoaError(.fileWriteInvalidFileName) }
        guard try source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSLocalizedDescriptionKey: "文件传输不跟随符号链接。"])
        }
        let source = try canonicalURL(source)
        let directory = try canonicalURL(destinationDirectory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else { throw CocoaError(.fileNoSuchFile) }
        var targetIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &targetIsDirectory), targetIsDirectory.boolValue else { throw CocoaError(.fileWriteInvalidFileName) }
        if isDirectory.boolValue && (directory.path == source.path || directory.path.hasPrefix(source.path + "/")) {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSLocalizedDescriptionKey: "目标目录不能位于源目录内部。"])
        }
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        guard !exists(destination) else { throw CocoaError(.fileWriteFileExists) }
        await progress(FileTransferProgress(completedBytes: 0, totalBytes: 0, phase: .scanning))
        try Task.checkCancellation()
        let entries = try plan(source)
        let total = entries.reduce(Int64(0)) { $0 + $1.size }
        try Task.checkCancellation()
        if operation == .move && sameVolume(source, directory) {
            await progress(FileTransferProgress(completedBytes: 0, totalBytes: total, phase: .committing))
            try Task.checkCancellation()
            try commit(source, to: destination)
            await progress(FileTransferProgress(completedBytes: total, totalBytes: total, phase: .completed))
            return
        }
        let stage = directory.appendingPathComponent(".ytools-transfer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stage) }
        var completed: Int64 = 0
        var lastProgress = ContinuousClock.now
        for entry in entries {
            try Task.checkCancellation()
            let output = entry.relativePath.isEmpty ? stage : stage.appendingPathComponent(entry.relativePath)
            if entry.directory {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            } else {
                guard FileManager.default.createFile(atPath: output.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
                let input = try FileHandle(forReadingFrom: entry.source)
                let writer = try FileHandle(forWritingTo: output)
                defer { try? input.close(); try? writer.close() }
                var written: Int64 = 0
                while let data = try input.read(upToCount: 256 * 1024), !data.isEmpty {
                    try Task.checkCancellation()
                    try writer.write(contentsOf: data)
                    written += Int64(data.count)
                    completed += Int64(data.count)
                    if completed == Int64(data.count) || lastProgress.duration(to: .now) >= .milliseconds(100) || completed >= total {
                        await progress(FileTransferProgress(completedBytes: completed, totalBytes: total, phase: .copying))
                        lastProgress = .now
                    }
                }
                try writer.synchronize()
                guard written == entry.size else { throw changedSource() }
                try copyAttributes(entry.source, to: output)
            }
        }
        try Task.checkCancellation()
        try verifyUnchanged(entries, source: source)
        for entry in entries.reversed() where entry.directory {
            try copyAttributes(entry.source, to: entry.relativePath.isEmpty ? stage : stage.appendingPathComponent(entry.relativePath))
        }
        await progress(FileTransferProgress(completedBytes: completed, totalBytes: total, phase: .committing))
        try Task.checkCancellation()
        try commit(stage, to: destination)
        // Commit is the cancellation boundary. A completed target must stay intact.
        if operation == .move { try FileManager.default.removeItem(at: source) }
        await progress(FileTransferProgress(completedBytes: total, totalBytes: total, phase: .completed))
    }
    private func canonicalURL(_ url: URL) throws -> URL {
        guard let path = realpath(url.path, nil) else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT) }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path))
    }
    private func plan(_ source: URL) throws -> [Entry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        func entry(_ url: URL) throws -> Entry {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true, values.isDirectory == true || values.isRegularFile == true else {
                throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSLocalizedDescriptionKey: "文件传输不跟随符号链接，也不复制特殊设备文件。"])
            }
            return Entry(source: url, relativePath: url == source ? "" : String(url.path.dropFirst(source.path.count + 1)),
                         directory: values.isDirectory == true, size: values.isDirectory == true ? 0 : Int64(values.fileSize ?? 0), modified: values.contentModificationDate)
        }
        var result = [try entry(source)]
        if result[0].directory {
            var enumerationError: Error?
            guard let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: Array(keys), errorHandler: { _, error in enumerationError = error; return false }) else { throw CocoaError(.fileReadUnknown) }
            for case let url as URL in enumerator { result.append(try entry(url)) }
            if let enumerationError { throw enumerationError }
        }
        return result
    }
    private func verifyUnchanged(_ entries: [Entry], source: URL) throws {
        let current = try plan(source)
        let previous = Dictionary(uniqueKeysWithValues: entries.map { ($0.relativePath, $0) })
        guard current.count == entries.count, current.allSatisfy({ entry in
            guard let old = previous[entry.relativePath] else { return false }
            return old.directory == entry.directory && old.size == entry.size && old.modified == entry.modified
        }) else { throw changedSource() }
    }
    private func changedSource() -> CocoaError { CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "源项目在传输中发生变化，请重试；源文件未删除。"]) }
    private func copyAttributes(_ source: URL, to destination: URL) throws {
        // Preserve extended attributes, resource forks, permissions, ACLs and dates.
        guard copyfile(source.path, destination.path, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
    private func exists(_ url: URL) -> Bool { (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil }
    private func sameVolume(_ source: URL, _ destination: URL) -> Bool {
        var lhs = stat(), rhs = stat()
        return Darwin.lstat(source.path, &lhs) == 0 && Darwin.lstat(destination.path, &rhs) == 0 && lhs.st_dev == rhs.st_dev
    }
    private func commit(_ source: URL, to destination: URL) throws {
        guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            if errno == EEXIST { throw CocoaError(.fileWriteFileExists) }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
