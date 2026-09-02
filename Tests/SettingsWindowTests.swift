import Testing
import AppKit
@testable import Velox

@Suite("Settings window")
struct SettingsWindowTests {
    @Test func centersOnVisibleFrame() {
        let visible = NSRect(x: 100, y: 80, width: 1440, height: 900)
        let size = NSSize(width: 440, height: 400)
        let frame = SettingsWindowPlacement.centeredFrame(size: size, visible: visible)
        #expect(frame.midX == visible.midX)
        #expect(frame.midY == visible.midY)
        #expect(frame.size == size)
    }

    @Test func prefersTheScreenUnderTheMouse() {
        let frames = [
            NSRect(x: 0, y: 0, width: 800, height: 600),
            NSRect(x: 800, y: 0, width: 800, height: 600)
        ]
        #expect(SettingsWindowPlacement.screenIndex(mouse: NSPoint(x: 1000, y: 100), frames: frames) == 1)
        #expect(SettingsWindowPlacement.screenIndex(mouse: NSPoint(x: 10, y: 10), frames: frames) == 0)
        #expect(SettingsWindowPlacement.screenIndex(mouse: NSPoint(x: -20, y: 10), frames: frames) == nil)
    }

    @Test func windowUsesNormalLevel() {
        #expect(SettingsWindowPlacement.windowLevel == .normal)
    }

    @Test func openingSettingsDoesNotRestoreThePreviousApp() {
        #expect(SearchPanelHideReason.shouldRestorePreviousApp(.settings) == false)
        #expect(SearchPanelHideReason.shouldRestorePreviousApp(.launchedApp) == false)
        #expect(SearchPanelHideReason.shouldRestorePreviousApp(.dismissed))
    }

    @Test func previewTapsDoNotExecute() {
        #expect(SearchPanelShowTransition.shouldRunResultAction(acceptsFocus: false) == false)
        #expect(SearchPanelShowTransition.shouldRunResultAction(acceptsFocus: true))
        #expect(SearchPanelShowTransition.shouldExitPreview(from: .preview))
        #expect(SearchPanelShowTransition.shouldExitPreview(from: .interactive) == false)
        #expect(SearchPanelShowTransition.shouldExitPreview(from: .hidden) == false)
    }

    @Test func previousAppFallsBackToLastActivatedNotAnArbitraryOne() {
        let isSelf: (String) -> Bool = { $0 == "velox" }
        let alive: (String) -> Bool = { _ in false }
        #expect(PreviousAppPolicy.pick(frontmost: "safari", lastActivated: "notes", isSelf: isSelf, isTerminated: alive) == "safari")
        #expect(PreviousAppPolicy.pick(frontmost: "velox", lastActivated: "notes", isSelf: isSelf, isTerminated: alive) == "notes")
        #expect(PreviousAppPolicy.pick(frontmost: nil, lastActivated: "notes", isSelf: isSelf, isTerminated: alive) == "notes")
        #expect(PreviousAppPolicy.pick(frontmost: "velox", lastActivated: "velox", isSelf: isSelf, isTerminated: alive) == nil)
        #expect(PreviousAppPolicy.pick(frontmost: "velox", lastActivated: nil, isSelf: isSelf, isTerminated: alive) == nil)
        let quit: (String) -> Bool = { $0 == "notes" }
        #expect(PreviousAppPolicy.pick(frontmost: "velox", lastActivated: "notes", isSelf: isSelf, isTerminated: quit) == nil)
        #expect(PreviousAppPolicy.pick(frontmost: "notes", lastActivated: "safari", isSelf: isSelf, isTerminated: quit) == "safari")
    }

    @Test func staleShowTimerDoesNotRearmHidesOnDeactivate() {
        #expect(SearchPanelShowTransition.shouldRearmHidesOnDeactivate(scheduled: 3, current: 3, mode: .interactive))
        #expect(!SearchPanelShowTransition.shouldRearmHidesOnDeactivate(scheduled: 2, current: 3, mode: .interactive))
        #expect(!SearchPanelShowTransition.shouldRearmHidesOnDeactivate(scheduled: 3, current: 3, mode: .hidden))
        #expect(!SearchPanelShowTransition.shouldRearmHidesOnDeactivate(scheduled: 3, current: 3, mode: .preview))
    }

    @Test func panelKeysYieldToImeComposition() {
        #expect(SearchPanelKeyRouting.shouldConsumePanelKey(hasMarkedText: false))
        #expect(SearchPanelKeyRouting.shouldConsumePanelKey(hasMarkedText: true) == false)
    }

