import AppKit

enum Constants {
    enum App {
        static let name = "Velox"
        static let bundleIdentifier = "ro.randusoft.velox"
        static let supportFolderName = "Velox"
        static let settingsWindowTitle = "Settings"
        static let unknownVersionLabel = "v0.0.0 (0)"
    }

    enum Defaults {
        static let maxResults = 8
        static let maxResultsMin = 3
        static let maxResultsMax = 30
        static let maxResultsHardCap = 50
        static let includeSystemApps = false
        static let showPathInSubtitle = false
        static let mathEnabled = true
        static let currencyEnabled = true
        static let launchAtLogin = true
        static let openShortcut = KeyShortcut.optionSpace
        static let themeID = ThemeID.glass
        static let highlightID = HighlightID.accent
        static let panelCornerRadius = PanelMetrics.standard.cornerRadius
        static let panelScreenPolicy = PanelScreenPolicy.mouse

        static var maxResultsRange: ClosedRange<Int> {
            maxResultsMin...maxResultsMax
        }
    }

    enum PreferenceKey {
        static let maxResults = "maxResults"
        static let includeSystemApps = "includeSystemApps"
        static let showPathInSubtitle = "showPathInSubtitle"
        static let mathEnabled = "mathEnabled"
        static let currencyEnabled = "currencyEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let panelOriginX = "panelOriginX"
        static let panelMaxY = "panelMaxY"
        static let hasCustomPanelPosition = "hasCustomPanelPosition"
        static let systemAppsDefaultOff = "systemAppsDefaultOff"
        static let openHotKeyCode = "openHotKeyCode"
        static let openHotKeyModifiers = "openHotKeyModifiers"
        static let themeID = "themeID"
        static let highlightID = "highlightID"
        static let panelCornerRadius = "panelCornerRadius"
        static let panelScreenPolicy = "panelScreenPolicy"
    }

    enum Panel {
        static var width: CGFloat { PanelMetrics.standard.width }
        static var searchRowHeight: CGFloat { PanelMetrics.standard.searchRowHeight }
        static var resultRowHeight: CGFloat { PanelMetrics.standard.resultRowHeight }
        static var resultsBottomPad: CGFloat { PanelMetrics.standard.resultsBottomPad }
        static var topAnchorFraction: CGFloat { PanelMetrics.standard.topAnchorFraction }
        static var cornerRadius: CGFloat { PanelMetrics.standard.cornerRadius }
        static var snapThreshold: CGFloat { PanelMetrics.standard.snapThreshold }
        static var iconColumn: CGFloat { PanelMetrics.standard.iconColumn }
        static var barPaddingX: CGFloat { PanelMetrics.standard.barPaddingX }
        static var resultInsetX: CGFloat { PanelMetrics.standard.resultInsetX }
        static var stackSpacing: CGFloat { PanelMetrics.standard.stackSpacing }
    }

    enum SettingsWindow {
        static let width: CGFloat = 760
        static let height: CGFloat = 424
        static var size: CGSize { CGSize(width: width, height: height) }
    }

    enum Index {
        static let folderDebounce: TimeInterval = 1.5
        static let periodicRefresh: TimeInterval = 120
        static let panelShowMaxAge: TimeInterval = 120
    }

    enum Currency {
        static let cacheFileName = "rates.json"
        static let refreshInterval: TimeInterval = 3600
        static let attemptThrottle: TimeInterval = 30
        static let primaryAPI = "https://api.frankfurter.app/latest"
        static let fallbackAPI = "https://api.frankfurter.dev/v1/latest"
    }

    enum HotKey {
        static let carbonSignature: UInt32 = 0x564C5858
        static let spaceKeyCode: UInt32 = 49
    }

    enum Symbol {
        static let search = "magnifyingglass"
        static let settings = "gearshape"
    }

    enum Notify {
        static let showExistingInstance = Notification.Name("com.velox.launcher.show")
        static let openShortcutDidChange = Notification.Name("veloxOpenShortcutDidChange")
        static let suspendOpenHotKey = Notification.Name("veloxSuspendOpenHotKey")
        static let resumeOpenHotKey = Notification.Name("veloxResumeOpenHotKey")
        static let cancelHotKeyCapture = Notification.Name("veloxCancelHotKeyCapture")
        static let focusSearch = Notification.Name("veloxFocusSearch")
        static let resultsDidChange = Notification.Name("veloxResultsDidChange")
        static let setQuery = Notification.Name("veloxSetQuery")
        static let executeSelected = Notification.Name("veloxExecuteSelected")
        static let indexReady = Notification.Name("veloxIndexReady")
        static let selectAllSearchText = Notification.Name("veloxSelectAllSearchText")
        static let ratesDidChange = Notification.Name("veloxRatesDidChange")
        static let hidePanel = Notification.Name("veloxHidePanel")
        static let showPanelPreview = Notification.Name("veloxShowPanelPreview")
        static let hidePanelPreview = Notification.Name("veloxHidePanelPreview")
        static let themeDidChange = Notification.Name("veloxThemeDidChange")
        static let panelPositionDidReset = Notification.Name("veloxPanelPositionDidReset")
    }
}
