import AppKit
import SwiftUI

enum ThemeID: String, CaseIterable, Identifiable, Sendable {
    case glass
    case clear
    case midnight
    case snow
    case olive
    case harbor
    case orchid
    case parchment

    var id: String { rawValue }

    static func parse(_ raw: String?) -> ThemeID? {
        switch raw {
        case "spotlight":
            return .glass
        case "frost":
            return .snow
        case "graphite":
            return .midnight
        case let value?:
            return ThemeID(rawValue: value)
        default:
            return nil
        }
    }
}

enum HighlightID: String, CaseIterable, Identifiable, Sendable {
    case accent
    case soft
    case contrast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accent: return "Accent"
        case .soft: return "Soft"
        case .contrast: return "Contrast"
        }
    }

    static func parse(_ raw: String?) -> HighlightID? {
        raw.flatMap(HighlightID.init(rawValue:))
    }
}

enum HairlineKind: Equatable, Sendable {
    case white(alpha: CGFloat)
    case separator
    case label(alpha: CGFloat)
}

struct Hairline: Equatable, Sendable {
    var kind: HairlineKind
    var width: CGFloat

    func cgColor(in appearance: NSAppearance) -> CGColor {
        var color = CGColor(gray: 1, alpha: 0.14)
        appearance.performAsCurrentDrawingAppearance {
            color = nsColor.cgColor
        }
        return color
    }

    private var nsColor: NSColor {
        switch kind {
        case .white(let alpha):
            return NSColor.white.withAlphaComponent(alpha)
        case .separator:
            return NSColor.separatorColor
        case .label(let alpha):
            return NSColor.labelColor.withAlphaComponent(alpha)
        }
    }
}

enum SelectionFill: Equatable, Sendable {
    case accent(opacity: CGFloat)
    case primary(opacity: CGFloat)
}

struct SelectionStyle: Equatable, Sendable {
    var fill: SelectionFill
    var invertLabels: Bool

    var color: Color {
        switch fill {
        case .accent(let opacity):
            return Color.accentColor.opacity(opacity)
        case .primary(let opacity):
            return Color.primary.opacity(opacity)
        }
    }
}

enum ThemeLegibility: Equatable, Sendable {
    case followSystem
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .followSystem: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .followSystem: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

struct ThemeWash: Equatable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    static let none = ThemeWash(red: 0, green: 0, blue: 0, alpha: 0)

    init(white: CGFloat, alpha: CGFloat) {
        self.red = white
        self.green = white
        self.blue = white
        self.alpha = alpha
    }

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat) -> ThemeWash {
        ThemeWash(red: red, green: green, blue: blue, alpha: alpha)
    }

    func cgColor(in appearance: NSAppearance) -> CGColor {
        var color = CGColor(red: red, green: green, blue: blue, alpha: alpha)
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor(red: red, green: green, blue: blue, alpha: alpha).cgColor
        }
        return color
    }

    var swatchColor: Color {
        Color(red: red, green: green, blue: blue)
    }

    var white: CGFloat {
        (red + green + blue) / 3
    }
}

struct Theme: Equatable, Identifiable, Sendable {
    var id: ThemeID
    var name: String
    var materialRaw: Int
    var hairline: Hairline
    var wash: ThemeWash
    var legibility: ThemeLegibility
    var rowCornerRadius: CGFloat
    var dividerOpacity: Double
    var previewWhite: CGFloat

    var material: NSVisualEffectView.Material {
        NSVisualEffectView.Material(rawValue: materialRaw) ?? .hudWindow
    }

    var previewColor: Color {
        wash.alpha > 0.08 ? wash.swatchColor : Color(white: previewWhite)
    }
}

enum HighlightCatalog {
    static let all: [HighlightID] = HighlightID.allCases

    static func style(for id: HighlightID) -> SelectionStyle {
        switch id {
        case .accent:
            return SelectionStyle(fill: .accent(opacity: 0.85), invertLabels: true)
        case .soft:
            return SelectionStyle(fill: .accent(opacity: 0.28), invertLabels: false)
        case .contrast:
            return SelectionStyle(fill: .primary(opacity: 0.82), invertLabels: true)
        }
    }
}

