import Foundation

actor FileOperationService {
    enum Operation {
        case copy
        case move
    }

    func perform(_ operation: Operation, source: URL, destinationDirectory: URL) throws {
        guard source.isFileURL, destinationDirectory.isFileURL else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let resolvedSource = source.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedDirectory = destinationDirectory.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile)
        }
        if isDirectory.boolValue && (resolvedDirectory.path == resolvedSource.path
            || resolvedDirectory.path.hasPrefix(resolvedSource.path + "/")) {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSLocalizedDescriptionKey: "目标目录不能位于源目录内部。"])
        }
        let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        switch operation {
        case .copy:
            try FileManager.default.copyItem(at: source, to: destination)
        case .move:
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }
}
