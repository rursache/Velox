import AppKit
import SwiftUI
import Combine

enum SearchPanelHideReason {
    case dismissed
    case launchedApp
    case settings

    static func shouldRestorePreviousApp(_ reason: SearchPanelHideReason) -> Bool {
        reason == .dismissed
    }
}

enum SearchPanelMode: Equatable {
    case hidden
    case interactive
    case preview
}

enum SearchPanelHotKeyAction: Equatable {
    case togglePanel
    case ignore
}

enum SearchPanelHotKey {
    static func action(settingsVisible: Bool) -> SearchPanelHotKeyAction {
        settingsVisible ? .ignore : .togglePanel
    }
}

enum SearchPanelKeyRouting {
    static func shouldConsumePanelKey(hasMarkedText: Bool) -> Bool {
        !hasMarkedText
    }
}

enum SearchPanelShowTransition {
    static func shouldExitPreview(from mode: SearchPanelMode) -> Bool {
        mode == .preview
    }

    static func shouldRunResultAction(acceptsFocus: Bool) -> Bool {
        acceptsFocus
    }
}

enum SearchPanelPresentation {
    static func ignoresMouseEvents(_ mode: SearchPanelMode) -> Bool {
        false
    }

    static func hidesOnDeactivate(_ mode: SearchPanelMode) -> Bool {
        mode == .interactive
    }

    static func shouldHideOnResign(_ mode: SearchPanelMode) -> Bool {
        mode == .interactive
    }

    static func shouldDismissOnResign(_ mode: SearchPanelMode, settingsIsFront: Bool) -> Bool {
        shouldHideOnResign(mode) && !settingsIsFront
    }

    static func isMovable(_ mode: SearchPanelMode) -> Bool {
        mode == .interactive
    }

    static func ordersIndependently(_ mode: SearchPanelMode) -> Bool {
        mode != .preview
    }

    static func parksPreviewWhenSettingsResigns(_ mode: SearchPanelMode) -> Bool {
        mode == .preview
    }

    static func showsAlignmentGuides(_ mode: SearchPanelMode) -> Bool {
        mode == .interactive
    }

    static func windowLevel(
        _ mode: SearchPanelMode,
        settingsLevel: NSWindow.Level = SettingsWindowPlacement.windowLevel
    ) -> NSWindow.Level {
        switch mode {
        case .preview:
            return NSWindow.Level(rawValue: settingsLevel.rawValue + 1)
        case .interactive, .hidden:
            return .floating
        }
    }
}

enum SearchPanelPreview {
    static let rows: [SearchResult] = [
        SearchResult(
            id: "preview-app",
            kind: .app,
            title: "Safari",
            subtitle: "Application",
            score: 1,
            action: {}
        ),
        SearchResult(
            id: "preview-math",
            kind: .calculation,
            title: "42",
            subtitle: "Calculation · ⏎ to copy",
            score: 1,
            copyValue: "42",
            action: {}
        ),
        SearchResult(
            id: "preview-fx",
            kind: .currency,
            title: "€92.40",
            subtitle: "100 USD → EUR",
            score: 1,
            copyValue: "92.40",
            action: {}
        )
    ]
}

@MainActor
final class SearchPanelController: NSObject, NSWindowDelegate {
    static let panelWidth = Constants.Panel.width
    static let searchRowHeight = Constants.Panel.searchRowHeight
    static let resultRowHeight = Constants.Panel.resultRowHeight
    static let resultsBottomPad = Constants.Panel.resultsBottomPad

    private let panel: KeyablePanel
    private let engine: SearchEngine
    private var localMonitor: Any?
    private var resignMonitor: Any?
    private var globalClickMonitor: Any?
    private var dragEndMonitor: Any?
    private let alignmentOverlay = AlignmentGuideOverlay()
    private var hasMovedSinceMouseDown = false
    private let hosting: NSHostingView<SearchView>
    private let container: VisualEffectContainer
    /// Ignore resign-key briefly after show so activation races don't auto-hide
    private var ignoreResignUntil: Date = .distantPast
    /// App that was frontmost before Velox stole focus — restored on hide
    private var previousApp: NSRunningApplication?
    /// Skip persisting origin while we setFrame programmatically
    private var isProgrammaticFrameChange = false
    private var cancellables = Set<AnyCancellable>()
    private var mode: SearchPanelMode = .hidden
    private var replicas: [SearchPanelSurface] = []
    private var restoreGeneration: UInt64 = 0