enum ThemeCatalog {
    static let all: [Theme] = [glass, clear, midnight, snow, olive, harbor, orchid, parchment]

    static func theme(for id: ThemeID) -> Theme {
        switch id {
        case .glass: return glass
        case .clear: return clear
        case .midnight: return midnight
        case .snow: return snow
        case .olive: return olive
        case .harbor: return harbor
        case .orchid: return orchid
        case .parchment: return parchment
        }
    }

    static func theme(for raw: String?) -> Theme {
        theme(for: ThemeID.parse(raw) ?? .glass)
    }

    static let glass = Theme(
        id: .glass,
        name: "Glass",
        materialRaw: NSVisualEffectView.Material.hudWindow.rawValue,
        hairline: Hairline(kind: .white(alpha: 0.14), width: 0.5),
        wash: .none,
        legibility: .dark,
        rowCornerRadius: 8,
        dividerOpacity: 0.35,
        previewWhite: 0.22
    )

    static let clear = Theme(
        id: .clear,
        name: "Clear",
        materialRaw: NSVisualEffectView.Material.titlebar.rawValue,
        hairline: Hairline(kind: .separator, width: 0.5),
        wash: ThemeWash(white: 1, alpha: 0.10),
        legibility: .light,
        rowCornerRadius: 8,
        dividerOpacity: 0.3,
        previewWhite: 0.90
    )

    static let midnight = Theme(
        id: .midnight,
        name: "Midnight",
        materialRaw: NSVisualEffectView.Material.menu.rawValue,
        hairline: Hairline(kind: .white(alpha: 0.08), width: 0.5),
        wash: ThemeWash(white: 0, alpha: 0.42),
        legibility: .dark,
        rowCornerRadius: 8,
        dividerOpacity: 0.22,
        previewWhite: 0.08
    )

    static let snow = Theme(
        id: .snow,
        name: "Snow",
        materialRaw: NSVisualEffectView.Material.headerView.rawValue,
        hairline: Hairline(kind: .label(alpha: 0.16), width: 0.5),
        wash: ThemeWash(white: 1, alpha: 0.72),
        legibility: .light,
        rowCornerRadius: 8,
        dividerOpacity: 0.28,
        previewWhite: 0.97
    )

    static let olive = Theme(
        id: .olive,
        name: "Olive",
        materialRaw: NSVisualEffectView.Material.menu.rawValue,
        hairline: Hairline(kind: .white(alpha: 0.12), width: 0.5),
        wash: ThemeWash.rgb(0.153, 0.157, 0.133, alpha: 0.56),
        legibility: .dark,
        rowCornerRadius: 8,
        dividerOpacity: 0.24,
        previewWhite: 0.16
    )

    static let harbor = Theme(
        id: .harbor,
        name: "Harbor",
        materialRaw: NSVisualEffectView.Material.menu.rawValue,
        hairline: Hairline(kind: .white(alpha: 0.10), width: 0.5),
        wash: ThemeWash.rgb(0.00, 0.169, 0.212, alpha: 0.50),
        legibility: .dark,
        rowCornerRadius: 8,
        dividerOpacity: 0.22,
        previewWhite: 0.12
    )

    static let orchid = Theme(
        id: .orchid,
        name: "Orchid",
        materialRaw: NSVisualEffectView.Material.menu.rawValue,
        hairline: Hairline(kind: .white(alpha: 0.12), width: 0.5),
        wash: ThemeWash.rgb(0.157, 0.165, 0.212, alpha: 0.52),
        legibility: .dark,
        rowCornerRadius: 8,
        dividerOpacity: 0.24,
        previewWhite: 0.14
    )

