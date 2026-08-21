import Testing
import Foundation
@testable import Velox

@Suite("Single instance")
struct SingleInstanceTests {
    @Test func noPeersKeepsThisProcess() {
        #expect(SingleInstance.shouldHandoff(peerPIDs: [], selfPID: 42) == false)
    }

    @Test func otherPIDHandsOff() {
        #expect(SingleInstance.shouldHandoff(peerPIDs: [100], selfPID: 42))
    }

    @Test func onlySelfPIDDoesNotHandoff() {
        #expect(SingleInstance.shouldHandoff(peerPIDs: [42], selfPID: 42) == false)
    }

    @Test func mixedPeersStillHandoff() {
        #expect(SingleInstance.shouldHandoff(peerPIDs: [42, 99], selfPID: 42))
    }

    @Test func showNotificationNameIsStable() {
        #expect(SingleInstance.showNotification == Constants.Notify.showExistingInstance)
    }

    @Test func runningPeersExcludeSelfPID() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        #expect(!SingleInstance.runningPeerPIDs(selfPID: selfPID).contains(selfPID))
    }

    @Test func testHostEnvironmentIsDetected() {
        #expect(
            SingleInstance.isRunningUnderTests(
                environment: ["XCTestConfigurationFilePath": "/tmp/xctest"]
            )
        )
        #expect(
            SingleInstance.isRunningUnderTests(
                environment: ["XCTestSessionIdentifier": "abc"]
            )
        )
        #expect(SingleInstance.isRunningUnderTests(environment: [:]) == false)
    }

    @Test func liveTestRunDoesNotHandoff() {
        #expect(SingleInstance.isRunningUnderTests())
        #expect(SingleInstance.handoffIfNeeded() == false)
    }
}
