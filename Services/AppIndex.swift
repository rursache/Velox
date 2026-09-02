import Foundation
import AppKit
import Darwin

actor AppIndex {
    static let shared = AppIndex()
    nonisolated let signal = NotificationToken()

    private(set) var apps: [AppEntry] = []
    private(set) var isReady = false
    private(set) var lastRebuildAt: Date?
    private var rebuildGeneration: UInt64 = 0
    private var rebuildTask: Task<Void, Never>?
    private var queuedRebuild = false

    func rebuild() async {
        if let rebuildTask {
            queuedRebuild = true
            await rebuildTask.value
            return
        }
        queuedRebuild = false
        let task = Task { await self.performRebuild() }
        rebuildTask = task
        await task.value
        rebuildTask = nil
        if queuedRebuild {
            queuedRebuild = false
            await rebuild()
        }
    }

    private func performRebuild() async {
        rebuildGeneration &+= 1
        let generation = rebuildGeneration
        let started = CFAbsoluteTimeGetCurrent()
        let previousIDs = Set(apps.map(\.id))
        let discovered = await Task.detached(priority: .userInitiated) {
            MountedVolumeIndex.refresh()
            return AppScanner.scan()
        }.value
        guard generation == rebuildGeneration else { return }
        apps = discovered
        isReady = true
        lastRebuildAt = Date()
        if previousIDs != Set(apps.map(\.id)) {
            await MainActor.run {
                AppIconCache.removeAll()
            }
        }
        let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
        print(String(format: "[Velox] Indexed %d apps in %.1f ms", discovered.count, ms))
        await MainActor.run {
            NotificationCenter.default.post(name: .veloxIndexReady, object: signal)
        }
    }

    func replaceAppsForTesting(_ apps: [AppEntry]) {
        self.apps = apps
        isReady = true
        lastRebuildAt = Date()
    }

    func isStale(
        now: Date = Date(),
        maxAge: TimeInterval = AppIndexWatchPolicy.panelShowMaxAge
    ) -> Bool {
        AppIndexWatchPolicy.isStale(lastRebuild: lastRebuildAt, now: now, maxAge: maxAge)
    }

    func search(query: String, limit: Int, includeSystem: Bool) -> [(app: AppEntry, score: Int)] {
        AppSearch.ranked(apps: apps, query: query, limit: limit, includeSystem: includeSystem)
    }

    var count: Int { apps.count }
}

enum AppSearch {
    static func ranked(
        apps: [AppEntry],
        query: String,
        limit: Int,
        includeSystem: Bool,
        isMounted: (String) -> Bool = { MountedVolumeIndex.contains($0) }
    ) -> [(app: AppEntry, score: Int)] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return [] }
        let qLower = q.lowercased()

        var scored: [(AppEntry, Int)] = []
        scored.reserveCapacity(min(apps.count, 64))

        for app in apps {
            if !includeSystem && app.isSystem { continue }
            guard AppPresence.isAvailable(app, isMounted: isMounted) else { continue }
            let nameScore = FuzzyMatcher.match(normalizedQuery: qLower, in: app.nameLower, original: app.name).score
            let fileScore = app.fileNameLower == app.nameLower
                ? 0
                : FuzzyMatcher.match(normalizedQuery: qLower, in: app.fileNameLower, original: app.fileName).score
            let best = max(nameScore, fileScore)
            if best > 0 {
                scored.append((app, best))
            }
        }

        scored.sort { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.name.count < rhs.0.name.count
        }

        return scored.prefix(limit).map { (app: $0.0, score: $0.1) }
    }
}

enum AppVisibility {
    static func isUserFacing(
        name: String,
        path: String,
        isUIElement: Bool,
        isBackgroundOnly: Bool
    ) -> Bool {
        if isBackgroundOnly { return false }
        if hasInternalSuffix(name) { return false }
        if isUIElement && isAppleInternalPath(path) { return false }
        return true
    }

    static func infoBool(_ bundle: Bundle?, key: String) -> Bool {
        guard let raw = bundle?.object(forInfoDictionaryKey: key) else { return false }
        switch raw {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            return ["1", "true", "yes"].contains(value.lowercased())
        default:
            return false
        }
    }

    static func hasInternalSuffix(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("Helper")
            || trimmed.hasSuffix("Agent")
            || trimmed.hasSuffix("Stub")
    }

    /// Everyday Apple apps stay searchable. CoreServices extras stay `isSystem`
    static func isSystemApp(_ path: String) -> Bool {
        if isFinder(path) { return false }
        return isAppleInternalPath(path)
    }

