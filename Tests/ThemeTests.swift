import Testing
import AppKit
@testable import Velox

@Suite("Theme catalog")
struct ThemeCatalogTests {
    @Test func glassIsTheDefaultAndUnknownFallback() {
        #expect(Constants.Defaults.themeID == .glass)
        #expect(ThemeCatalog.theme(for: nil).id == .glass)
        #expect(ThemeCatalog.theme(for: "nope").id == .glass)
        #expect(ThemeID(rawValue: "glass") == .glass)
        #expect(ThemeID.parse("spotlight") == .glass)
        #expect(ThemeID.parse("frost") == .snow)
        #expect(ThemeID.parse("graphite") == .midnight)
        #expect(ThemeID.parse(nil) == nil)
        #expect(ThemeCatalog.theme(for: "spotlight").id == .glass)
        #expect(ThemeCatalog.glass.name == "Glass")
        #expect(ThemeCatalog.midnight.name == "Midnight")
        #expect(ThemeCatalog.snow.name == "Snow")
    }

    @Test func catalogHasUniqueThemes() {
        let ids = ThemeCatalog.all.map(\.id)
        #expect(ThemeCatalog.all.count == 8)
        #expect(Set(ids).count == 8)
        #expect(ThemeID.allCases.count == 8)
        #expect(ThemeCatalog.all.map(\.name) == [
            "Glass", "Clear", "Midnight", "Snow",
            "Olive", "Harbor", "Orchid", "Parchment"
        ])
    }

    @Test func glassMatchesCurrentChrome() {
        let theme = ThemeCatalog.glass
        #expect(theme.material == .hudWindow)
        #expect(theme.hairline.width == 0.5)
        #expect(theme.hairline.kind == .white(alpha: 0.14))
        #expect(theme.wash == .none)
        #expect(theme.legibility == .dark)
        #expect(theme.rowCornerRadius == 8)
        #expect(theme.dividerOpacity == 0.35)
        #expect(theme.materialRaw == NSVisualEffectView.Material.hudWindow.rawValue)
    }

    @Test func barThemesChangeTheWash() {
        #expect(ThemeCatalog.midnight.wash.alpha > ThemeCatalog.glass.wash.alpha)
        #expect(ThemeCatalog.snow.wash.white > ThemeCatalog.midnight.wash.white)
        #expect(ThemeCatalog.snow.wash.alpha > ThemeCatalog.clear.wash.alpha)
        #expect(ThemeCatalog.midnight.previewWhite < ThemeCatalog.snow.previewWhite)
        #expect(ThemeCatalog.snow.legibility == .light)
        #expect(ThemeCatalog.clear.legibility == .light)
        #expect(ThemeCatalog.midnight.legibility == .dark)
        #expect(ThemeCatalog.parchment.legibility == .light)
        #expect(ThemeCatalog.olive.wash.alpha > 0.4)
        #expect(ThemeCatalog.harbor.wash.blue > ThemeCatalog.harbor.wash.red)
        #expect(ThemeCatalog.orchid.wash.blue > ThemeCatalog.olive.wash.blue)
        #expect(ThemeCatalog.parchment.wash.red > ThemeCatalog.parchment.wash.blue)
        for theme in ThemeCatalog.all where theme.id != .glass {
            #expect(theme.materialRaw != ThemeCatalog.glass.materialRaw || theme.wash != ThemeCatalog.glass.wash)
        }
    }

    @Test func highlightIsIndependentOfBarTheme() {
        #expect(Constants.Defaults.highlightID == .accent)
        #expect(HighlightID.parse("soft") == .soft)
        #expect(HighlightCatalog.all == [.accent, .soft, .contrast])
        #expect(HighlightCatalog.style(for: .accent).invertLabels)
        #expect(HighlightCatalog.style(for: .soft).invertLabels == false)
        #expect(HighlightCatalog.style(for: .contrast).invertLabels)
        #expect(HighlightCatalog.style(for: .accent) != HighlightCatalog.style(for: .soft))
        #expect(HighlightID.accent.title == "Accent")
        #expect(HighlightID.contrast.title == "Contrast")
    }

    @Test func themeIDsRoundTrip() {
        for id in ThemeID.allCases {
            #expect(ThemeID(rawValue: id.rawValue) == id)
            #expect(ThemeCatalog.theme(for: id).id == id)
        }
    }
}

@Suite("Panel metrics")
struct PanelMetricsTests {
    @Test func standardMatchesPreviousConstants() {
        let metrics = PanelMetrics.standard
        #expect(metrics.width == 680)
        #expect(metrics.searchRowHeight == 56)
        #expect(metrics.resultRowHeight == 48)
        #expect(metrics.resultsBottomPad == 8)
        #expect(metrics.topAnchorFraction == 0.22)
        #expect(metrics.cornerRadius == 16)
        #expect(metrics.snapThreshold == 20)
        #expect(Constants.Panel.width == metrics.width)
        #expect(Constants.Panel.cornerRadius == metrics.cornerRadius)
        #expect(Constants.Defaults.panelCornerRadius == 16)
    }

    @Test func radiusClampsToEvenSteps() {
        #expect(PanelMetrics.cornerRadiusRange == 12...48)
        #expect(PanelMetrics.cornerRadiusStep == 2)
        #expect(PanelMetrics.clampedRadius(3) == 12)
        #expect(PanelMetrics.clampedRadius(50) == 48)
        #expect(PanelMetrics.clampedRadius(15) == 16)
        #expect(PanelMetrics.clampedRadius(16) == 16)
        #expect(PanelMetrics.clampedRadius(17) == 18)
        #expect(PanelMetrics.cornerRadiusRange.contains(PanelMetrics.standard.cornerRadius))
    }

