import AppKit

enum SettingsWindowPlacement {
    static let windowLevel = NSWindow.Level.normal
    static let windowSize = Constants.SettingsWindow.size
    static let restoresFrame = false

    static func contentSize(fittingHeight: CGFloat) -> NSSize {
        let height = (fittingHeight.isFinite && fittingHeight > 0)
            ? fittingHeight
            : Constants.SettingsWindow.height
        return NSSize(width: Constants.SettingsWindow.width, height: height)
    }

    static func centeredFrame(size: NSSize, visible: NSRect) -> NSRect {
        NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func targetScreen(
        mouse: NSPoint = NSEvent.mouseLocation,
        screens: [NSScreen] = NSScreen.screens,
        main: NSScreen? = NSScreen.main
    ) -> NSScreen? {
        let index = screenIndex(mouse: mouse, frames: screens.map(\.frame))
        if let index { return screens[index] }
        return main
    }

    static func screenIndex(mouse: NSPoint, frames: [NSRect]) -> Int? {
        frames.firstIndex { NSMouseInRect(mouse, $0, false) }
    }
}

enum SearchPanelPreviewPlacement {
    static let gap: CGFloat = 12

    static var previewCardHeight: CGFloat {
        Constants.Panel.searchRowHeight
            + 1
            + CGFloat(SearchPanelPreview.rows.count) * Constants.Panel.resultRowHeight
            + Constants.Panel.resultsBottomPad
    }

    static func frame(
        panelSize: NSSize,
        settingsFrame: NSRect,
        visible: NSRect
    ) -> NSRect {
        var panel = NSRect(
            x: settingsFrame.midX - panelSize.width / 2,
            y: settingsFrame.maxY + gap,
            width: panelSize.width,
            height: panelSize.height
        )
        if panel.maxY > visible.maxY {
            panel.origin.y = visible.maxY - panel.height
        }
        if panel.minX < visible.minX {
            panel.origin.x = visible.minX
        } else if panel.maxX > visible.maxX {
            panel.origin.x = visible.maxX - panel.width
        }
        return panel
    }

    static func followsSettingsAsChildWindow(_ mode: SearchPanelMode) -> Bool {
        mode == .preview
    }

    static func stackedFrames(
        panelSize: NSSize,
        settingsSize: NSSize,
        visible: NSRect
    ) -> (panel: NSRect, settings: NSRect) {
        let stackHeight = panelSize.height + gap + settingsSize.height
        var stackMinY = visible.midY - stackHeight / 2
        if stackMinY < visible.minY {
            stackMinY = visible.minY
        }
        if stackMinY + stackHeight > visible.maxY {
            stackMinY = visible.maxY - stackHeight
        }
        let settings = NSRect(
            x: visible.midX - settingsSize.width / 2,
            y: stackMinY,
            width: settingsSize.width,
            height: settingsSize.height
        )
        let panel = frame(panelSize: panelSize, settingsFrame: settings, visible: visible)
        return (panel, settings)
    }
}