    static func isFinder(_ path: String) -> Bool {
        path.hasSuffix("/CoreServices/Finder.app")
    }

    /// Notes, Safari, Mail, Terminal: /System/Applications and Cryptex, not CoreServices
    static func isEverydayApplePath(_ path: String) -> Bool {
        if path.hasPrefix("/System/Applications/") { return true }
        if path.hasPrefix("/System/Volumes/Data/Applications/") { return true }
        return path.contains("/Cryptexes/") && path.contains("/Applications/")
    }

    /// CoreServices internals, not /System/Applications or Cryptex (Safari, Notes)
    static func isAppleInternalPath(_ path: String) -> Bool {
        if isEverydayApplePath(path) { return false }
        return path.hasPrefix("/System/")
    }
}

enum UserHome {
    static var path: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    static var applicationsDirectory: URL {
        URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("Applications", isDirectory: true)
    }

    static func isContainerPath(_ path: String) -> Bool {
        path.contains("/Library/Containers/")
    }
}

enum MountedVolumeIndex: Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var prefixes: [String] = []

    // No `.skipHiddenVolumes`: disks mounted `nobrowse` still hold apps and must count as mounted
    static func refresh(
        urls: [URL]? = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: []
        )
    ) {
        let next = (urls ?? []).compactMap { url -> String? in
            let prefix = normalizedPrefix(for: url)
            if prefix == "/" { return nil }
            if prefix == "/System/Volumes/Data/" { return nil }
            guard prefix.hasPrefix("/Volumes/") else { return nil }
            return prefix
        }
        lock.lock()
        prefixes = next
        lock.unlock()
    }

    static func contains(_ path: String) -> Bool {
        guard AppPresence.isVolumeBacked(path) else { return true }
        lock.lock()
        let snapshot = prefixes
        lock.unlock()
        return snapshot.contains { path.hasPrefix($0) }
    }

    static func normalizedPrefix(for url: URL) -> String {
        let path = url.resolvingSymlinksInPath().path
        return path.hasSuffix("/") ? path : path + "/"
    }
}

enum AppPresence {
    static func isVolumeBacked(_ path: String) -> Bool {
        path.hasPrefix("/Volumes/")
    }

    static func isAvailable(
        _ app: AppEntry,
        isMounted: (String) -> Bool = { MountedVolumeIndex.contains($0) }
    ) -> Bool {
        guard isVolumeBacked(app.path) else { return true }
        return isMounted(app.path)
    }
}

enum ExternalVolumeRoots {
    struct Candidate: Equatable, Sendable {
        var url: URL
        var isLocal: Bool?
        var isRootFileSystem: Bool?
        var hasApplications: Bool
        var isBrowsable: Bool? = true
    }

    static func applicationsDirectories(
        from candidates: [Candidate],
        bootPath: String = "/"
    ) -> [URL] {
        let boot = URL(fileURLWithPath: bootPath).resolvingSymlinksInPath().standardizedFileURL.path
        return candidates.compactMap { candidate in
            if candidate.isRootFileSystem == true { return nil }
            if candidate.isLocal == false { return nil }
            guard candidate.hasApplications else { return nil }
            let resolved = candidate.url.resolvingSymlinksInPath().standardizedFileURL.path
            if resolved == boot || resolved == "/System/Volumes/Data" { return nil }
            if candidate.isBrowsable == false, !isUserDiskMountPoint(candidate.url.path) {
                return nil
            }
            return candidate.url.appendingPathComponent("Applications", isDirectory: true)
        }
    }

    /// Hidden (`nobrowse`) volumes qualify only when mounted directly under /Volumes like a normal disk.
    /// Keeps Time Machine snapshot mounts, simulator runtimes, and cryptexes out of the index
    static func isUserDiskMountPoint(_ path: String) -> Bool {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard components.count == 3, components[1] == "Volumes" else { return false }
        let name = components[2]
        return !name.hasPrefix(".") && !name.hasPrefix("com.apple.TimeMachine")
    }

    static func applicationsDirectories() -> [URL] {
        applicationsDirectories(from: liveCandidates())
    }

    static func liveCandidates() -> [Candidate] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.volumeIsLocalKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey]
        guard let urls = fm.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: []
        ) else { return [] }

        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: keys)
            if values?.volumeIsRootFileSystem == true { return nil }
            if values?.volumeIsLocal == false { return nil }
            if values?.volumeIsBrowsable == false, !isUserDiskMountPoint(url.path) { return nil }
            let apps = url.appendingPathComponent("Applications", isDirectory: true)
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: apps.path, isDirectory: &isDir) && isDir.boolValue
            return Candidate(
                url: url,
                isLocal: values?.volumeIsLocal,
                isRootFileSystem: values?.volumeIsRootFileSystem,
                hasApplications: exists,
                isBrowsable: values?.volumeIsBrowsable
            )
        }
    }
}

