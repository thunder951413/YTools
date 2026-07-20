import Darwin
import Foundation

/// Lightweight local directory invalidation. It never reads file contents and
/// only marks the application index dirty when an Applications root changes.
final class ApplicationDirectoryWatcher: @unchecked Sendable {
    private let sources: [DispatchSourceFileSystemObject]

    init(urls: [URL], onChange: @escaping @Sendable () -> Void) {
        var created: [DispatchSourceFileSystemObject] = []
        let queue = DispatchQueue(label: "com.ztools.native.application-directory-watcher")
        for url in urls {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: queue
            )
            source.setEventHandler(handler: onChange)
            source.setCancelHandler { close(descriptor) }
            source.resume()
            created.append(source)
        }
        sources = created
    }

    deinit {
        sources.forEach { $0.cancel() }
    }
}
