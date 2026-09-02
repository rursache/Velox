import Testing
import Foundation
import AppKit
@testable import Velox

@Suite("App index")
struct AppIndexTests {
    @Test func scanFindsInstalledApps() {
        let apps = AppScanner.scan()
        #expect(!apps.isEmpty)

        let paths = apps.map(\.path)
        #expect(Set(paths).count == paths.count)
        #expect(apps.allSatisfy { $0.path.hasSuffix(".app") || $0.url.pathExtension == "app" })
        #expect(apps.allSatisfy { !$0.name.hasSuffix("Helper") && !$0.name.hasSuffix("Agent") && !$0.name.hasSuffix("Stub") })
        #expect(apps.contains { $0.fileName == "Finder" || $0.name == "Finder" })
        #expect(apps.contains { $0.bundleIdentifier == "com.apple.iCal" || $0.fileName == "Calendar" })
        #expect(!apps.contains { $0.bundleIdentifier == "com.apple.Automator.Automator-Application-Stub" })
        #expect(!apps.contains { $0.bundleIdentifier == "com.apple.IPAInstaller" })
        #expect(!apps.contains { $0.bundleIdentifier == "com.apple.AOSUIPrefPaneLauncher" })
        #expect(!apps.contains { $0.name == "Automator Application Stub" })
        #expect(!apps.contains { $0.path.hasPrefix("/System/Library/CoreServices/") && $0.fileName != "Finder" && !$0.path.contains("/CoreServices/Applications/") })
    }

    @Test func emptyQueryReturnsNothing() async {
        let index = AppIndex()
        await index.rebuild()
        let hits = await index.search(query: "", limit: 8, includeSystem: true)
        #expect(hits.isEmpty)
    }

    @Test func searchReturnsTheNamedAppFirst() async throws {
        let index = AppIndex()
        await index.rebuild()
        let apps = await index.apps
        let sample = try #require(apps.first)
        let hits = await index.search(query: sample.name, limit: 8, includeSystem: true)
        let first = try #require(hits.first)
        #expect(first.app.id == sample.id)
    }

    @Test func systemAppsCanBeExcluded() async throws {
        let index = AppIndex()
        await index.rebuild()
        let all = await index.apps
        let userApps = all.filter { !$0.isSystem }
        try #require(!userApps.isEmpty)
        let sample = userApps[0]
        let hits = await index.search(query: sample.name, limit: 20, includeSystem: false)
        #expect(hits.allSatisfy { !$0.app.isSystem })
        #expect(hits.contains { $0.app.id == sample.id })
    }

    @Test func filenameMatchRanksWhenDisplayNameDiffers() {
        let calendar = AppEntry(
            name: "日历",
            path: "/Applications/Calendar.app",
            bundleIdentifier: "com.apple.iCal",
            url: URL(fileURLWithPath: "/Applications/Calendar.app"),
            fileName: "Calendar",
            isSystem: false
        )
        let hits = AppSearch.ranked(apps: [calendar], query: "cal", limit: 8, includeSystem: true)
        #expect(hits.count == 1)
        #expect(hits[0].score > 0)
    }

    @Test func limitIsRespected() {
        let apps = (1...10).map { i in
            AppEntry(
                name: "Calc\(i)",
                path: "/Applications/Calc\(i).app",
                bundleIdentifier: nil,
                url: URL(fileURLWithPath: "/Applications/Calc\(i).app"),
                isSystem: false
            )
        }
        let hits = AppSearch.ranked(apps: apps, query: "calc", limit: 3, includeSystem: true)
        #expect(hits.count == 3)
    }

    @Test func shorterNameWinsOnTiedScore() {
        let short = AppEntry(
            name: "Notes",
            path: "/Applications/Notes.app",
            bundleIdentifier: nil,
            url: URL(fileURLWithPath: "/Applications/Notes.app")
        )
        let long = AppEntry(
            name: "Notes Extra",
            path: "/Applications/Notes Extra.app",
            bundleIdentifier: nil,
            url: URL(fileURLWithPath: "/Applications/Notes Extra.app")
        )
        let hits = AppSearch.ranked(apps: [long, short], query: "notes", limit: 8, includeSystem: true)
        #expect(hits.first?.app.name == "Notes")
    }

