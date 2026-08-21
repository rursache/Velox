import Foundation
import Testing

@Suite("Docs")
struct DocsTests {
    @Test func releaseWorkflowBuildsAndTaps() throws {
        let yml = try Self.text(".github/workflows/release.yml")
        #expect(yml.contains("types: [published]"))
        #expect(yml.contains("Velox.app"))
        #expect(yml.contains("macos-26"))
        #expect(yml.contains("RanduSoft/macos-signing"))
        #expect(yml.contains("update-formula.yml"))
        #expect(yml.contains("formula: 'velox'"))
        #expect(yml.contains("Velox-${VERSION}.zip") || yml.contains("zip=Velox-"))
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
        #expect(agents.contains(".github/workflows/release.yml"))
        #expect(agents.contains("homebrew-tap"))
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
