import Testing
import AppKit
import Foundation
@testable import Velox

@MainActor
@Suite("Search panel surface")
struct SearchPanelSurfaceTests {
    @Test func replicaAppliesChromeWithoutStealingFocus() async {
        let index = AppIndex()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fx = CurrencyService(cacheURL: dir.appendingPathComponent("rates.json"))
        let engine = SearchEngine(appIndex: index, currencyService: fx)
        let surface = SearchPanelSurface(
            engine: engine,
            theme: ThemeCatalog.glass,
            cornerRadius: 20,
            acceptsFocus: false
        )
        #expect(surface.container.appliedMaterial == ThemeCatalog.glass.material)
        #expect(surface.container.appliedCornerRadius == 20)
        surface.applyChrome(
            theme: ThemeCatalog.snow,
            highlight: HighlightCatalog.style(for: .soft),
            cornerRadius: 24,
            acceptsFocus: false
        )
        #expect(surface.container.appliedMaterial == ThemeCatalog.snow.material)
        #expect(surface.container.appliedWash == ThemeCatalog.snow.wash)
        #expect(surface.container.appliedCornerRadius == 24)
        surface.close()
    }
}
