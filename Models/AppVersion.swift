import Foundation

enum AppVersion {
    static func label(
        short: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        build: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    ) -> String {
        let version = normalized(short)
        let buildNumber = normalized(build)
        if let version, let buildNumber {
            return "v\(version) (\(buildNumber))"
        }
        if let version {
            return "v\(version)"
        }
        return Constants.App.unknownVersionLabel
    }

    private static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }
        return value.isEmpty ? nil : value
    }
}