    @Test func previewModeIsDisplayOnly() {
        #expect(SearchPanelPresentation.ignoresMouseEvents(.preview) == false)
        #expect(SearchPanelPresentation.hidesOnDeactivate(.preview) == false)
        #expect(SearchPanelPresentation.shouldHideOnResign(.preview) == false)
        #expect(SearchPanelPresentation.isMovable(.preview) == false)
        #expect(SearchPanelPresentation.ignoresMouseEvents(.interactive) == false)
        #expect(SearchPanelPresentation.hidesOnDeactivate(.interactive))
        #expect(SearchPanelPresentation.shouldHideOnResign(.interactive))
        #expect(SearchPanelPresentation.isMovable(.interactive))
    }

    @Test func resignDoesNotHideWhenSettingsIsFront() {
        #expect(SearchPanelPresentation.shouldDismissOnResign(.interactive, settingsIsFront: false))
        #expect(SearchPanelPresentation.shouldDismissOnResign(.interactive, settingsIsFront: true) == false)
        #expect(SearchPanelPresentation.shouldDismissOnResign(.preview, settingsIsFront: false) == false)
        #expect(SearchPanelPresentation.shouldDismissOnResign(.preview, settingsIsFront: true) == false)
    }

    @Test func previewStaysWithSettingsInsteadOfFloating() {
        let settings = SettingsWindowPlacement.windowLevel
        #expect(SearchPanelPresentation.windowLevel(.interactive) == .floating)
        #expect(SearchPanelPresentation.windowLevel(.preview, settingsLevel: settings).rawValue == settings.rawValue + 1)
        #expect(SearchPanelPresentation.windowLevel(.preview, settingsLevel: settings) != .floating)
        #expect(SearchPanelPresentation.ordersIndependently(.preview) == false)
        #expect(SearchPanelPresentation.ordersIndependently(.interactive))
        #expect(SearchPanelPresentation.parksPreviewWhenSettingsResigns(.preview))
        #expect(SearchPanelPresentation.parksPreviewWhenSettingsResigns(.interactive) == false)
        #expect(SearchPanelPresentation.showsAlignmentGuides(.interactive))
        #expect(SearchPanelPresentation.showsAlignmentGuides(.preview) == false)
        #expect(SearchPanelPresentation.showsAlignmentGuides(.hidden) == false)
    }

    @Test func previewRowsCoverEachResultKind() {
        let kinds = Set(SearchPanelPreview.rows.map(\.kind))
        #expect(kinds == [.app, .calculation, .currency])
        #expect(SearchPanelPreview.rows.count == 3)
    }

