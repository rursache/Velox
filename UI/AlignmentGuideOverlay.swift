import AppKit

@MainActor
final class AlignmentGuideOverlay {
    private var window: NSPanel?
    private let canvas = AlignmentGuideView()

    func show(_ guides: [PanelAlignment.Guide], on screen: NSScreen) {
        if guides.isEmpty {
            hide()
            return
        }
        let panel = ensureWindow()
        panel.setFrame(screen.frame, display: true)
        canvas.frame = panel.contentView?.bounds ?? panel.frame
        canvas.guides = guides.map { guide in
            switch guide.axis {
            case .vertical:
                return AlignmentGuideView.Line(axis: .vertical, position: guide.position - screen.frame.minX)
            case .horizontal:
                return AlignmentGuideView.Line(axis: .horizontal, position: guide.position - screen.frame.minY)
            }
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
        canvas.guides = []
    }

    private func ensureWindow() -> NSPanel {
        if let window { return window }
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        canvas.autoresizingMask = [.width, .height]
        panel.contentView = canvas
        window = panel
        return panel
    }
}

final class AlignmentGuideView: NSView {
    struct Line {
        enum Axis { case vertical, horizontal }
        var axis: Axis
        var position: CGFloat
    }

    var guides: [Line] = [] {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard !guides.isEmpty else { return }
        let color = NSColor(white: 0.72, alpha: 0.7)
        color.setStroke()
        for guide in guides {
            let path = NSBezierPath()
            path.lineWidth = 1
            switch guide.axis {
            case .vertical:
                path.move(to: NSPoint(x: guide.position, y: bounds.minY))
                path.line(to: NSPoint(x: guide.position, y: bounds.maxY))
            case .horizontal:
                path.move(to: NSPoint(x: bounds.minX, y: guide.position))
                path.line(to: NSPoint(x: bounds.maxX, y: guide.position))
            }
            path.stroke()
        }
    }
}
