import AppKit

enum StatusItemAppearance {
    static let searchSymbol = Constants.Symbol.search
    static let settingsSymbol = Constants.Symbol.settings

    /// Search-field hover only; the menu-bar item always uses `searchSymbol`
    static func symbolName(hovering: Bool) -> String {
        hovering ? settingsSymbol : searchSymbol
    }

    static func templateImage() -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = NSImage(systemSymbolName: searchSymbol, accessibilityDescription: Constants.App.name)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }
}

@MainActor
final class StatusItemController: NSObject {
    var onOpenSettings: () -> Void = {}
    var onShowPanel: () -> Void = {}
    var onRebuildIndex: () -> Void = {}

    private let item: NSStatusItem

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        guard let button = item.button else { return }
        button.title = ""
        button.imagePosition = .imageOnly
        button.image = StatusItemAppearance.templateImage()
        button.image?.isTemplate = true
        button.toolTip = Constants.App.name
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func showContextMenu() {
        guard let button = item.button else { return }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show \(Constants.App.name)", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Rebuild App Index", action: #selector(rebuildIndex), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit \(Constants.App.name)", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
    }

    @objc private func handleClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
            return
        }
        onOpenSettings()
    }

    @objc private func showPanel() {
        onShowPanel()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func rebuildIndex() {
        onRebuildIndex()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