enum VolumeWatcher {
    static let notifications: [NSNotification.Name] = [
        NSWorkspace.didMountNotification,
        NSWorkspace.didUnmountNotification,
        NSWorkspace.didRenameVolumeNotification
    ]

    @discardableResult
    static func observe(_ handler: @escaping @Sendable () -> Void) -> [NSObjectProtocol] {
        notifications.map { name in
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { _ in
                MountedVolumeIndex.refresh()
                handler()
            }
        }
    }
}

enum AppScanner {
    private static let extraApps: [URL] = [
        URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    ]

    static func scanRoots(
        external: [URL] = ExternalVolumeRoots.applicationsDirectories()
    ) -> [URL] {
        var urls: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications", isDirectory: true),
            UserHome.applicationsDirectory
        ]
        let fm = FileManager.default
        if let local = fm.urls(for: .applicationDirectory, in: .localDomainMask).first {
            urls.append(local)
        }
        if let user = fm.urls(for: .applicationDirectory, in: .userDomainMask).first,
           !UserHome.isContainerPath(user.path) {
            urls.append(user)
        }
        if let system = fm.urls(for: .applicationDirectory, in: .systemDomainMask).first {
            urls.append(system)
        }
        urls.append(contentsOf: external)
        var seen = Set<String>()
        return urls.filter { seen.insert($0.resolvingSymlinksInPath().path).inserted }
    }

    static func scan() -> [AppEntry] {
        var seen = Set<String>()
        var results: [AppEntry] = []
        results.reserveCapacity(256)

        for root in scanRoots() {
            walk(root: root, depth: 0, maxDepth: 4, seen: &seen, results: &results)
        }
        for url in extraApps {
            collectApp(at: url, seen: &seen, results: &results)
        }

        results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return results
    }

    private static func walk(
        root: URL,
        depth: Int,
        maxDepth: Int,
        seen: inout Set<String>,
        results: inout [AppEntry]
    ) {
        guard depth <= maxDepth else { return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey, .isPackageKey, .isAliasFileKey],
            options: []
        ) else { return }

        for url in entries {
            if url.lastPathComponent.hasPrefix(".") { continue }
            var target = url
            var values = try? url.resourceValues(forKeys: [
                .isApplicationKey, .isPackageKey, .isDirectoryKey, .isAliasFileKey
            ])
            if values?.isAliasFile == true {
                guard let resolved = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]) else {
                    continue
                }
                target = resolved
                values = try? resolved.resourceValues(forKeys: [
                    .isApplicationKey, .isPackageKey, .isDirectoryKey
                ])
            }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: target.path, isDirectory: &isDir) else { continue }

            let isApp = values?.isApplication == true || target.pathExtension == "app"

            if isApp {
                collectApp(at: target, seen: &seen, results: &results)
                continue
            }

            if isDir.boolValue && values?.isPackage != true {
                walk(
                    root: target,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    seen: &seen,
                    results: &results
                )
            }
        }
    }

    private static func collectApp(
        at url: URL,
        seen: inout Set<String>,
        results: inout [AppEntry]
    ) {
        let resolved = url.resolvingSymlinksInPath()
        let path = resolved.path
        guard !seen.contains(path) else { return }
        seen.insert(path)

        let bundle = Bundle(url: resolved)
        let name = displayName(for: resolved, bundle: bundle)
        let isUIElement = AppVisibility.infoBool(bundle, key: "LSUIElement")
        let isBackgroundOnly = AppVisibility.infoBool(bundle, key: "LSBackgroundOnly")
        guard AppVisibility.isUserFacing(
            name: name,
            path: path,
            isUIElement: isUIElement,
            isBackgroundOnly: isBackgroundOnly
        ) else { return }

        results.append(AppEntry(
            name: name,
            path: path,
            bundleIdentifier: bundle?.bundleIdentifier,
            url: resolved,
            fileName: url.deletingPathExtension().lastPathComponent,
            isSystem: AppVisibility.isSystemApp(path)
        ))
    }

    private static func displayName(for url: URL, bundle: Bundle?) -> String {
        if let bundle {
            if let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !display.isEmpty {
                return display
            }
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
                return name
            }
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}
