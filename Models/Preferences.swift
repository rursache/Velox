import Foundation
import Combine

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private typealias Keys = Constants.PreferenceKey

    /// Spotlight-like default: 8 visible app rows (plus special results)
    @Published var maxResults: Int {
        didSet { defaults.set(maxResults, forKey: Keys.maxResults) }
    }

    @Published var includeSystemApps: Bool {
        didSet { defaults.set(includeSystemApps, forKey: Keys.includeSystemApps) }
    }

    @Published var showPathInSubtitle: Bool {
        didSet { defaults.set(showPathInSubtitle, forKey: Keys.showPathInSubtitle) }
    }

    @Published var mathEnabled: Bool {
        didSet { defaults.set(mathEnabled, forKey: Keys.mathEnabled) }
    }

    @Published var currencyEnabled: Bool {
        didSet { defaults.set(currencyEnabled, forKey: Keys.currencyEnabled) }
    }

    @Published var openShortcut: KeyShortcut {
        didSet {
            defaults.set(Int(openShortcut.keyCode), forKey: Keys.openHotKeyCode)
            defaults.set(Int(openShortcut.carbonModifiers), forKey: Keys.openHotKeyModifiers)
            NotificationCenter.default.post(name: Constants.Notify.openShortcutDidChange, object: nil)
        }
    }

    @Published var themeID: ThemeID {
        didSet {
            defaults.set(themeID.rawValue, forKey: Keys.themeID)
            NotificationCenter.default.post(name: Constants.Notify.themeDidChange, object: nil)
        }
    }

    @Published var highlightID: HighlightID {
        didSet {
            defaults.set(highlightID.rawValue, forKey: Keys.highlightID)
            NotificationCenter.default.post(name: Constants.Notify.themeDidChange, object: nil)
        }
    }

    @Published var panelCornerRadius: CGFloat {
        didSet {
            let clamped = PanelMetrics.clampedRadius(panelCornerRadius)
            if clamped != panelCornerRadius {
                panelCornerRadius = clamped
                return
            }
            defaults.set(Double(panelCornerRadius), forKey: Keys.panelCornerRadius)
            NotificationCenter.default.post(name: Constants.Notify.themeDidChange, object: nil)
        }
    }

    @Published var panelScreenPolicy: PanelScreenPolicy {
        didSet { defaults.set(panelScreenPolicy.rawValue, forKey: Keys.panelScreenPolicy) }
    }

    var theme: Theme { ThemeCatalog.theme(for: themeID) }
    var highlight: SelectionStyle { HighlightCatalog.style(for: highlightID) }

    /// Saved panel position: origin.x + maxY (top edge). Nil until user moves the panel
    var customPanelPosition: (x: CGFloat, maxY: CGFloat)? {
        get {
            guard defaults.bool(forKey: Keys.hasCustomPanelPosition) else { return nil }
            return (
                CGFloat(defaults.double(forKey: Keys.panelOriginX)),
                CGFloat(defaults.double(forKey: Keys.panelMaxY))
            )
        }
        set {
            if let newValue {
                defaults.set(Double(newValue.x), forKey: Keys.panelOriginX)
                defaults.set(Double(newValue.maxY), forKey: Keys.panelMaxY)
                defaults.set(true, forKey: Keys.hasCustomPanelPosition)
            } else {
                defaults.removeObject(forKey: Keys.panelOriginX)
                defaults.removeObject(forKey: Keys.panelMaxY)
                defaults.set(false, forKey: Keys.hasCustomPanelPosition)
            }
        }
    }

    private init() {
        maxResults = defaults.object(forKey: Keys.maxResults) as? Int ?? Constants.Defaults.maxResults
        if !defaults.bool(forKey: Keys.systemAppsDefaultOff) {
            defaults.set(Constants.Defaults.includeSystemApps, forKey: Keys.includeSystemApps)
            defaults.set(true, forKey: Keys.systemAppsDefaultOff)
        }
        includeSystemApps = defaults.object(forKey: Keys.includeSystemApps) as? Bool ?? Constants.Defaults.includeSystemApps
        showPathInSubtitle = defaults.object(forKey: Keys.showPathInSubtitle) as? Bool ?? Constants.Defaults.showPathInSubtitle
        mathEnabled = defaults.object(forKey: Keys.mathEnabled) as? Bool ?? Constants.Defaults.mathEnabled
        currencyEnabled = defaults.object(forKey: Keys.currencyEnabled) as? Bool ?? Constants.Defaults.currencyEnabled
        if defaults.object(forKey: Keys.openHotKeyCode) != nil {
            openShortcut = KeyShortcut(
                keyCode: UInt32(defaults.integer(forKey: Keys.openHotKeyCode)),
                carbonModifiers: UInt32(defaults.integer(forKey: Keys.openHotKeyModifiers))
            )
        } else {
            openShortcut = Constants.Defaults.openShortcut
        }
        themeID = ThemeID.parse(defaults.string(forKey: Keys.themeID)) ?? Constants.Defaults.themeID
        highlightID = HighlightID.parse(defaults.string(forKey: Keys.highlightID)) ?? Constants.Defaults.highlightID
        if defaults.object(forKey: Keys.panelCornerRadius) != nil {
            panelCornerRadius = PanelMetrics.clampedRadius(CGFloat(defaults.double(forKey: Keys.panelCornerRadius)))
        } else {
            panelCornerRadius = Constants.Defaults.panelCornerRadius
        }
        panelScreenPolicy = PanelScreenPolicy(rawValue: defaults.string(forKey: Keys.panelScreenPolicy) ?? "")
            ?? Constants.Defaults.panelScreenPolicy
    }

    func resetPanelPosition() {
        customPanelPosition = nil
        NotificationCenter.default.post(name: Constants.Notify.panelPositionDidReset, object: nil)
    }

    func registerDefaults() {
        defaults.register(defaults: [
            Keys.maxResults: Constants.Defaults.maxResults,
            Keys.includeSystemApps: Constants.Defaults.includeSystemApps,
            Keys.showPathInSubtitle: Constants.Defaults.showPathInSubtitle,
            Keys.mathEnabled: Constants.Defaults.mathEnabled,
            Keys.currencyEnabled: Constants.Defaults.currencyEnabled,
            Keys.themeID: Constants.Defaults.themeID.rawValue,
            Keys.highlightID: Constants.Defaults.highlightID.rawValue,
            Keys.panelCornerRadius: Double(Constants.Defaults.panelCornerRadius),
            Keys.panelScreenPolicy: Constants.Defaults.panelScreenPolicy.rawValue
        ])
    }
}
