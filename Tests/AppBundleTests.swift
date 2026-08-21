import Foundation
import Security
import Testing

@Suite("App bundle")
struct AppBundleTests {
    @Test func usesIconComposerAppIcon() {
        let iconName = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String
        #expect(iconName == "Icon")
        let iconFile = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String
        #expect(iconFile == "Icon")
        #expect(Bundle.main.url(forResource: "Icon", withExtension: "icns") != nil)
    }

    @Test func minimumSystemVersionMatchesDeploymentTarget() {
        let version = Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String
        #expect(version == "15.0")
    }

    @Test func identityAndCategoryMatchTheProduct() {
        #expect(Bundle.main.bundleIdentifier == "ro.randusoft.velox")
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true)
        #expect(
            Bundle.main.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
                == "public.app-category.utilities"
        )
    }

    @Test func signedWithRanduSoftTeam() throws {
        var staticCode: SecStaticCode?
        let create = SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode)
        #expect(create == errSecSuccess)
        let code = try #require(staticCode)

        var info: CFDictionary?
        let copy = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        #expect(copy == errSecSuccess)
        let team = (info as NSDictionary?)?[kSecCodeInfoTeamIdentifier] as? String
        #expect(team == "3999533L99")
    }
}
