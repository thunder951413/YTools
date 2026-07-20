import Foundation

actor FileOperationService {
    enum Operation {
        case copy
        case move
    }

    func perform(_ operation: Operation, source: URL, destinationDirectory: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CocoaError(.fileNoSuchFile)
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