    init(appIndex: AppIndex, currencyService: CurrencyService) {
        let engine = SearchEngine(appIndex: appIndex, currencyService: currencyService)
        self.engine = engine

        let root = SearchView(engine: engine, theme: Preferences.shared.theme, highlight: Preferences.shared.highlight)
        let hosting = NSHostingView(rootView: root)
        hosting.safeAreaRegions = []
        hosting.layer?.isOpaque = false
        self.hosting = hosting

        // Borderless avoids titlebar safe-area / extra chrome that breaks collapsed layout
        let initial = NSRect(
            x: 0,
            y: 0,
            width: Self.panelWidth,
            height: Self.searchRowHeight
        )
        let panel = KeyablePanel(
            contentRect: initial,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .none
        panel.isMovableByWindowBackground = true

        let container = VisualEffectContainer(frame: initial)
        self.container = container
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container

        self.panel = panel
        super.init()

        panel.delegate = self

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResultsChanged),
            name: .veloxResultsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHide),
            name: .veloxHidePanel,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSetQuery(_:)),
            name: .veloxSetQuery,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExecute),
            name: .veloxExecuteSelected,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChromeChange),
            name: Constants.Notify.themeDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePositionReset),
            name: Constants.Notify.panelPositionDidReset,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowPreview),
            name: Constants.Notify.showPanelPreview,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHidePreview),
            name: Constants.Notify.hidePanelPreview,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        observeChrome()
        applyChrome()
    }

    // MARK: - Window delegate

    func windowDidResignKey(_ notification: Notification) {
        hideIfNotIgnoringResign()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticFrameChange else { return }
        guard notification.object as? NSWindow === panel else { return }
        guard SearchPanelPresentation.showsAlignmentGuides(mode) else {
            alignmentOverlay.hide()
            return
        }
        hasMovedSinceMouseDown = true
        updateAlignmentGuides()
    }

    private func persistPanelPositionIfUserMoved() {
        guard !isProgrammaticFrameChange, panel.isVisible else { return }
        let frame = panel.frame
        Preferences.shared.customPanelPosition = (x: frame.origin.x, maxY: frame.maxY)
    }

    @objc private func handleAppResignActive() {
        hideIfNotIgnoringResign()
    }

    private func hideIfNotIgnoringResign() {
        guard panel.isVisible || replicas.contains(where: { $0.panel.isVisible }) else { return }
        guard Date() >= ignoreResignUntil else { return }
        let settingsIsFront = isOwnedWindow(NSApp.keyWindow)
            || PreferencesWindowController.shared.isVisible
        guard SearchPanelPresentation.shouldDismissOnResign(mode, settingsIsFront: settingsIsFront) else {
            return
        }
        hide()
    }

    private func isOwnedWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        if window === panel { return true }
        if window === PreferencesWindowController.shared.hostWindow { return true }
        return replicas.contains { $0.panel === window }
    }

    @objc private func handleExecute() {
        Task { @MainActor in
            let kind = await self.engine.executeSelected()
            self.hide(restorePrevious: kind != .app)
        }
    }

    @objc private func handleSetQuery(_ note: Notification) {
        if let q = note.object as? String {
            Task { @MainActor in
                self.engine.updateQuery(q)
                NotificationCenter.default.post(name: .veloxFocusSearch, object: nil)
            }
        }
    }

    @objc private func handleResultsChanged() {
        relayout()
    }

    @objc private func handleHide(_ note: Notification) {
        if let reason = note.object as? SearchPanelHideReason {
            hide(restorePrevious: SearchPanelHideReason.shouldRestorePreviousApp(reason))
            return
        }
        let kind = note.object as? SearchResultKind
        hide(restorePrevious: kind != .app)
    }

    func toggle() {
        switch SearchPanelHotKey.action(settingsVisible: PreferencesWindowController.shared.isVisible) {
        case .ignore:
            return
        case .togglePanel:
            if panel.isVisible {
                hide()
            } else {
                show()
            }
        }
    }

    func show() {
        if PreferencesWindowController.shared.isVisible {
            showPreview()
            return
        }
        restoreGeneration &+= 1
        if mode != .interactive {
            rememberPreviousApp()
        }
        if SearchPanelShowTransition.shouldExitPreview(from: mode) {
            exitPreviewState()
        }
        mode = .interactive
        applyPresentation()
        applyChrome()
        panel.hidesOnDeactivate = false
        ignoreResignUntil = Date().addingTimeInterval(0.25)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
            guard let self, self.mode == .interactive else { return }
            self.panel.hidesOnDeactivate = true
        }
        relayout(preferDefaultPosition: Preferences.shared.customPanelPosition == nil)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
        installFocusLossMonitors()
        syncReplicas()
        NotificationCenter.default.post(name: .veloxFocusSearch, object: nil)
        Task {
            if Preferences.shared.currencyEnabled {
                await CurrencyService.shared.refreshIfNeeded(trigger: .panelShow)
            }
        }
    }

    func showPreview() {
        let alreadyPreview = mode == .preview
        if !alreadyPreview {
            removeKeyMonitor()
            removeFocusLossMonitors()
            alignmentOverlay.hide()
            mode = .preview
            applyPresentation()
            applyChrome()
            engine.showChromePreview()
            relayout(preferDefaultPosition: false)
            panel.alphaValue = 1
        }
        hideReplicas()
        attachPreviewToSettings()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func parkPreview() {
        guard SearchPanelPresentation.parksPreviewWhenSettingsResigns(mode) else { return }
        panel.orderOut(nil)
    }

    func hide(restorePrevious: Bool = true) {
        restoreGeneration &+= 1
        alignmentOverlay.hide()
        hideReplicas()
        exitPreviewState()
        mode = .hidden
        applyPresentation()
        panel.orderOut(nil)
        removeKeyMonitor()
        removeFocusLossMonitors()
        if restorePrevious {
            restorePreviousApp()
        } else {
            previousApp = nil
        }
    }

    private func exitPreviewState() {
        detachPreviewFromSettings()
        engine.endChromePreview()
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = true
        panel.isMovableByWindowBackground = true
        panel.allowsKey = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    private func attachPreviewToSettings() {
        guard let settings = PreferencesWindowController.shared.hostWindow else { return }
        if panel.parent !== settings {
            settings.addChildWindow(panel, ordered: .above)
        }
        panel.level = SearchPanelPresentation.windowLevel(.preview, settingsLevel: settings.level)
    }

    private func detachPreviewFromSettings() {
        if let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
        panel.level = SearchPanelPresentation.windowLevel(.interactive)
    }

    private func applyPresentation() {
        applyPresentation(to: panel)
        for replica in replicas {
            applyPresentation(to: replica.panel)
        }
    }

    private func applyPresentation(to panel: KeyablePanel) {
        panel.ignoresMouseEvents = SearchPanelPresentation.ignoresMouseEvents(mode)
        panel.hidesOnDeactivate = SearchPanelPresentation.hidesOnDeactivate(mode)
        panel.isMovableByWindowBackground = SearchPanelPresentation.isMovable(mode)
        panel.allowsKey = mode != .preview
        panel.level = SearchPanelPresentation.windowLevel(mode)
        if mode == .preview {
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        } else {
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        }
    }

    private func rememberPreviousApp() {
        let front = NSWorkspace.shared.frontmostApplication
        // Don't store ourselves
        if let front, front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
            return
        }
        // Fall back to the most recently active non-Velox app
        previousApp = NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                && !$0.isTerminated
        }
    }

    private func restorePreviousApp() {
        guard let app = previousApp, !app.isTerminated else {
            previousApp = nil
            return
        }
        let generation = restoreGeneration
        previousApp = nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if PreferencesWindowController.shared.isVisible { return }
            guard generation == self.restoreGeneration, self.mode == .hidden else { return }
            app.activate()
        }
    }

    private func desiredHeight() -> CGFloat {
        let rowCount = engine.results.count
        if rowCount == 0 {
            return Self.searchRowHeight
        }
        return Self.searchRowHeight
            + 1 // divider
            + CGFloat(rowCount) * Self.resultRowHeight
            + Self.resultsBottomPad
    }

    /// Horizontal center; pin the TOP of the panel so height changes grow downward only
    private static func defaultOrigin(for size: NSSize, on screen: NSScreen) -> NSPoint {
        PanelAlignment.factoryFrame(size: size, visible: screen.visibleFrame).origin
    }

    private func targetScreen(preferCurrent: Bool) -> NSScreen? {
        let screens = NSScreen.screens
        if preferCurrent, let saved = Preferences.shared.customPanelPosition {
            let probe = NSRect(x: saved.x, y: saved.maxY - 56, width: Self.panelWidth, height: 56)
            if let index = PanelPlacement.screenIndex(containing: probe, frames: screens.map(\.frame)),
               screens.indices.contains(index) {
                return screens[index]
            }
        }
        if preferCurrent, let current = panel.screen {
            return current
        }
        let frames = screens.map(\.frame)
        let mainIndex = NSScreen.main.flatMap { main in
            screens.firstIndex { $0 === main }
        }
        let index = PanelPlacement.screenIndex(
            mouse: NSEvent.mouseLocation,
            frames: frames,
            mainIndex: mainIndex,
            policy: Preferences.shared.panelScreenPolicy
        )
        if let index, screens.indices.contains(index) {
            return screens[index]
        }
        return NSScreen.main
    }

    private func applyPreviewPosition(to frame: inout NSRect) {
        guard let settingsFrame = PreferencesWindowController.shared.windowFrame else {
            applyPosition(to: &frame, preferDefault: true)
            return
        }
        let visible = PreferencesWindowController.shared.windowScreen?.visibleFrame
            ?? targetScreen(preferCurrent: false)?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        if let visible {
            frame = SearchPanelPreviewPlacement.frame(
                panelSize: frame.size,
                settingsFrame: settingsFrame,
                visible: visible
            )
        }
    }

    /// Place frame using saved top-left anchor, or default center if none / off-screen
    private func applyPosition(to frame: inout NSRect, preferDefault: Bool) {
        let screen = targetScreen(preferCurrent: !preferDefault)

        if !preferDefault, let saved = Preferences.shared.customPanelPosition {
            frame.origin.x = saved.x
            frame.origin.y = saved.maxY - frame.size.height
            let screens = NSScreen.screens
            if let index = PanelPlacement.screenIndex(containing: frame, frames: screens.map(\.frame)),
               screens.indices.contains(index) {
                frame = Self.clamp(frame, to: screens[index].visibleFrame)
            } else if let screen {
                frame.origin = Self.defaultOrigin(for: frame.size, on: screen)
            } else if let main = NSScreen.main {
                frame = Self.clamp(frame, to: main.visibleFrame)
            }
            return
        }

        if let screen {
            frame.origin = Self.defaultOrigin(for: frame.size, on: screen)
        }
    }

    static func clampReplica(_ frame: NSRect, to visible: NSRect) -> NSRect {
        clamp(frame, to: visible)
    }

    /// Keep the panel mostly on-screen after drag / multi-display changes
    private static func clamp(_ frame: NSRect, to visible: NSRect) -> NSRect {
        var f = frame
        // Keep at least 48pt of the bar visible horizontally and vertically
        let minVisible: CGFloat = 48
        if f.maxX < visible.minX + minVisible {
            f.origin.x = visible.minX + minVisible - f.width
        }
        if f.minX > visible.maxX - minVisible {
            f.origin.x = visible.maxX - minVisible
        }
        if f.maxY < visible.minY + minVisible {
            f.origin.y = visible.minY + minVisible - f.height
        }
        if f.minY > visible.maxY - minVisible {
            f.origin.y = visible.maxY - minVisible
        }
        // Prefer fully inside if panel fits
        if f.width <= visible.width {
            f.origin.x = min(max(f.origin.x, visible.minX), visible.maxX - f.width)
        }
        if f.height <= visible.height {
            f.origin.y = min(max(f.origin.y, visible.minY), visible.maxY - f.height)
        }
        return f
    }

    private static func isMostlyVisible(_ frame: NSRect, on screen: NSScreen) -> Bool {
        let intersection = frame.intersection(screen.visibleFrame)
        guard !intersection.isNull else { return false }
        return intersection.width >= 48 && intersection.height >= 24
    }

    private func relayout(preferDefaultPosition: Bool = false) {
        let height = desiredHeight()
        let collapsed = engine.results.isEmpty
        container.setCollapsed(collapsed)

        var frame = panel.frame
        let oldMaxY = frame.maxY
        let oldX = frame.origin.x
        frame.size.width = Self.panelWidth
        frame.size.height = height

        if mode == .preview {
            applyPreviewPosition(to: &frame)
        } else if preferDefaultPosition {
            applyPosition(to: &frame, preferDefault: true)
        } else if let saved = Preferences.shared.customPanelPosition {
            // Keep user placement; grow/shrink from the top edge
            frame.origin.x = panel.isVisible ? oldX : saved.x
            frame.origin.y = (panel.isVisible ? oldMaxY : saved.maxY) - height
            if let screen = targetScreen(preferCurrent: true) {
                frame = Self.clamp(frame, to: screen.visibleFrame)
            }
        } else if !panel.isVisible {
            applyPosition(to: &frame, preferDefault: true)
        } else {
            // Keep top edge fixed — never re-center on expand/collapse (that yanked the bar)
            frame.origin.x = oldX
            frame.origin.y = oldMaxY - height
            if let screen = targetScreen(preferCurrent: true) {
                frame = Self.clamp(frame, to: screen.visibleFrame)
                // Restore top edge after clamp if only the bottom was at risk
                if frame.maxY != oldMaxY, frame.height <= screen.visibleFrame.height {
                    frame.origin.y = min(oldMaxY, screen.visibleFrame.maxY) - frame.height
                    frame = Self.clamp(frame, to: screen.visibleFrame)
                }
            }
        }

        let bounds = NSRect(origin: .zero, size: frame.size)

        isProgrammaticFrameChange = true
        panel.setFrame(frame, display: true, animate: false)
        container.frame = bounds
        hosting.frame = bounds
        panel.contentView?.frame = bounds
        isProgrammaticFrameChange = false
        relayoutReplicas()
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // Text editing: handle explicitly so nonactivating panel + no-menu cases still work
            if Self.isTextEditingShortcut(event) {
                if Self.handleTextEditingShortcut(event) {
                    return nil
                }
                // Let main-menu key equivalents run if we couldn't handle it
                return event
            }

            let editorHasMark = (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
            if !SearchPanelKeyRouting.shouldConsumePanelKey(hasMarkedText: editorHasMark) {
                return event
            }

            // Don't steal plain typing / system shortcuts from the field
            switch event.keyCode {
            case 53: // escape
                self.hide()
                return nil
            case 125: // down
                self.engine.moveSelection(by: 1)
                return nil
            case 126: // up
                self.engine.moveSelection(by: -1)
                return nil
            case 36, 76: // return
                Task { @MainActor in
                    let kind = await self.engine.executeSelected()
                    self.hide(restorePrevious: kind != .app)
                }
                return nil
            default:
                return event
            }
        }
    }

    private static func isTextEditingShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.option),
              !flags.contains(.control) else { return false }
        // Prefer keyCode — charactersIgnoringModifiers can be empty under some IME states
        switch event.keyCode {
        case 0, 7, 8, 9, 6: // a, x, c, v, z
            return true
        default:
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            return ["a", "c", "v", "x", "z"].contains(key)
        }
    }

    /// Returns true if the event was handled as a text-editing command
    private static func handleTextEditingShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasShift = flags.contains(.shift)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let code = event.keyCode

        // keyCodes: a=0, x=7, c=8, v=9, z=6
        if code == 0 || key == "a" {
            return selectAllInFieldEditor()
        }
        if code == 8 || key == "c" {
            return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        }
        if code == 9 || key == "v" {
            return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        }
        if code == 7 || key == "x" {
            return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
        }
        if code == 6 || key == "z" {
            if hasShift {
                return NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
            }
            return NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
        }
        return false
    }

    @discardableResult
    private static func selectAllInFieldEditor() -> Bool {
        // Prefer active field editor
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            textView.selectAll(nil)
            return true
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            if let field = findTextField(in: window.contentView),
               window.makeFirstResponder(field) {
                if let editor = field.currentEditor() ?? window.fieldEditor(true, for: field) {
                    editor.selectAll(nil)
                    return true
                }
                field.selectText(nil)
                return true
            }
            if let editor = window.fieldEditor(false, for: nil) {
                editor.selectAll(nil)
                return true
            }
        }
        if NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil) {
            return true
        }
        NotificationCenter.default.post(name: .veloxSelectAllSearchText, object: nil)
        return true
    }

    private static func findTextField(in root: NSView?) -> NSTextField? {
        guard let root else { return nil }
        if let field = root as? NSTextField { return field }
        for sub in root.subviews {
            if let found = findTextField(in: sub) { return found }
        }
        return nil
    }

    private func removeKeyMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func installFocusLossMonitors() {
        removeFocusLossMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hideIfNotIgnoringResign()
            }
        }
        resignMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window === self.panel, event.type == .leftMouseDown {
                self.hasMovedSinceMouseDown = false
            }
            if !self.isOwnedWindow(event.window) {
                self.hideIfNotIgnoringResign()
            }
            return event
        }
        dragEndMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.snapToGuidesIfNeeded()
            return event
        }
    }

    private func updateAlignmentGuides() {
        guard SearchPanelPresentation.showsAlignmentGuides(mode),
              panel.isVisible,
              let screen = targetScreen(preferCurrent: true) else {
            alignmentOverlay.hide()
            return
        }
        let guides = PanelAlignment.guides(for: panel.frame, visible: screen.visibleFrame)
        alignmentOverlay.show(guides, on: screen)
    }

    private func snapToGuidesIfNeeded() {
        guard SearchPanelPresentation.showsAlignmentGuides(mode),
              hasMovedSinceMouseDown,
              panel.isVisible,
              let screen = targetScreen(preferCurrent: true) else {
            alignmentOverlay.hide()
            return
        }
        hasMovedSinceMouseDown = false
        let result = PanelAlignment.snap(panel.frame, visible: screen.visibleFrame)
        if result.frame != panel.frame {
            isProgrammaticFrameChange = true
            panel.setFrame(result.frame, display: true)
            isProgrammaticFrameChange = false
        }
        persistPanelPositionIfUserMoved()
        alignmentOverlay.hide()
    }

    @objc private func handleShowPreview() {
        MainActor.assumeIsolated { showPreview() }
    }

    @objc private func handleHidePreview() {
        MainActor.assumeIsolated { parkPreview() }
    }

    @objc private func handleChromeChange() {
        MainActor.assumeIsolated { applyChrome() }
    }

    @objc private func handlePositionReset() {
        MainActor.assumeIsolated {
            guard panel.isVisible, mode != .preview else { return }
            relayout(preferDefaultPosition: true)
        }
    }

    @objc private func handleScreensChanged() {
        MainActor.assumeIsolated {
            guard panel.isVisible else { return }
            if mode == .preview {
                relayout(preferDefaultPosition: false)
                return
            }
            guard mode == .interactive else { return }
            relayout(preferDefaultPosition: Preferences.shared.customPanelPosition == nil)
            syncReplicas()
        }
    }

    private func observeChrome() {
        let prefs = Preferences.shared
        prefs.$themeID
            .combineLatest(prefs.$highlightID, prefs.$panelCornerRadius)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.applyChrome()
            }
            .store(in: &cancellables)
        prefs.$panelScreenPolicy
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncReplicas()
            }
            .store(in: &cancellables)
    }

    private func applyChrome() {
        let prefs = Preferences.shared
        container.apply(theme: prefs.theme, cornerRadius: prefs.panelCornerRadius)
        hosting.appearance = prefs.theme.legibility.nsAppearance
        hosting.rootView = SearchView(
            engine: engine,
            theme: prefs.theme,
            highlight: prefs.highlight,
            acceptsFocus: mode == .interactive
        )
        for replica in replicas {
            replica.applyChrome(
                theme: prefs.theme,
                highlight: prefs.highlight,
                cornerRadius: prefs.panelCornerRadius,
                acceptsFocus: false
            )
        }
    }

    private func syncReplicas() {
        let shouldShow = mode == .interactive
            && panel.isVisible
            && Preferences.shared.panelScreenPolicy.showsOnEveryScreen
        guard shouldShow else {
            hideReplicas()
            return
        }

        let screens = NSScreen.screens
        let frames = screens.map(\.frame)
        let mainIndex = NSScreen.main.flatMap { main in
            screens.firstIndex { $0 === main }
        }
        let primary = PanelPlacement.screenIndex(
            mouse: NSEvent.mouseLocation,
            frames: frames,
            mainIndex: mainIndex,
            policy: .allScreens
        )
        let keyPrimary = PanelPlacement.screenIndex(containing: panel.frame, frames: frames) ?? primary
        let extras = PanelPlacement.replicaScreenIndexes(
            primary: keyPrimary,
            count: screens.count,
            policy: .allScreens
        ).compactMap { screens.indices.contains($0) ? screens[$0] : nil }

        rebuildReplicas(on: extras)
    }

    private func rebuildReplicas(on screens: [NSScreen]) {
        hideReplicas()
        let prefs = Preferences.shared
        let height = desiredHeight()
        replicas = screens.map { screen in
            let replica = SearchPanelSurface(
                engine: engine,
                theme: prefs.theme,
                highlight: prefs.highlight,
                cornerRadius: prefs.panelCornerRadius,
                acceptsFocus: false,
                allowsKey: false
            )
            replica.panel.delegate = self
            applyPresentation(to: replica.panel)
            replica.panel.allowsKey = false
            replica.panel.isMovableByWindowBackground = false
            replica.placeFactory(height: height, on: screen)
            replica.orderFront()
            return replica
        }
    }

    private func relayoutReplicas() {
        guard mode == .interactive, Preferences.shared.panelScreenPolicy.showsOnEveryScreen else {
            hideReplicas()
            return
        }
        let height = desiredHeight()
        if replicas.isEmpty {
            syncReplicas()
            return
        }
        for replica in replicas {
            if replica.panel.isVisible {
                replica.growDown(to: height, visible: replica.panel.screen?.visibleFrame)
            }
        }
    }

    private func hideReplicas() {
        for replica in replicas {
            replica.panel.delegate = nil
            replica.close()
        }
        replicas.removeAll()
    }

    private func removeFocusLossMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let resignMonitor {
            NSEvent.removeMonitor(resignMonitor)
            self.resignMonitor = nil
        }
        if let dragEndMonitor {
            NSEvent.removeMonitor(dragEndMonitor)
            self.dragEndMonitor = nil
        }
    }
}

