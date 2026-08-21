import Testing
@testable import Velox

@Suite("Status item")
struct StatusItemTests {
    @Test func menuBarIconIsAlwaysSearch() {
        #expect(StatusItemAppearance.symbolName(hovering: false) == Constants.Symbol.search)
        let image = StatusItemAppearance.templateImage()
        #expect(image != nil)
        #expect(image?.isTemplate == true)
    }

    @Test func searchFieldHoverShowsGear() {
        #expect(StatusItemAppearance.symbolName(hovering: true) == Constants.Symbol.settings)
    }

    @Test func symbolsAreDistinct() {
        #expect(StatusItemAppearance.searchSymbol != StatusItemAppearance.settingsSymbol)
    }
}
