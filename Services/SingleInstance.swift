import AppKit

enum SingleInstance {
    static let showNotification = Constants.Notify.showExistingInstance

    static func isRunningUnderTests(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        if environment["XCTestBundlePath"] != nil { return true }
        if environment["XCTestSessionIdentifier"] != nil { return true }
        return false
    }

    static func shouldHandoff(peerPIDs: [pid_t], selfPID: pid_t) -> Bool {
        peerPIDs.contains { $0 != selfPID }
    }

    static func runningPeerPIDs(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        selfPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> [pid_t] {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return [] }
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .map(\.processIdentifier)
            .filter { $0 != selfPID }
    }

    /// True when another Velox is already running and was asked to show
    @discardableResult
    static func handoffIfNeeded() -> Bool {
        if isRunningUnderTests() { return false }
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let peers = runningPeerPIDs(selfPID: selfPID)
        guard shouldHandoff(peerPIDs: peers, selfPID: selfPID) else { return false }
        DistributedNotificationCenter.default().postNotificationName(
            showNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }
}
