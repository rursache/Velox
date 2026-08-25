import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: SearchPanelController?
    private var statusItem: StatusItemController?
    private var hotKey: HotKey?
    private var volumeObservers: [NSObjectProtocol] = []
    private var appFolderWatcher: AppFolderWatcher?
    private var currencyRefreshTimer: Timer?
    private var indexRefreshTimer: Timer?
    private var indexDebounce: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            Preferences.shared.registerDefaults()
            LaunchAtLogin.apply(Preferences.shared.launchAtLogin)
            // LSUIElement apps have no default Edit menu — without it Cmd+A/C/V/X/Z never fire
            installMainMenu()
            panelController = SearchPanelController(
                appIndex: AppIndex.shared,
                currencyService: CurrencyService.shared
            )
            setupStatusItem()
            listenForActivationHandoff()
            listenForHotKeyChanges()
            finishLaunch()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            if PreferencesWindowController.shared.isVisible {
                PreferencesWindowController.shared.show()
            } else {
                panelController?.show()
            }
        }
        return false
    }

    /// Minimal main menu so standard text-editing key equivalents work in the search field
    @MainActor
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "About \(Constants.App.name)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Settings…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit \(Constants.App.name)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        NSApp.mainMenu = mainMenu
    }

    @MainActor
    private func finishLaunch() {
        setupHotKey()
        watchVolumes()

        Task {
            await AppIndex.shared.rebuild()
            let count = await AppIndex.shared.count
            NSLog("[Velox] Indexed %d apps", count)
            await MainActor.run { [weak self] in
                self?.startAppFolderWatching()
                self?.startIndexRefreshTimer()
            }
        }
        Task {
            await CurrencyService.shared.prepare()
            if Preferences.shared.currencyEnabled {
                await CurrencyService.shared.refreshIfNeeded(trigger: .launch)
            }
        }
        startCurrencyRefreshTimer()

        let args = CommandLine.arguments
        if args.contains("--show") || args.contains("--query") {
            let query: String? = {
                if let idx = args.firstIndex(of: "--query"), args.indices.contains(idx + 1) {
                    return args[idx + 1]
                }
                return nil
            }()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                MainActor.assumeIsolated {
                    self?.panelController?.show()
                    if let query {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            NotificationCenter.default.post(name: .veloxSetQuery, object: query)
                        }
                    }
                }
            }
        }
        #if DEBUG
        if args.contains("--launch-first") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                MainActor.assumeIsolated {
                    self?.panelController?.show()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NotificationCenter.default.post(name: .veloxExecuteSelected, object: nil)
                    }
                }
            }
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    private func setupStatusItem() {
        let item = StatusItemController()
        item.onOpenSettings = { [weak self] in
            self?.openPreferences()
        }
        item.onShowPanel = { [weak self] in
            self?.showPanel()
        }
        item.onRebuildIndex = { [weak self] in
            self?.rebuildIndex()
        }
        statusItem = item
    }

    private func listenForActivationHandoff() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleShowRequest),
            name: SingleInstance.showNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    private func listenForHotKeyChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShortcutDidChange),
            name: .veloxOpenShortcutDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSuspendHotKey),
            name: .veloxSuspendOpenHotKey,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResumeHotKey),
            name: .veloxResumeOpenHotKey,
            object: nil
        )
    }

    @MainActor
    private func watchVolumes() {
        volumeObservers = VolumeWatcher.observe { [weak self] in
            NotificationCenter.default.post(name: .veloxIndexReady, object: AppIndex.shared.signal)
            Task { await AppIndex.shared.rebuild() }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.refreshFolderWatcher()
                }
            }
        }
    }

    @MainActor
    private func startAppFolderWatching() {
        guard !Self.isTestHost else { return }
        if appFolderWatcher == nil {
            appFolderWatcher = AppFolderWatcher { [weak self] in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.requestIndexRebuild(debounce: true)
                    }
                }
            }
        }
        refreshFolderWatcher()
    }

    private static var isTestHost: Bool {
        SingleInstance.isRunningUnderTests()
            || LaunchAtLogin.isTestHost
            || NSClassFromString("XCTestCase") != nil
    }

    @MainActor
    private func refreshFolderWatcher() {
        appFolderWatcher?.update(paths: AppIndexWatchPolicy.watchPaths(from: AppScanner.scanRoots()))
    }

    @MainActor
    private func requestIndexRebuild(debounce: Bool) {
        indexDebounce?.cancel()
        if !debounce {
            rebuildIndex()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.rebuildIndex()
            }
        }
        indexDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + AppIndexWatchPolicy.debounceInterval, execute: work)
    }

    @MainActor
    private func startIndexRefreshTimer() {
        indexRefreshTimer?.invalidate()
        guard !Self.isTestHost else { return }
        let timer = Timer(timeInterval: AppIndexWatchPolicy.periodicInterval, repeats: true) { _ in
            Task {
                if await AppIndex.shared.isStale(maxAge: AppIndexWatchPolicy.periodicInterval) {
                    await AppIndex.shared.rebuild()
                }
            }
        }
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        indexRefreshTimer = timer
    }

    @MainActor
    private func startCurrencyRefreshTimer() {
        currencyRefreshTimer?.invalidate()
        let timer = Timer(timeInterval: Constants.Currency.refreshInterval, repeats: true) { _ in
            Task { @MainActor in
                guard Preferences.shared.currencyEnabled else { return }
                await CurrencyService.shared.refreshIfNeeded(trigger: .hourly)
            }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        currencyRefreshTimer = timer
    }

    @MainActor
    private func setupHotKey() {
        hotKey = nil
        let shortcut = Preferences.shared.openShortcut
        hotKey = HotKey(keyCode: shortcut.keyCode, modifiers: HotKey.Modifiers(rawValue: shortcut.carbonModifiers)) { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.panelController?.toggle()
                }
            }
        }
    }

    @objc private func handleShortcutDidChange() {
        MainActor.assumeIsolated { setupHotKey() }
    }

    @objc private func handleSuspendHotKey() {
        MainActor.assumeIsolated { hotKey = nil }
    }

    @objc private func handleResumeHotKey() {
        MainActor.assumeIsolated { setupHotKey() }
    }

    @objc private func showPanel() {
        MainActor.assumeIsolated {
            panelController?.show()
            Task {
                if Preferences.shared.currencyEnabled {
                    await CurrencyService.shared.refreshIfNeeded(trigger: .panelShow)
                }
            }
        }
    }

    @objc private func openPreferences() {
        MainActor.assumeIsolated {
            PreferencesWindowController.shared.show()
        }
    }

    @objc private func rebuildIndex() {
        Task { @MainActor in
            await AppIndex.shared.rebuild()
            refreshFolderWatcher()
        }
    }

    @objc private func handleShowRequest() {
        MainActor.assumeIsolated {
            if PreferencesWindowController.shared.isVisible {
                PreferencesWindowController.shared.show()
            } else {
                panelController?.show()
            }
        }
    }
}
