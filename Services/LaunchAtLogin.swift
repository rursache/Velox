import Foundation
import ServiceManagement

protocol LoginItemControlling {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemControlling {}

enum LaunchAtLogin {
    static var isTestHost: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
    }

    static func apply(_ enabled: Bool) {
        guard !isTestHost else { return }
        try? apply(enabled, to: SMAppService.mainApp)
    }

    static func apply(_ enabled: Bool, to service: LoginItemControlling) throws {
        switch (enabled, service.status) {
        case (true, .enabled), (false, .notRegistered):
            return
        case (true, _):
            try service.register()
        case (false, _):
            try service.unregister()
        }
    }
}