    @Test(arguments: [
        ("/System/Applications/Notes.app", false),
        ("/System/Applications/Calendar.app", false),
        ("/System/Applications/Utilities/Terminal.app", false),
        ("/System/Cryptexes/App/System/Applications/Safari.app", false),
        ("/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app", false),
        ("/System/Volumes/Data/Applications/Safari.app", false),
        ("/System/Library/CoreServices/Finder.app", false),
        ("/Applications/Raycast.app", false),
        ("/System/Library/CoreServices/Applications/Archive Utility.app", true),
        ("/System/Library/CoreServices/Applications/Directory Utility.app", true),
        ("/System/Library/CoreServices/Applications/Ticket Viewer.app", true)
    ])
    func classifiesEverydayAppleAppsAsUserFacing(path: String, expectedSystem: Bool) {
        #expect(AppVisibility.isSystemApp(path) == expectedSystem)
    }

    @Test func includeSystemFalseKeepsSafariAndNotes() {
        let safari = AppEntry(
            name: "Safari",
            path: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app",
            bundleIdentifier: "com.apple.Safari",
            url: URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"),
            fileName: "Safari",
            isSystem: AppVisibility.isSystemApp(
                "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"
            )
        )
        let notes = AppEntry(
            name: "Notes",
            path: "/System/Applications/Notes.app",
            bundleIdentifier: "com.apple.Notes",
            url: URL(fileURLWithPath: "/System/Applications/Notes.app"),
            fileName: "Notes",
            isSystem: AppVisibility.isSystemApp("/System/Applications/Notes.app")
        )
        let archive = AppEntry(
            name: "Archive Utility",
            path: "/System/Library/CoreServices/Applications/Archive Utility.app",
            bundleIdentifier: "com.apple.archiveutility",
            url: URL(fileURLWithPath: "/System/Library/CoreServices/Applications/Archive Utility.app"),
            fileName: "Archive Utility",
            isSystem: AppVisibility.isSystemApp(
                "/System/Library/CoreServices/Applications/Archive Utility.app"
            )
        )
        #expect(safari.isSystem == false)
        #expect(notes.isSystem == false)
        #expect(archive.isSystem)
        let hits = AppSearch.ranked(
            apps: [safari, notes, archive],
            query: "safari",
            limit: 8,
            includeSystem: false
        )
        #expect(hits.map(\.app.fileName) == ["Safari"])
        let notesHits = AppSearch.ranked(
            apps: [safari, notes, archive],
            query: "notes",
            limit: 8,
            includeSystem: false
        )
        #expect(notesHits.map(\.app.fileName) == ["Notes"])
        let archiveHits = AppSearch.ranked(
            apps: [safari, notes, archive],
            query: "archive",
            limit: 8,
            includeSystem: false
        )
        #expect(archiveHits.isEmpty)
    }

    @Test func scanMarksEverydayAppleAppsVisibleByDefault() {
        let apps = AppScanner.scan()
        let safari = apps.first { $0.bundleIdentifier == "com.apple.Safari" || $0.fileName == "Safari" }
        let notes = apps.first { $0.bundleIdentifier == "com.apple.Notes" || $0.fileName == "Notes" }
        let finder = apps.first { $0.fileName == "Finder" || $0.name == "Finder" }
        #expect(safari != nil)
        #expect(safari?.isSystem == false)
        #expect(notes != nil)
        #expect(notes?.isSystem == false)
        #expect(finder != nil)
        #expect(finder?.isSystem == false)
        let hidden = AppSearch.ranked(apps: apps, query: "safari", limit: 8, includeSystem: false)
        #expect(hidden.contains { $0.app.fileName == "Safari" || $0.app.name == "Safari" })
        let notesHits = AppSearch.ranked(apps: apps, query: "notes", limit: 8, includeSystem: false)
        #expect(notesHits.contains { $0.app.fileName == "Notes" || $0.app.name == "Notes" })
    }