final class KeyablePanel: NSPanel {
    var allowsKey = true
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { allowsKey }

    override var contentView: NSView? {
        get { super.contentView }
        set {
            super.contentView = newValue
            // Keep clear so rounded blur is the only chrome
            newValue?.wantsLayer = true
        }
    }
}

final class VisualEffectContainer: NSView {
    private let effect = NSVisualEffectView()
    private let washView = NSView()
    private var hairline = ThemeCatalog.glass.hairline
    private var wash = ThemeCatalog.glass.wash
    private var cornerRadius = PanelMetrics.standard.cornerRadius

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        effect.frame = bounds
        effect.autoresizingMask = [.width, .height]
        effect.material = ThemeCatalog.glass.material
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.masksToBounds = true
        addSubview(effect, positioned: .below, relativeTo: nil)

        washView.frame = bounds
        washView.autoresizingMask = [.width, .height]
        washView.wantsLayer = true
        washView.layer?.masksToBounds = true
        addSubview(washView, positioned: .above, relativeTo: effect)
        apply(theme: ThemeCatalog.glass, cornerRadius: PanelMetrics.standard.cornerRadius)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        effect.frame = bounds
        washView.frame = bounds
        applyCornerRadius()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyHairline()
        applyWash()
    }

    func setCollapsed(_: Bool) {
        applyCornerRadius()
    }

    var appliedMaterial: NSVisualEffectView.Material { effect.material }
    var appliedCornerRadius: CGFloat { cornerRadius }
    var appliedWash: ThemeWash { wash }

    func apply(theme: Theme, cornerRadius: CGFloat) {
        self.hairline = theme.hairline
        self.wash = theme.wash
        self.cornerRadius = cornerRadius
        appearance = theme.legibility.nsAppearance
        effect.appearance = theme.legibility.nsAppearance
        if effect.material != theme.material {
            effect.material = theme.material
            effect.state = .inactive
            effect.state = .active
        }
        applyCornerRadius()
        applyHairline()
        applyWash()
        needsDisplay = true
        layer?.setNeedsDisplay()
    }

    private func applyCornerRadius() {
        layer?.cornerRadius = cornerRadius
        effect.layer?.cornerRadius = cornerRadius
        washView.layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        effect.layer?.cornerCurve = .continuous
        washView.layer?.cornerCurve = .continuous
    }

    private func applyHairline() {
        layer?.borderWidth = hairline.width
        layer?.borderColor = hairline.cgColor(in: effectiveAppearance)
    }

    private func applyWash() {
        washView.layer?.backgroundColor = wash.cgColor(in: effectiveAppearance)
    }
}

extension Notification.Name {
    static let veloxFocusSearch = Constants.Notify.focusSearch
    static let veloxResultsDidChange = Constants.Notify.resultsDidChange
    static let veloxSetQuery = Constants.Notify.setQuery
    static let veloxExecuteSelected = Constants.Notify.executeSelected
    static let veloxIndexReady = Constants.Notify.indexReady
    static let veloxSelectAllSearchText = Constants.Notify.selectAllSearchText
    static let veloxRatesDidChange = Constants.Notify.ratesDidChange
}
