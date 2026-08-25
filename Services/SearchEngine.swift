import Foundation
import Combine
import AppKit

@MainActor
final class SearchEngine: ObservableObject {
    @Published var query: String = ""
    @Published var results: [SearchResult] = []
    @Published var selectedIndex: Int = 0
    @Published var isIndexing: Bool = false

    private let appIndex: AppIndex
    private let currencyService: CurrencyService
    private var appsSnapshot: [AppEntry] = []
    private var searchTask: Task<Void, Never>?
    private var searchGeneration: UInt64 = 0
    private var observers: [NSObjectProtocol] = []

    init(appIndex: AppIndex, currencyService: CurrencyService) {
        self.appIndex = appIndex
        self.currencyService = currencyService
        observers = [
            NotificationCenter.default.addObserver(
                forName: .veloxIndexReady,
                object: appIndex.signal,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshSnapshot()
                    await self?.replayCurrentQuery()
                }
            },
            NotificationCenter.default.addObserver(
                forName: .veloxRatesDidChange,
                object: currencyService.signal,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.replayCurrentQuery()
                }
            }
        ]
        Task { await refreshSnapshot() }
    }

    func refreshSnapshot() async {
        appsSnapshot = await appIndex.apps
        isIndexing = !(await appIndex.isReady)
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func showChromePreview() {
        searchTask?.cancel()
        searchGeneration &+= 1
        query = ""
        applyResults(SearchPanelPreview.rows)
    }

    func endChromePreview() {
        updateQuery("")
    }

    func updateQuery(_ newQuery: String) {
        query = newQuery
        searchGeneration &+= 1
        let generation = searchGeneration

        searchTask?.cancel()

        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            applyResults([])
            return
        }

        searchTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            guard generation == self.searchGeneration else { return }
            await self.performSearch(for: trimmed, generation: generation)
        }
    }

    func searchNow(_ newQuery: String) async {
        query = newQuery
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()
        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            applyResults([])
            return
        }
        await performSearch(for: trimmed, generation: generation)
    }

    func replayCurrentQuery() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchGeneration &+= 1
        await performSearch(for: trimmed, generation: searchGeneration)
    }

    private func performSearch(for q: String, generation: UInt64) async {
        guard generation == searchGeneration else { return }
        guard query.trimmingCharacters(in: .whitespacesAndNewlines) == q else { return }

        let prefs = Preferences.shared
        let limit = max(1, min(prefs.maxResults, Constants.Defaults.maxResultsHardCap))
        var items: [SearchResult] = []

        if prefs.mathEnabled, let math = MathEngine.evaluate(q) {
            items.append(SearchResult(
                id: "calc-\(math.raw)",
                kind: .calculation,
                title: math.display,
                subtitle: "Calculation · ⏎ to copy",
                score: 200_000,
                copyValue: math.raw,
                action: {
                    DispatchQueue.main.async {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(math.raw, forType: .string)
                    }
                }
            ))
        }

        if prefs.currencyEnabled, let parsed = CurrencyService.parse(q) {
            if let fx = await currencyService.convert(parsed: parsed) {
                guard generation == searchGeneration else { return }
                let copyVal = fx.copy
                items.append(SearchResult(
                    id: "fx-\(fx.title)-\(fx.subtitle)",
                    kind: .currency,
                    title: fx.title,
                    subtitle: fx.subtitle + (copyVal == "—" ? "" : " · ⏎ to copy"),
                    score: 180_000,
                    copyValue: copyVal,
                    action: {
                        guard copyVal != "—" else { return }
                        DispatchQueue.main.async {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(copyVal, forType: .string)
                        }
                    }
                ))
            }
        }

        let apps = AppSearch.ranked(
            apps: appsSnapshot,
            query: q,
            limit: limit,
            includeSystem: prefs.includeSystemApps
        )
        guard generation == searchGeneration else { return }
        guard query.trimmingCharacters(in: .whitespacesAndNewlines) == q else { return }

        for hit in apps {
            let app = hit.app
            let subtitle: String
            if prefs.showPathInSubtitle {
                subtitle = app.path
            } else if let bid = app.bundleIdentifier {
                subtitle = "Application · \(bid)"
            } else {
                subtitle = "Application"
            }
            let appURL = app.url
            items.append(SearchResult(
                id: "app-\(app.id)",
                kind: .app,
                title: app.name,
                subtitle: subtitle,
                score: hit.score,
                app: app,
                action: {
                    AppLauncher.launch(url: appURL)
                }
            ))
        }

        items.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.title.count < rhs.title.count
        }

        applyResults(items)
    }

    private func applyResults(_ items: [SearchResult]) {
        if Self.sameVisibleResults(results, items) {
            return
        }

        let previousCount = results.count
        results = items
        selectedIndex = 0

        if previousCount != items.count {
            NotificationCenter.default.post(name: .veloxResultsDidChange, object: nil)
        }
    }

    private static func sameVisibleResults(_ a: [SearchResult], _ b: [SearchResult]) -> Bool {
        guard a.count == b.count else { return false }
        for i in a.indices {
            if a[i].id != b[i].id { return false }
            if a[i].title != b[i].title { return false }
            if a[i].subtitle != b[i].subtitle { return false }
        }
        return true
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let count = results.count
        selectedIndex = (selectedIndex + delta + count) % count
    }

    @discardableResult
    func executeSelected() async -> SearchResultKind? {
        let previousId = results.indices.contains(selectedIndex) ? results[selectedIndex].id : nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            searchTask?.cancel()
            searchGeneration &+= 1
            await performSearch(for: trimmed, generation: searchGeneration)
        }
        if let previousId, let idx = results.firstIndex(where: { $0.id == previousId }) {
            selectedIndex = idx
            let item = results[idx]
            item.action()
            return item.kind
        }
        if previousId != nil {
            return nil
        }
        guard results.indices.contains(selectedIndex) else { return nil }
        let item = results[selectedIndex]
        item.action()
        return item.kind
    }
}

enum AppLauncher {
    static func launch(url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                NSLog("[Velox] Launch failed: %@", error.localizedDescription)
            }
        }
    }
}