    @Test(arguments: [
        ("Automator Application Stub", "/System/Library/CoreServices/Automator Application Stub.app", true, false, false),
        ("iOS App Installer", "/System/Library/CoreServices/Applications/iOS App Installer.app", true, false, false),
        ("AOSUIPrefPaneLauncher", "/System/Library/CoreServices/AOSUIPrefPaneLauncher.app", true, false, false),
        ("Software Update", "/System/Library/CoreServices/Software Update.app", true, false, false),
        ("Calendar Helper", "/System/Library/CoreServices/Calendar Helper.app", false, false, false),
        ("WiFiAgent", "/System/Library/CoreServices/WiFiAgent.app", true, false, false),
        ("PreviewShell", "/System/Library/CoreServices/PreviewShell.app", false, true, false)
    ])
    func hidesAppleInternals(
        name: String,
        path: String,
        isUIElement: Bool,
        isBackgroundOnly: Bool,
        expected: Bool
    ) {
        #expect(
            AppVisibility.isUserFacing(
                name: name,
                path: path,
                isUIElement: isUIElement,
                isBackgroundOnly: isBackgroundOnly
            ) == expected
        )
    }

    @Test(arguments: [
        ("Calendar", "/System/Applications/Calendar.app", false, false),
        ("Safari", "/System/Cryptexes/App/System/Applications/Safari.app", false, false),
        ("Finder", "/System/Library/CoreServices/Finder.app", false, false),
        ("Archive Utility", "/System/Library/CoreServices/Applications/Archive Utility.app", false, false),
        ("Siri", "/System/Applications/Siri.app", true, false),
        ("Time Machine", "/System/Applications/Time Machine.app", true, false),
        ("Screenshot", "/System/Applications/Utilities/Screenshot.app", true, false),
        ("System Information", "/System/Applications/Utilities/System Information.app", true, false),
        ("Raycast", "/Applications/Raycast.app", true, false),
        ("Stats", "/Applications/Stats.app", true, false)
    ])
    func keepsLaunchableApps(name: String, path: String, isUIElement: Bool, isBackgroundOnly: Bool) {
        #expect(
            AppVisibility.isUserFacing(
                name: name,
                path: path,
                isUIElement: isUIElement,
                isBackgroundOnly: isBackgroundOnly
            )
        )
    }

    @Test func infoBoolReadsPlistVariants() {
        #expect(AppVisibility.hasInternalSuffix("Automator Application Stub"))
        #expect(AppVisibility.hasInternalSuffix("WiFiAgent"))
        #expect(AppVisibility.hasInternalSuffix("Calendar Helper"))
        #expect(!AppVisibility.hasInternalSuffix("Calendar"))
        #expect(AppVisibility.isAppleInternalPath("/System/Library/CoreServices/AOSUIPrefPaneLauncher.app"))
        #expect(!AppVisibility.isAppleInternalPath("/System/Applications/Calendar.app"))
        #expect(!AppVisibility.isAppleInternalPath("/System/Cryptexes/App/System/Applications/Safari.app"))
        #expect(!AppVisibility.isAppleInternalPath("/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"))
        #expect(!AppVisibility.isAppleInternalPath("/Applications/Raycast.app"))
        #expect(AppVisibility.isFinder("/System/Library/CoreServices/Finder.app"))
        #expect(AppVisibility.isEverydayApplePath("/System/Applications/Notes.app"))
        #expect(AppVisibility.isEverydayApplePath("/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"))
    }

    @Test func externalVolumeRootsSkipBootNetworkAndEmptyDisks() {
        let boot = ExternalVolumeRoots.Candidate(
            url: URL(fileURLWithPath: "/"),
            isLocal: true,
            isRootFileSystem: true,
            hasApplications: true
        )
        let data = ExternalVolumeRoots.Candidate(
            url: URL(fileURLWithPath: "/System/Volumes/Data"),
            isLocal: true,
            isRootFileSystem: false,
            hasApplications: true
        )
        let network = ExternalVolumeRoots.Candidate(
            url: URL(fileURLWithPath: "/Volumes/Share"),
            isLocal: false,
            isRootFileSystem: false,
            hasApplications: true
        )
        let photos = ExternalVolumeRoots.Candidate(
            url: URL(fileURLWithPath: "/Volumes/Photos"),
            isLocal: true,
            isRootFileSystem: false,
            hasApplications: false
        )
        let ssd = ExternalVolumeRoots.Candidate(
            url: URL(fileURLWithPath: "/Volumes/SSD"),
            isLocal: true,
            isRootFileSystem: false,
            hasApplications: true
        )
        let roots = ExternalVolumeRoots.applicationsDirectories(from: [boot, data, network, photos, ssd])
        #expect(roots == [URL(fileURLWithPath: "/Volumes/SSD/Applications", isDirectory: true)])
    }

    @Test func hiddenDisksUnderVolumesStillIndex() {
        let nobrowse = ExternalVolumeRoots.Candidate(
            url: URL(fileURLWithPath: "/Volumes/Storage"),
            isLocal: true,
            isRootFileSystem: false,
            hasApplications: true,
            isBrowsable: false
        )
        let preboot = ExternalVolumeRoots.Candidate(
            url: URL(fileURLWithPath: "/System/Volumes/Preboot"),
            isLocal: true,
            isRootFileSystem: false,
            hasApplications: true,
            isBrowsable: false
        )
        let snapshot = ExternalVolumeRoots.Candidate(
            url: URL(fileURLWithPath: "/Volumes/.timemachine/ABC/2026-01-01-000000.backup"),
            isLocal: true,
            isRootFileSystem: false,
            hasApplications: true,
            isBrowsable: false
        )
        let localSnapshot = ExternalVolumeRoots.Candidate(
            url: URL(fileURLWithPath: "/Volumes/com.apple.TimeMachine.localsnapshots"),
            isLocal: true,
            isRootFileSystem: false,
            hasApplications: true,
            isBrowsable: false
        )
        let simulator = ExternalVolumeRoots.Candidate(
            url: URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Volumes/iOS_23F77"),
            isLocal: true,
            isRootFileSystem: false,
            hasApplications: true,
            isBrowsable: false
        )
        let browsableElsewhere = ExternalVolumeRoots.Candidate(
            url: URL(fileURLWithPath: "/Users/me/mnt/Disk"),
            isLocal: true,
            isRootFileSystem: false,
            hasApplications: true,
            isBrowsable: true
        )
        let unknown = ExternalVolumeRoots.Candidate(
            url: URL(fileURLWithPath: "/Volumes/SSD"),
            isLocal: true,
            isRootFileSystem: false,
            hasApplications: true,
            isBrowsable: nil
        )
        let roots = ExternalVolumeRoots.applicationsDirectories(
            from: [nobrowse, preboot, snapshot, localSnapshot, simulator, browsableElsewhere, unknown]
        )
        #expect(roots == [
            URL(fileURLWithPath: "/Volumes/Storage/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Users/me/mnt/Disk/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Volumes/SSD/Applications", isDirectory: true)
        ])
    }

    @Test func userDiskMountPointsAreDirectChildrenOfVolumes() {
        #expect(ExternalVolumeRoots.isUserDiskMountPoint("/Volumes/Storage"))
        #expect(ExternalVolumeRoots.isUserDiskMountPoint("/Volumes/My Disk/"))
        #expect(!ExternalVolumeRoots.isUserDiskMountPoint("/Volumes"))
        #expect(!ExternalVolumeRoots.isUserDiskMountPoint("/Volumes/.timemachine/ABC"))
        #expect(!ExternalVolumeRoots.isUserDiskMountPoint("/Volumes/.hidden"))
        #expect(!ExternalVolumeRoots.isUserDiskMountPoint("/Volumes/com.apple.TimeMachine.localsnapshots"))
        #expect(!ExternalVolumeRoots.isUserDiskMountPoint("/Volumes/Storage/Nested"))
        #expect(!ExternalVolumeRoots.isUserDiskMountPoint("/System/Volumes/Preboot"))
        #expect(!ExternalVolumeRoots.isUserDiskMountPoint("/"))
    }

    @Test func liveVolumeRootsNeverIncludeSystemOrSimulatorMounts() {
        let roots = ExternalVolumeRoots.applicationsDirectories().map(\.path)
        for root in roots {
            #expect(!root.hasPrefix("/System/Volumes/"), Comment(rawValue: root))
            #expect(!root.contains("/CoreSimulator/"), Comment(rawValue: root))
            #expect(!root.contains("/cryptexd/"), Comment(rawValue: root))
            #expect(!root.contains("/.timemachine/"), Comment(rawValue: root))
            #expect(!root.contains("com.apple.TimeMachine"), Comment(rawValue: root))
        }
    }

    @Test func nobrowseDiskOnThisMachineIsScanned() throws {
        let storage = "/Volumes/Storage/Applications"
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: storage, isDirectory: &isDir), isDir.boolValue else {
            return
        }
        let roots = AppScanner.scanRoots().map { $0.resolvingSymlinksInPath().path }
        #expect(roots.contains(storage))
        MountedVolumeIndex.refresh()
        #expect(MountedVolumeIndex.contains(storage + "/Example.app"))
    }

    @Test func mountedVolumeIndexCountsHiddenVolumes() {
        MountedVolumeIndex.refresh(urls: [
            URL(fileURLWithPath: "/", isDirectory: true),
            URL(fileURLWithPath: "/System/Volumes/Preboot", isDirectory: true),
            URL(fileURLWithPath: "/Volumes/Storage", isDirectory: true)
        ])
        #expect(MountedVolumeIndex.contains("/Volumes/Storage/Applications/WoWSilicon.app"))
        #expect(!MountedVolumeIndex.contains("/Volumes/Gone/Applications/WoWSilicon.app"))
    }

    @Test func scanRootsDedupesBootAliasesAndKeepsExternalApplications() {
        let roots = AppScanner.scanRoots(external: [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Volumes/SSD/Applications", isDirectory: true)
        ])
        let resolved = roots.map { $0.resolvingSymlinksInPath().path }
        #expect(Set(resolved).count == resolved.count)
        #expect(resolved.contains { $0.hasSuffix("/Volumes/SSD/Applications") || $0 == "/Volumes/SSD/Applications" })
        #expect(resolved.contains { $0 == URL(fileURLWithPath: "/Applications").resolvingSymlinksInPath().path })
    }

    @Test func vanishedVolumeAppsAreOmittedFromSearch() {
        let gone = AppEntry(
            name: "Travel",
            path: "/Volumes/NoSuchDisk-VeloxTest/Applications/Travel.app",
            bundleIdentifier: "com.example.travel",
            url: URL(fileURLWithPath: "/Volumes/NoSuchDisk-VeloxTest/Applications/Travel.app"),
            isSystem: false
        )
        let local = AppEntry(
            name: "Travel",
            path: "/Applications/Travel.app",
            bundleIdentifier: "com.example.travel.local",
            url: URL(fileURLWithPath: "/Applications/Travel.app"),
            isSystem: false
        )
        #expect(AppPresence.isVolumeBacked(gone.path))
        #expect(!AppPresence.isVolumeBacked(local.path))
        #expect(!AppPresence.isAvailable(gone, isMounted: { _ in false }))
        #expect(AppPresence.isAvailable(local, isMounted: { _ in true }))
        let hits = AppSearch.ranked(
            apps: [gone, local],
            query: "travel",
            limit: 8,
            includeSystem: true,
            isMounted: { !$0.hasPrefix("/Volumes/NoSuchDisk-VeloxTest") }
        )
        #expect(hits.map(\.app.path) == ["/Applications/Travel.app"])
    }

    @Test func scanRootsUseRealHomeNotContainer() {
        let roots = AppScanner.scanRoots()
        let paths = roots.map(\.path)
        #expect(paths.contains(UserHome.applicationsDirectory.path))
        #expect(!paths.contains { UserHome.isContainerPath($0) })
    }

    @Test func mountedVolumeIndexUsesPrefixNotFileExists() {
        MountedVolumeIndex.refresh(urls: [URL(fileURLWithPath: "/Volumes/SSD", isDirectory: true)])
        #expect(MountedVolumeIndex.contains("/Volumes/SSD/Applications/Travel.app"))
        #expect(!MountedVolumeIndex.contains("/Volumes/Other/Applications/Travel.app"))
        #expect(MountedVolumeIndex.contains("/Applications/Travel.app"))
        MountedVolumeIndex.refresh(urls: [
            URL(fileURLWithPath: "/", isDirectory: true),
            URL(fileURLWithPath: "/Volumes/SSD", isDirectory: true)
        ])
        #expect(!MountedVolumeIndex.contains("/Volumes/Gone/Applications/Travel.app"))
        #expect(MountedVolumeIndex.contains("/Volumes/SSD/Applications/Travel.app"))
    }

    @Test func volumeWatcherListensForMountChanges() {
        #expect(VolumeWatcher.notifications.contains(NSWorkspace.didMountNotification))
        #expect(VolumeWatcher.notifications.contains(NSWorkspace.didUnmountNotification))
        #expect(VolumeWatcher.notifications.contains(NSWorkspace.didRenameVolumeNotification))
    }

    @Test func watchPolicyUsesFolderDebounceAndPeriodicFallback() {
        #expect(AppIndexWatchPolicy.debounceInterval == Constants.Index.folderDebounce)
        #expect(AppIndexWatchPolicy.periodicInterval == Constants.Index.periodicRefresh)
        #expect(AppIndexWatchPolicy.panelShowMaxAge == Constants.Index.panelShowMaxAge)
        #expect(AppIndexWatchPolicy.debounceInterval == 1.5)
        #expect(AppIndexWatchPolicy.periodicInterval == 120)
        #expect(AppIndexWatchPolicy.panelShowMaxAge == 120)
    }

    @Test func watchPolicySkipsSystemRoots() {
        #expect(AppIndexWatchPolicy.shouldWatch(URL(fileURLWithPath: "/Applications", isDirectory: true)))
        #expect(AppIndexWatchPolicy.shouldWatch(UserHome.applicationsDirectory))
        #expect(AppIndexWatchPolicy.shouldWatch(URL(fileURLWithPath: "/Volumes/SSD/Applications", isDirectory: true)))
        #expect(!AppIndexWatchPolicy.shouldWatch(URL(fileURLWithPath: "/System/Applications", isDirectory: true)))
        #expect(!AppIndexWatchPolicy.shouldWatch(
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true)
        ))
        #expect(!AppIndexWatchPolicy.shouldWatch(
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications", isDirectory: true)
        ))
    }

    @Test func watchPathsSkipMissingAndDedup() {
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let home = URL(fileURLWithPath: "/Users/demo/Applications", isDirectory: true)
        let missing = URL(fileURLWithPath: "/Volumes/Gone/Applications", isDirectory: true)
        let paths = AppIndexWatchPolicy.watchPaths(
            from: [applications, applications, home, missing],
            exists: { $0 != missing }
        )
        #expect(paths.count == 2)
        #expect(Set(paths).count == 2)
        #expect(paths.contains(applications.resolvingSymlinksInPath().path))
        #expect(paths.contains(home.resolvingSymlinksInPath().path))
        #expect(!paths.contains { $0.contains("/Gone/") })
    }

    @Test func watchPathsIncludeLiveApplicationsRoots() {
        let paths = AppIndexWatchPolicy.watchPaths(from: AppScanner.scanRoots())
        let applications = URL(fileURLWithPath: "/Applications").resolvingSymlinksInPath().path
        #expect(paths.contains(applications))
        let home = UserHome.applicationsDirectory.resolvingSymlinksInPath().path
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: home, isDirectory: &isDir), isDir.boolValue {
            #expect(paths.contains(home))
        }
    }

    @Test func staleWhenNeverRebuiltOrPastMaxAge() {
        let now = Date()
        #expect(AppIndexWatchPolicy.isStale(lastRebuild: nil, now: now, maxAge: 30))
        #expect(!AppIndexWatchPolicy.isStale(lastRebuild: now, now: now, maxAge: 30))
        #expect(!AppIndexWatchPolicy.isStale(
            lastRebuild: now.addingTimeInterval(-29),
            now: now,
            maxAge: 30
        ))
        #expect(AppIndexWatchPolicy.isStale(
            lastRebuild: now.addingTimeInterval(-30),
            now: now,
            maxAge: 30
        ))
    }

    @Test func rebuildRecordsTimestamp() async {
        let index = AppIndex()
        #expect(await index.isStale(now: Date(), maxAge: 120))
        await index.rebuild()
        #expect(await !index.isStale(now: Date(), maxAge: 120))
        #expect(await index.isStale(now: Date().addingTimeInterval(180), maxAge: 120))
    }

    @Test func overlappingRebuildsLeaveAPopulatedIndex() async {
        let index = AppIndex()
        async let first: Void = index.rebuild()
        async let second: Void = index.rebuild()
        _ = await (first, second)
        let apps = await index.apps
        #expect(!apps.isEmpty)
        #expect(await !index.isStale(now: Date(), maxAge: 120))
    }

    @Test func folderWatcherKeepsEmptyPathsWithoutStarting() {
        let watcher = AppFolderWatcher {}
        watcher.start(paths: [])
        #expect(watcher.paths.isEmpty)
        watcher.update(paths: [])
        #expect(watcher.paths.isEmpty)
    }

    @Test func searchBeforeRebuildIsEmpty() async {
        let index = AppIndex()
        let before = await index.search(query: "Safari", limit: 8, includeSystem: true)
        #expect(before.isEmpty)
        await index.rebuild()
        let apps = await index.apps
        guard let name = apps.first?.name else {
            Issue.record("Index stayed empty after rebuild")
            return
        }
        let after = await index.search(query: name, limit: 8, includeSystem: true)
        #expect(!after.isEmpty)
    }
}
