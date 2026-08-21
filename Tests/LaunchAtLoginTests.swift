import Testing
import ServiceManagement
@testable import Velox

@Suite("Launch at login")
struct LaunchAtLoginTests {
    @Test func defaultsOn() {
        #expect(Constants.Defaults.launchAtLogin)
        #expect(Constants.PreferenceKey.launchAtLogin == "launchAtLogin")
        #expect(SettingsSearchCard.launchAtLogin == "Start at login")
    }

    @Test func registersWhenTurningOn() throws {
        let service = MockLoginItem(status: .notRegistered)
        try LaunchAtLogin.apply(true, to: service)
        #expect(service.didRegister)
        #expect(!service.didUnregister)
    }

    @Test func unregistersWhenTurningOff() throws {
        let service = MockLoginItem(status: .enabled)
        try LaunchAtLogin.apply(false, to: service)
        #expect(service.didUnregister)
        #expect(!service.didRegister)
    }

    @Test func skipsNoOpWhenAlreadyEnabled() throws {
        let service = MockLoginItem(status: .enabled)
        try LaunchAtLogin.apply(true, to: service)
        #expect(!service.didRegister)
        #expect(!service.didUnregister)
    }

    @Test func skipsNoOpWhenAlreadyOff() throws {
        let service = MockLoginItem(status: .notRegistered)
        try LaunchAtLogin.apply(false, to: service)
        #expect(!service.didRegister)
        #expect(!service.didUnregister)
    }

    @Test func testHostDoesNotTouchTheSystemService() {
        #expect(LaunchAtLogin.isTestHost)
    }
}

private final class MockLoginItem: LoginItemControlling {
    var status: SMAppService.Status
    var didRegister = false
    var didUnregister = false

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        didRegister = true
        status = .enabled
    }

    func unregister() throws {
        didUnregister = true
        status = .notRegistered
    }
}
