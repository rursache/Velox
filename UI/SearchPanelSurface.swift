import AppKit
import SwiftUI

@MainActor
final class SearchPanelSurface {
    let panel: KeyablePanel
    let container: VisualEffectContainer
    private let hosting: NSHostingView<SearchView>
    private let engine: SearchEngine

    init(
        engine: SearchEngine,
        theme: Theme,
        highlight: SelectionStyle = HighlightCatalog.style(for: .accent),
        cornerRadius: CGFloat,
        acceptsFocus: Bool,
        allowsKey: Bool = true
    ) {
        self.engine = engine
        let initial = NSRect(
            x: 0,
            y: 0,
            width: SearchPanelController.panelWidth,
            height: SearchPanelController.searchRowHeight
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
        panel.allowsKey = allowsKey
        panel.isMovableByWindowBackground = allowsKey && acceptsFocus

        let container = VisualEffectContainer(frame: initial)
        let hosting = NSHostingView(rootView: SearchView(engine: engine, theme: theme, highlight: highlight, acceptsFocus: acceptsFocus))
        hosting.safeAreaRegions = []
        hosting.layer?.isOpaque = false
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container

        self.panel = panel
        self.container = container
        self.hosting = hosting
        applyChrome(theme: theme, highlight: highlight, cornerRadius: cornerRadius, acceptsFocus: acceptsFocus)
    }

    func applyChrome(theme: Theme, highlight: SelectionStyle, cornerRadius: CGFloat, acceptsFocus: Bool) {
        container.apply(theme: theme, cornerRadius: cornerRadius)
        hosting.appearance = theme.legibility.nsAppearance
        hosting.rootView = SearchView(engine: engine, theme: theme, highlight: highlight, acceptsFocus: acceptsFocus)
    }

    func applyFrame(_ frame: NSRect) {
        let bounds = NSRect(origin: .zero, size: frame.size)
        panel.setFrame(frame, display: true, animate: false)
        container.frame = bounds
        hosting.frame = bounds
        panel.contentView?.frame = bounds
    }

    func placeFactory(height: CGFloat, on screen: NSScreen) {
        let size = NSSize(width: SearchPanelController.panelWidth, height: height)
        applyFrame(PanelAlignment.factoryFrame(size: size, visible: screen.visibleFrame))
        container.setCollapsed(height <= SearchPanelController.searchRowHeight)
    }

    func growDown(to height: CGFloat, visible: NSRect? = nil) {
        var frame = panel.frame
        let maxY = frame.maxY
        frame.size.width = SearchPanelController.panelWidth
        frame.size.height = height
        frame.origin.y = maxY - height
        if let visible {
            frame = SearchPanelController.clampReplica(frame, to: visible)
        }
        applyFrame(frame)
        container.setCollapsed(height <= SearchPanelController.searchRowHeight)
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }

    func orderFront() {
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func orderOut() {
        panel.orderOut(nil)
    }
}
