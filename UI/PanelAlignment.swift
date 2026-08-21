import AppKit

enum PanelAlignment {
    struct Guide: Equatable {
        enum Axis: Equatable {
            case vertical
            case horizontal
        }

        var axis: Axis
        var position: CGFloat
    }

    static func defaultTopY(visible: NSRect, fraction: CGFloat = Constants.Panel.topAnchorFraction) -> CGFloat {
        visible.minY + visible.height * (1.0 - fraction)
    }

    static func factoryFrame(size: NSSize, visible: NSRect, fraction: CGFloat = Constants.Panel.topAnchorFraction) -> NSRect {
        let x = visible.midX - size.width / 2
        let top = defaultTopY(visible: visible, fraction: fraction)
        return NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }

    static func snap(
        _ frame: NSRect,
        visible: NSRect,
        threshold: CGFloat = Constants.Panel.snapThreshold,
        defaultTopFraction: CGFloat = Constants.Panel.topAnchorFraction
    ) -> (frame: NSRect, guides: [Guide]) {
        var snapped = frame
        var guides: [Guide] = []
        let factory = factoryFrame(size: frame.size, visible: visible, fraction: defaultTopFraction)

        if abs(frame.origin.x - factory.origin.x) <= threshold {
            snapped.origin.x = factory.origin.x
            guides.append(Guide(axis: .vertical, position: factory.minX))
            guides.append(Guide(axis: .vertical, position: factory.maxX))
        }

        if abs(frame.maxY - factory.maxY) <= threshold {
            snapped.origin.y = factory.maxY - frame.height
            guides.append(Guide(axis: .horizontal, position: factory.maxY))
        }

        return (snapped, guides)
    }

    static func guides(
        for frame: NSRect,
        visible: NSRect,
        threshold: CGFloat = Constants.Panel.snapThreshold,
        defaultTopFraction: CGFloat = Constants.Panel.topAnchorFraction
    ) -> [Guide] {
        snap(frame, visible: visible, threshold: threshold, defaultTopFraction: defaultTopFraction).guides
    }
}
