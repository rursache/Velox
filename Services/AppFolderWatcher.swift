import Foundation
import Darwin

enum AppIndexWatchPolicy {
    static var debounceInterval: TimeInterval { Constants.Index.folderDebounce }
    static var periodicInterval: TimeInterval { Constants.Index.periodicRefresh }
    static var panelShowMaxAge: TimeInterval { Constants.Index.panelShowMaxAge }

    static func shouldWatch(_ url: URL) -> Bool {
        let paths = [url.path, url.resolvingSymlinksInPath().path]
        return paths.allSatisfy { path in
            !path.hasPrefix("/System/Applications")
                && !path.hasPrefix("/System/Library/")
                && !path.hasPrefix("/System/Volumes/Preboot/")
                && !path.contains("/Cryptexes/")
        }
    }

    static func watchPaths(
        from roots: [URL],
        exists: (URL) -> Bool = { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                && isDir.boolValue
        }
    ) -> [String] {
        var seen = Set<String>()
        return roots.compactMap { url in
            guard shouldWatch(url), exists(url) else { return nil }
            let path = url.resolvingSymlinksInPath().path
            guard seen.insert(path).inserted else { return nil }
            return path
        }
    }

    static func isStale(lastRebuild: Date?, now: Date, maxAge: TimeInterval) -> Bool {
        guard let lastRebuild else { return true }
        return now.timeIntervalSince(lastRebuild) >= maxAge
    }
}

/// Directory watchers for Applications folders
final class AppFolderWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var watchedPaths: [String] = []
    private let handler: () -> Void

    var paths: [String] { watchedPaths }

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    func update(paths: [String]) {
        if paths == watchedPaths { return }
        start(paths: paths)
    }

    func start(paths: [String]) {
        stop()
        var armed: [String] = []
        for path in paths {
            guard let source = Self.makeSource(path: path, handler: handler) else { continue }
            sources.append(source)
            armed.append(path)
        }
        watchedPaths = armed
        if !sources.isEmpty {
            NSLog("[Velox] Watching %d app folders", sources.count)
        }
    }

    func stop() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
        watchedPaths = []
    }

    private static func makeSource(
        path: String,
        handler: @escaping () -> Void
    ) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: eventQueue
        )
        source.setEventHandler {
            DispatchQueue.main.async(execute: handler)
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        return source
    }

    private static let eventQueue = DispatchQueue(label: "ro.randusoft.velox.folder-watch")
}