    static let parchment = Theme(
        id: .parchment,
        name: "Parchment",
        materialRaw: NSVisualEffectView.Material.headerView.rawValue,
        hairline: Hairline(kind: .label(alpha: 0.16), width: 0.5),
        wash: ThemeWash.rgb(0.984, 0.945, 0.780, alpha: 0.64),
        legibility: .light,
        rowCornerRadius: 8,
        dividerOpacity: 0.26,
        previewWhite: 0.93
    )
}

struct PanelMetrics: Equatable, Sendable {
    var width: CGFloat
    var searchRowHeight: CGFloat
    var resultRowHeight: CGFloat
    var resultsBottomPad: CGFloat
    var topAnchorFraction: CGFloat
    var cornerRadius: CGFloat
    var snapThreshold: CGFloat
    var iconColumn: CGFloat
    var barPaddingX: CGFloat
    var resultInsetX: CGFloat
    var stackSpacing: CGFloat

    static let cornerRadiusRange: ClosedRange<CGFloat> = 12...48
    static let cornerRadiusStep: CGFloat = 2

    static let standard = PanelMetrics(
        width: 680,
        searchRowHeight: 56,
        resultRowHeight: 48,
        resultsBottomPad: 8,
        topAnchorFraction: 0.22,
        cornerRadius: 16,
        snapThreshold: 20,
        iconColumn: 32,
        barPaddingX: 16,
        resultInsetX: 8,
        stackSpacing: 12
    )

    static func clampedRadius(_ value: CGFloat) -> CGFloat {
        let clamped = min(max(value, cornerRadiusRange.lowerBound), cornerRadiusRange.upperBound)
        let steps = ((clamped - cornerRadiusRange.lowerBound) / cornerRadiusStep).rounded()
        return cornerRadiusRange.lowerBound + steps * cornerRadiusStep
    }
}

enum PanelScreenPolicy: String, CaseIterable, Identifiable, Sendable {
    case mouse
    case activeWindow
    case allScreens

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mouse: return "Screen with mouse"
        case .activeWindow: return "Screen with active window"
        case .allScreens: return "Show on all screens"
        }
    }

    var showsOnEveryScreen: Bool { self == .allScreens }
}

enum PanelPlacement {
    static func screenIndex(
        mouse: NSPoint,
        frames: [NSRect],
        mainIndex: Int?,
        policy: PanelScreenPolicy
    ) -> Int? {
        switch policy {
        case .mouse, .allScreens:
            return frames.firstIndex { NSMouseInRect(mouse, $0, false) } ?? mainIndex
        case .activeWindow:
            if let mainIndex, frames.indices.contains(mainIndex) { return mainIndex }
            return frames.firstIndex { NSMouseInRect(mouse, $0, false) }
        }
    }

    static func replicaScreenIndexes(
        primary: Int?,
        count: Int,
        policy: PanelScreenPolicy
    ) -> [Int] {
        guard policy.showsOnEveryScreen, count > 1 else { return [] }
        let keep = primary ?? 0
        return (0..<count).filter { $0 != keep }
    }

    /// The screen the panel is on right now. A visible panel's live frame wins over the saved
    /// position, which is stale while the user is still dragging across displays
    static func currentScreenIndex(
        liveFrame: NSRect?,
        savedProbe: NSRect?,
        frames: [NSRect]
    ) -> Int? {
        if let liveFrame, let index = screenIndex(containing: liveFrame, frames: frames) {
            return index
        }
        if let savedProbe, let index = screenIndex(containing: savedProbe, frames: frames) {
            return index
        }
        return nil
    }

    static func screenIndex(containing frame: NSRect, frames: [NSRect], minArea: CGFloat = 48 * 24) -> Int? {
        var best: (Int, CGFloat)?
        for (index, candidate) in frames.enumerated() {
            let intersection = frame.intersection(candidate)
            guard !intersection.isNull, !intersection.isInfinite else { continue }
            let area = intersection.width * intersection.height
            if best == nil || area > best!.1 {
                best = (index, area)
            }
        }
        guard let best, best.1 >= minArea else { return nil }
        return best.0
    }
}
