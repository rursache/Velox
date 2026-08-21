import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    static let shared = PreferencesWindowController()
    private var window: NSWindow?
    private var hosting: NSHostingController<SettingsRootView>?
    private var restoredAccessoryOnClose = false

    var isVisible: Bool { window?.isVisible == true }
    var hostWindow: NSWindow? { window }
    var windowFrame: NSRect? { window?.frame }
    var windowScreen: NSScreen? { window?.screen }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsRootView())
            hosting.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: hosting)
            window.title = Constants.App.settingsWindowTitle
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.isRestorable = SettingsWindowPlacement.restoresFrame
            window.delegate = self
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
            window.hidesOnDeactivate = false
            window.level = SettingsWindowPlacement.windowLevel
            window.isMovableByWindowBackground = true
            self.hosting = hosting
            self.window = window
        }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            restoredAccessoryOnClose = true
        }
        applyPlacement(recenter: true)
        // Preview first so the interactive bar does not hide and restore the previous app
        NotificationCenter.default.post(name: Constants.Notify.showPanelPreview, object: window)
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.performClose(nil)
    }

    private func applyPlacement(recenter: Bool) {
        guard let window else { return }
        window.setContentSize(fittedContentSize())
        if recenter, let screen = SettingsWindowPlacement.targetScreen() {
            let stack = SearchPanelPreviewPlacement.stackedFrames(
                panelSize: NSSize(width: Constants.Panel.width, height: SearchPanelPreviewPlacement.previewCardHeight),
                settingsSize: window.frame.size,
                visible: screen.visibleFrame
            )
            window.setFrameOrigin(stack.settings.origin)
        }
        window.level = SettingsWindowPlacement.windowLevel
    }

    private func fittedContentSize() -> NSSize {
        let width = SettingsWindowPlacement.windowSize.width
        let proposal = NSSize(width: width, height: .greatestFiniteMagnitude)
        let fitted = hosting?.sizeThatFits(in: proposal) ?? NSSize(SettingsWindowPlacement.windowSize)
        return SettingsWindowPlacement.contentSize(fittingHeight: fitted.height)
    }

    func windowDidResignKey(_ notification: Notification) {
        NotificationCenter.default.post(name: Constants.Notify.hidePanelPreview, object: nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard isVisible else { return }
        NotificationCenter.default.post(name: Constants.Notify.showPanelPreview, object: window)
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .veloxCancelHotKeyCapture, object: nil)
        NotificationCenter.default.post(name: .veloxResumeOpenHotKey, object: nil)
        NotificationCenter.default.post(name: .veloxHidePanel, object: SearchPanelHideReason.settings)
        guard restoredAccessoryOnClose else { return }
        restoredAccessoryOnClose = false
        NSApp.setActivationPolicy(.accessory)
    }

}

private extension NSSize {
    init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }
}
