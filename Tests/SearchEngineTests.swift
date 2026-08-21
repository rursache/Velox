import Testing
import Foundation
import AppKit
@testable import Velox

@MainActor
@Suite("Search engine", .serialized)
struct SearchEngineTests {
    private func makeEngine(apps: [AppEntry] = [], rates: [String: Double] = ["USD": 1.1]) async -> SearchEngine {
        Preferences.shared.mathEnabled = true
        Preferences.shared.currencyEnabled = true
        let index = AppIndex()
        await index.replaceAppsForTesting(apps)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fx = CurrencyService(cacheURL: dir.appendingPathComponent("rates.json"))
        await fx.replaceRatesForTesting(rates)
        let engine = SearchEngine(appIndex: index, currencyService: fx)
        await engine.refreshSnapshot()
        return engine
    }

    private func sampleApp(
        name: String,
        fileName: String? = nil,
        path: String = "/Applications/Demo.app"
    ) -> AppEntry {
        AppEntry(
            name: name,
            path: path,
            bundleIdentifier: "com.example.demo",
            url: URL(fileURLWithPath: path),
            fileName: fileName,
            isSystem: false
        )
    }

    @Test func currencyOutranksExactAppName() async {
        let engine = await makeEngine(apps: [sampleApp(name: "USD EUR", path: "/Applications/USDEUR.app")])
        await engine.searchNow("usd eur")
        #expect(engine.results.first?.kind == .currency)
        #expect(engine.results.contains { $0.kind == .app })
    }

    @Test func mathOutranksCurrencyAndApps() async {
        let engine = await makeEngine(apps: [sampleApp(name: "Calculator")])
        await engine.searchNow("12*8")
        #expect(engine.results.first?.kind == .calculation)
        #expect(engine.results.first?.score == 200_000)
    }

    @Test func chromePreviewShowsSampleRowsAndClears() async {
        let engine = await makeEngine()
        engine.showChromePreview()
        #expect(engine.results.map(\.id) == SearchPanelPreview.rows.map(\.id))
        #expect(engine.results.count == 3)
        #expect(engine.query.isEmpty)
        engine.endChromePreview()
        #expect(engine.results.isEmpty)
    }

    @Test func emptyQueryClearsImmediately() async {
        let engine = await makeEngine(apps: [sampleApp(name: "Safari")])
        await engine.searchNow("Safari")
        #expect(!engine.results.isEmpty)
        engine.updateQuery("")
        #expect(engine.results.isEmpty)
    }

    @Test func filenameOnlyHitAppears() async {
        let calendar = sampleApp(
            name: "日历",
            fileName: "Calendar",
            path: "/Applications/Calendar.app"
        )
        let engine = await makeEngine(apps: [calendar])
        await engine.searchNow("cal")
        #expect(engine.results.contains { $0.kind == .app && $0.title == "日历" })
    }

    @Test func maxResultsCapsAppsOnly() async {
        let previous = Preferences.shared.maxResults
        Preferences.shared.maxResults = 3
        defer { Preferences.shared.maxResults = previous }
        let apps = (1...8).map {
            sampleApp(name: "Calc\($0)", path: "/Applications/Calc\($0).app")
        }
        let engine = await makeEngine(apps: apps)
        await engine.searchNow("calc")
        #expect(engine.results.filter { $0.kind == .app }.count == 3)
        await engine.searchNow("12*8")
        #expect(engine.results.contains { $0.kind == .calculation })
    }

    @Test func moveSelectionWraps() async {
        let engine = await makeEngine(apps: [
            sampleApp(name: "Safari", path: "/Applications/Safari.app"),
            sampleApp(name: "Safe", path: "/Applications/Safe.app")
        ])
        await engine.searchNow("saf")
        #expect(engine.results.count >= 2)
        engine.selectedIndex = engine.results.count - 1
        engine.moveSelection(by: 1)
        #expect(engine.selectedIndex == 0)
    }

    @Test func executeDoesNotLaunchADifferentRowWhenSelectionVanishes() async {
        let first = sampleApp(name: "Travel", path: "/Applications/Travel.app")
        let local = sampleApp(name: "Notes", path: "/Applications/Notes.app")
        let index = AppIndex()
        await index.replaceAppsForTesting([first, local])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fx = CurrencyService(cacheURL: dir.appendingPathComponent("rates.json"))
        await fx.replaceRatesForTesting(["USD": 1.1])
        let engine = SearchEngine(appIndex: index, currencyService: fx)
        await engine.refreshSnapshot()
        await engine.searchNow("t")
        engine.selectedIndex = engine.results.firstIndex { $0.title == "Travel" } ?? 0
        await index.replaceAppsForTesting([local])
        await engine.refreshSnapshot()
        #expect(await engine.executeSelected() == nil)
    }

