import Foundation
import Testing

@Suite("Docs")
struct DocsTests {
    @Test func readmeDescribesTheCurrentProduct() throws {
        let readme = try Self.text("README.md")
        #expect(readme.contains("Raycast is bloated and slow"))
        #expect(readme.contains("buggy, opinionated, and not customizable"))
        #expect(readme.contains("⌥Space"))
        #expect(readme.contains("Remappable"))
        #expect(readme.contains("Olive"))
        #expect(readme.contains("Harbor"))
        #expect(readme.contains("Orchid"))
        #expect(readme.contains("Parchment"))
        #expect(readme.contains("result highlight"))
        #expect(readme.contains("all screens"))
        #expect(readme.contains("**off** by default"))
        #expect(readme.contains("currency"))
        #expect(readme.contains("**on** by default"))
        #expect(readme.contains("left-click opens Settings"))
        #expect(readme.contains("already-running instance"))
        #expect(readme.contains("macOS 15"))
        #expect(readme.contains("external disks"))
        #expect(readme.contains("every hour"))
        #expect(readme.contains("[MIT](LICENSE)"))
        #expect(readme.contains(".github/screenshot.jpg"))
        #expect(!readme.contains("Build & run"))
        #expect(!readme.contains("xcodebuild"))
        #expect(!readme.contains("| Action |"))
    }

    @Test func repoIncludesMitLicense() throws {
        let license = try Self.text("LICENSE")
        #expect(license.contains("MIT License"))
        #expect(license.contains("Permission is hereby granted"))
    }

    @Test func agentsListsEveryTestFile() throws {
        let agents = try Self.text("AGENTS.md")
        let names = try FileManager.default.contentsOfDirectory(at: Self.testsDirectory, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix("Tests.swift") }
            .sorted()
        #expect(!names.isEmpty)
        for name in names {
            let scope = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
            #expect(agents.contains("`\(scope)`"), "AGENTS.md should list \(scope)")
        }
    }

    @Test func projectHasNoAppSandboxCapability() throws {
        let pbx = try Self.text("Velox.xcodeproj/project.pbxproj")
        #expect(!pbx.contains("ENABLE_APP_SANDBOX"))
        #expect(!pbx.contains("ENABLE_INCOMING_NETWORK_CONNECTIONS"))
        #expect(!pbx.contains("ENABLE_OUTGOING_NETWORK_CONNECTIONS"))
        #expect(!pbx.contains("ENABLE_RESOURCE_ACCESS_"))
        #expect(pbx.contains("ENABLE_HARDENED_RUNTIME = YES"))
    }

    @Test func agentsKeepsArchitectureOutOfTheReadme() throws {
        let agents = try Self.text("AGENTS.md")
        #expect(agents.contains("README is a short product page"))
        #expect(agents.contains("ro.randusoft.velox"))
        #expect(agents.contains("math, then currency"))
        #expect(agents.contains("Everyday Apple apps"))
    }

    private static func text(_ fileName: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(fileName), encoding: .utf8)
    }

    private static var testsDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    }

    private static var repoRoot: URL {
        testsDirectory.deletingLastPathComponent()
    }
}
