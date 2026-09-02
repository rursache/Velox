import Testing
import AppKit
@testable import Velox

@Suite("Panel alignment")
struct PanelAlignmentTests {
    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = NSSize(width: 680, height: 56)

    @Test func snapsToFactoryHorizontalSlot() {
        let factory = PanelAlignment.factoryFrame(size: size, visible: visible)
        let origin = NSPoint(x: factory.origin.x + 8, y: 400)
        let frame = NSRect(origin: origin, size: size)
        let result = PanelAlignment.snap(frame, visible: visible)
        #expect(abs(result.frame.origin.x - factory.origin.x) < 0.5)
        #expect(result.guides.contains { $0.axis == .vertical && abs($0.position - factory.minX) < 0.5 })
        #expect(result.guides.contains { $0.axis == .vertical && abs($0.position - factory.maxX) < 0.5 })
    }

    @Test func doesNotSnapWhenFarFromFactory() {
        let frame = NSRect(x: 40, y: 400, width: size.width, height: size.height)
        let result = PanelAlignment.snap(frame, visible: visible)
        #expect(result.frame.origin.x == 40)
        #expect(!result.guides.contains { $0.axis == .vertical })
    }

    @Test func doesNotSnapToVerticalCenter() {
        let frame = NSRect(
            x: 40,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let result = PanelAlignment.snap(frame, visible: visible)
        #expect(result.frame.origin.y == frame.origin.y)
        #expect(!result.guides.contains { $0.axis == .horizontal && abs($0.position - visible.midY) < 0.5 })
    }

    @Test func snapsToDefaultSpotlightTop() {
        let defaultTop = PanelAlignment.defaultTopY(visible: visible)
        let frame = NSRect(
            x: 80,
            y: defaultTop - size.height + 5,
            width: size.width,
            height: size.height
        )
        let result = PanelAlignment.snap(frame, visible: visible)
        #expect(abs(result.frame.maxY - defaultTop) < 0.5)
    }

    @Test func factoryFrameSnapsToItself() {
        let factory = PanelAlignment.factoryFrame(size: size, visible: visible)
        let result = PanelAlignment.snap(factory, visible: visible)
        #expect(abs(result.frame.origin.x - factory.origin.x) < 0.5)
        #expect(abs(result.frame.maxY - factory.maxY) < 0.5)
        #expect(result.guides.contains { $0.axis == .vertical })
        #expect(result.guides.contains { $0.axis == .horizontal })
    }

    @Test func screenIndexPicksLargestIntersection() {
        let frames = [
            NSRect(x: 0, y: 0, width: 1440, height: 900),
            NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        ]
        let onSecondary = NSRect(x: 1600, y: 400, width: 680, height: 56)
        #expect(PanelPlacement.screenIndex(containing: onSecondary, frames: frames) == 1)
        let offscreen = NSRect(x: -2000, y: -2000, width: 680, height: 56)
        #expect(PanelPlacement.screenIndex(containing: offscreen, frames: frames) == nil)
    }

    @Test func currentScreenPrefersLiveFrameOverSavedPosition() {
        let frames = [
            NSRect(x: 0, y: 0, width: 1440, height: 900),
            NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        ]
        let savedOnPrimary = NSRect(x: 380, y: 600, width: 680, height: 56)
        let draggedToSecondary = NSRect(x: 1700, y: 400, width: 680, height: 56)
        #expect(PanelPlacement.currentScreenIndex(
            liveFrame: draggedToSecondary, savedProbe: savedOnPrimary, frames: frames
        ) == 1)
        #expect(PanelPlacement.currentScreenIndex(
            liveFrame: nil, savedProbe: savedOnPrimary, frames: frames
        ) == 0)
        let offscreen = NSRect(x: -3000, y: -3000, width: 680, height: 56)
        #expect(PanelPlacement.currentScreenIndex(
            liveFrame: offscreen, savedProbe: savedOnPrimary, frames: frames
        ) == 0)
        #expect(PanelPlacement.currentScreenIndex(
            liveFrame: offscreen, savedProbe: nil, frames: frames
        ) == nil)
    }

    @Test func guidesMatchFactoryTargets() {
        let factory = PanelAlignment.factoryFrame(size: size, visible: visible)
        let guides = PanelAlignment.guides(for: factory, visible: visible)
        #expect(guides.contains { $0.axis == .vertical && abs($0.position - factory.minX) < 0.5 })
        #expect(guides.contains { $0.axis == .vertical && abs($0.position - factory.maxX) < 0.5 })
        #expect(guides.contains { $0.axis == .horizontal && abs($0.position - factory.maxY) < 0.5 })
    }
}