    @Test func searchAndResultColumnsAlign() {
        let metrics = PanelMetrics.standard
        let queryX = metrics.barPaddingX + metrics.iconColumn + metrics.stackSpacing
        let resultX = metrics.resultInsetX + metrics.resultInsetX + metrics.iconColumn + metrics.stackSpacing
        #expect(queryX == resultX)
        #expect(queryX == 60)
    }
}

@Suite("Panel placement")
struct PanelPlacementTests {
    @Test func mousePolicyPrefersTheScreenUnderTheCursor() {
        let frames = [
            NSRect(x: 0, y: 0, width: 800, height: 600),
            NSRect(x: 800, y: 0, width: 800, height: 600)
        ]
        #expect(
            PanelPlacement.screenIndex(
                mouse: NSPoint(x: 1000, y: 100),
                frames: frames,
                mainIndex: 0,
                policy: .mouse
            ) == 1
        )
        #expect(
            PanelPlacement.screenIndex(
                mouse: NSPoint(x: -20, y: 10),
                frames: frames,
                mainIndex: 0,
                policy: .mouse
            ) == 0
        )
    }

    @Test func allScreensKeepsTheMouseScreenAsPrimary() {
        let frames = [
            NSRect(x: 0, y: 0, width: 800, height: 600),
            NSRect(x: 800, y: 0, width: 800, height: 600)
        ]
        #expect(
            PanelPlacement.screenIndex(
                mouse: NSPoint(x: 1000, y: 100),
                frames: frames,
                mainIndex: 0,
                policy: .allScreens
            ) == 1
        )
        #expect(
            PanelPlacement.replicaScreenIndexes(primary: 1, count: 2, policy: .allScreens) == [0]
        )
        #expect(PanelPlacement.replicaScreenIndexes(primary: 0, count: 1, policy: .allScreens).isEmpty)
        #expect(PanelPlacement.replicaScreenIndexes(primary: 0, count: 2, policy: .mouse).isEmpty)
        #expect(PanelPlacement.replicaScreenIndexes(primary: nil, count: 3, policy: .allScreens) == [1, 2])
    }

    @Test func activeWindowPolicyPrefersTheMainScreen() {
        let frames = [
            NSRect(x: 0, y: 0, width: 800, height: 600),
            NSRect(x: 800, y: 0, width: 800, height: 600)
        ]
        #expect(
            PanelPlacement.screenIndex(
                mouse: NSPoint(x: 1000, y: 100),
                frames: frames,
                mainIndex: 0,
                policy: .activeWindow
            ) == 0
        )
        #expect(
            PanelPlacement.screenIndex(
                mouse: NSPoint(x: 1000, y: 100),
                frames: frames,
                mainIndex: nil,
                policy: .activeWindow
            ) == 1
        )
    }

    @Test func screenPolicyTitlesAreSet() {
        #expect(PanelScreenPolicy.mouse.title == "Screen with mouse")
        #expect(PanelScreenPolicy.activeWindow.title == "Screen with active window")
        #expect(PanelScreenPolicy.allScreens.title == "Show on all screens")
        #expect(Constants.Defaults.panelScreenPolicy == .mouse)
        #expect(PanelScreenPolicy.mouse.showsOnEveryScreen == false)
        #expect(PanelScreenPolicy.allScreens.showsOnEveryScreen)
    }

    @Test func preferenceKeysAreStable() {
        #expect(Constants.PreferenceKey.themeID == "themeID")
        #expect(Constants.PreferenceKey.highlightID == "highlightID")
        #expect(Constants.PreferenceKey.panelCornerRadius == "panelCornerRadius")
        #expect(Constants.PreferenceKey.panelScreenPolicy == "panelScreenPolicy")
        #expect(Constants.Notify.themeDidChange.rawValue == "veloxThemeDidChange")
        #expect(Constants.Notify.panelPositionDidReset.rawValue == "veloxPanelPositionDidReset")
        #expect(Constants.Notify.showPanelPreview.rawValue == "veloxShowPanelPreview")
        #expect(Constants.Notify.hidePanelPreview.rawValue == "veloxHidePanelPreview")
    }
}

@Suite("Theme application")
struct ThemeApplicationTests {
    @Test @MainActor func applyUpdatesMaterialAndRadiusWithoutRelaunch() {
        let view = VisualEffectContainer(frame: NSRect(x: 0, y: 0, width: 200, height: 56))
        #expect(view.appliedMaterial == .hudWindow)
        #expect(view.appliedCornerRadius == 16)

        view.apply(theme: ThemeCatalog.snow, cornerRadius: 20)
        #expect(view.appliedMaterial == ThemeCatalog.snow.material)
        #expect(view.appliedCornerRadius == 20)
        #expect(view.appliedWash == ThemeCatalog.snow.wash)

        view.apply(theme: ThemeCatalog.midnight, cornerRadius: 12)
        #expect(view.appliedMaterial == ThemeCatalog.midnight.material)
        #expect(view.appliedCornerRadius == 12)
        #expect(view.appliedWash == ThemeCatalog.midnight.wash)
    }

    @Test func searchViewCarriesTheSelectedTheme() {
        #expect(ThemeCatalog.midnight.id != ThemeCatalog.glass.id)
        #expect(ThemeCatalog.clear.material != ThemeCatalog.glass.material)
        #expect(ThemeCatalog.snow.wash != ThemeCatalog.midnight.wash)
    }
}