    @Test func previewPinsAboveSettings() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let settings = NSRect(x: 410, y: 286, width: 620, height: 328)
        let panelSize = NSSize(width: 680, height: 209)
        let frame = SearchPanelPreviewPlacement.frame(
            panelSize: panelSize,
            settingsFrame: settings,
            visible: visible
        )
        #expect(abs(frame.midX - settings.midX) < 0.5)
        #expect(abs(frame.minY - (settings.maxY + SearchPanelPreviewPlacement.gap)) < 0.5)
        #expect(frame.width == 680)
    }

    @Test func previewKeepsOffsetWhenSettingsMoves() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let settings = NSRect(x: 400, y: 180, width: 620, height: 328)
        let panelSize = NSSize(width: 680, height: 209)
        let first = SearchPanelPreviewPlacement.frame(
            panelSize: panelSize,
            settingsFrame: settings,
            visible: visible
        )
        let moved = settings.offsetBy(dx: 80, dy: -36)
        let second = SearchPanelPreviewPlacement.frame(
            panelSize: panelSize,
            settingsFrame: moved,
            visible: visible
        )
        #expect(abs((second.origin.x - first.origin.x) - 80) < 0.5)
        #expect(abs((second.origin.y - first.origin.y) + 36) < 0.5)
        #expect(SearchPanelPreviewPlacement.followsSettingsAsChildWindow(.preview))
        #expect(SearchPanelPreviewPlacement.followsSettingsAsChildWindow(.interactive) == false)
    }

    @Test func stackedSettingsLeaveRoomForPreview() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelSize = NSSize(width: 680, height: SearchPanelPreviewPlacement.previewCardHeight)
        let settingsSize = Constants.SettingsWindow.size
        let stack = SearchPanelPreviewPlacement.stackedFrames(
            panelSize: panelSize,
            settingsSize: settingsSize,
            visible: visible
        )
        #expect(abs(stack.panel.midX - stack.settings.midX) < 0.5)
        #expect(stack.panel.minY >= stack.settings.maxY + SearchPanelPreviewPlacement.gap - 0.5)
        #expect(stack.panel.maxY <= visible.maxY + 0.5)
        #expect(stack.settings.minY >= visible.minY - 0.5)
    }

    @Test func windowSizeIsWideEnoughForOneThemeRow() {
        #expect(SettingsWindowPlacement.windowSize == Constants.SettingsWindow.size)
        #expect(Constants.SettingsWindow.width >= 740)
        #expect(Constants.SettingsWindow.height >= 400)
        #expect(Constants.SettingsWindow.height <= 440)
        #expect(SettingsChrome.themeColumns == ThemeCatalog.all.count)
        #expect(SettingsChrome.themeToControlsGap > SettingsChrome.cardStackSpacing)
        #expect(SettingsChrome.footerGap < SettingsChrome.pagePadding)
    }

    @Test func settingsWindowHugsMeasuredContentHeight() {
        #expect(SettingsWindowPlacement.restoresFrame == false)
        let fitted = SettingsWindowPlacement.contentSize(fittingHeight: 392)
        #expect(fitted.width == Constants.SettingsWindow.width)
        #expect(fitted.height == 392)
        #expect(SettingsWindowPlacement.contentSize(fittingHeight: 0).height == Constants.SettingsWindow.height)
        #expect(SettingsWindowPlacement.contentSize(fittingHeight: .nan).height == Constants.SettingsWindow.height)
    }

    @Test func hotkeyIsIgnoredWhileSettingsAreOpen() {
        #expect(SearchPanelHotKey.action(settingsVisible: true) == .ignore)
        #expect(SearchPanelHotKey.action(settingsVisible: false) == .togglePanel)
    }

    @Test func footerKeepsResetBesideRebuild() {
        #expect(SettingsFooter.leading == [SettingsFooter.rebuildIndex, SettingsFooter.resetPosition])
        #expect(SettingsFooter.rebuildIndex == "Rebuild App Index")
        #expect(SettingsFooter.resetPosition == "Reset Position")
    }

    @Test func searchCardStartsWithLoginToggle() {
        #expect(SettingsSearchCard.launchAtLogin == "Start at login")
        #expect(Constants.Defaults.launchAtLogin)
    }
}

@Suite("App version")
struct AppVersionTests {
    @Test func formatsMarketingAndBuild() {
        #expect(AppVersion.label(short: "1.0.0", build: "1") == "v1.0.0 (1)")
        #expect(AppVersion.label(short: "2.4.1", build: "88") == "v2.4.1 (88)")
    }

    @Test func stripsExistingVPrefix() {
        #expect(AppVersion.label(short: "v1.2.3", build: "9") == "v1.2.3 (9)")
    }
}

@Suite("Constants")
struct ConstantsTests {
    @Test func appNameAndBundleAreSet() {
        #expect(!Constants.App.name.isEmpty)
        #expect(Constants.App.bundleIdentifier == "ro.randusoft.velox")
        #expect(Constants.App.settingsWindowTitle == "Settings")
    }

    @Test func systemAppsAreOffByDefault() {
        #expect(Constants.Defaults.includeSystemApps == false)
    }

    @Test func mathAndCurrencyAreOnByDefault() {
        #expect(Constants.Defaults.mathEnabled)
        #expect(Constants.Defaults.currencyEnabled)
        #expect(Constants.Defaults.launchAtLogin)
        #expect(Constants.PreferenceKey.mathEnabled == "mathEnabled")
        #expect(Constants.PreferenceKey.currencyEnabled == "currencyEnabled")
        #expect(Constants.PreferenceKey.launchAtLogin == "launchAtLogin")
    }

    @Test func maxResultsDefaultIsSpotlightLike() {
        #expect(Constants.Defaults.maxResults == 8)
        #expect(Constants.Defaults.maxResultsRange.contains(Constants.Defaults.maxResults))
    }

    @Test func notificationNamesAreStable() {
        #expect(Constants.Notify.showExistingInstance.rawValue == "com.velox.launcher.show")
        #expect(SingleInstance.showNotification == Constants.Notify.showExistingInstance)
    }
}