    @Test func executeOnEmptyIsNil() async {
        let engine = await makeEngine()
        #expect(await engine.executeSelected() == nil)
    }

    @Test func currencyUsesFixtureAndShowsRow() async {
        let engine = await makeEngine()
        await engine.searchNow("110 USD to EUR")
        #expect(engine.results.contains { $0.kind == .currency })
    }

    @Test func unavailableCurrencyRowIsVisible() async {
        let index = AppIndex()
        await index.replaceAppsForTesting([])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fx = CurrencyService(cacheURL: dir.appendingPathComponent("rates.json"))
        let engine = SearchEngine(appIndex: index, currencyService: fx)
        await engine.searchNow("100 USD to GBP")
        #expect(engine.results.contains { $0.kind == .currency && $0.title == "Currency rates unavailable" })
    }

    @Test func replaysQueryWhenIndexBecomesReady() async throws {
        let index = AppIndex()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fx = CurrencyService(cacheURL: dir.appendingPathComponent("rates.json"))
        await fx.replaceRatesForTesting(["USD": 1.1])
        let engine = SearchEngine(appIndex: index, currencyService: fx)
        await engine.searchNow("Safari")
        #expect(engine.results.isEmpty)
        await index.replaceAppsForTesting([
            sampleApp(name: "Safari", path: "/Applications/Safari.app")
        ])
        NotificationCenter.default.post(name: .veloxIndexReady, object: index.signal)
        try await Task.sleep(nanoseconds: 80_000_000)
        #expect(engine.results.contains { $0.title == "Safari" })
    }

    @Test func updateQueryPopulatesResults() async throws {
        let engine = await makeEngine()
        engine.updateQuery("12*8")
        try await Task.sleep(nanoseconds: 40_000_000)
        #expect(engine.results.first?.kind == .calculation)
    }

    @Test func unknownPairShowsUnavailableRow() async {
        let engine = await makeEngine(rates: ["USD": 1.1])
        await engine.searchNow("100 USD to GBP")
        #expect(engine.results.contains { $0.kind == .currency && $0.title == "Currency rates unavailable" })
    }

    @Test func executeSelectedReturnsCalculation() async {
        let engine = await makeEngine()
        await engine.searchNow("2+2")
        #expect(await engine.executeSelected() == .calculation)
    }

    @Test func unavailableCurrencyDoesNotCopyPlaceholder() async {
        let engine = await makeEngine(rates: ["USD": 1.1])
        await engine.searchNow("100 USD to GBP")
        let row = engine.results.first { $0.kind == .currency }
        #expect(row?.copyValue == "—")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("keep", forType: .string)
        #expect(await engine.executeSelected() == .currency)
        #expect(NSPasteboard.general.string(forType: .string) == "keep")
    }

    @Test func disabledMathSkipsCalculationRows() async {
        let engine = await makeEngine(apps: [sampleApp(name: "Calculator")])
        Preferences.shared.mathEnabled = false
        defer { Preferences.shared.mathEnabled = true }
        await engine.searchNow("12*8")
        #expect(engine.results.contains { $0.kind == .calculation } == false)
        await engine.searchNow("Calculator")
        #expect(engine.results.contains { $0.kind == .app && $0.title == "Calculator" })
    }

    @Test func disabledCurrencySkipsConversionRows() async {
        let engine = await makeEngine(apps: [sampleApp(name: "USD EUR", path: "/Applications/USDEUR.app")])
        Preferences.shared.currencyEnabled = false
        defer { Preferences.shared.currencyEnabled = true }
        await engine.searchNow("usd eur")
        #expect(engine.results.contains { $0.kind == .currency } == false)
        #expect(engine.results.contains { $0.kind == .app && $0.title == "USD EUR" })
    }

    @Test func disabledMathStillAllowsCurrency() async {
        let engine = await makeEngine()
        Preferences.shared.mathEnabled = false
        defer { Preferences.shared.mathEnabled = true }
        await engine.searchNow("110 USD to EUR")
        #expect(engine.results.contains { $0.kind == .currency })
        #expect(engine.results.contains { $0.kind == .calculation } == false)
    }
}
