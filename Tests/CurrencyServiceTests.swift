import Testing
import Foundation
@testable import Velox

@Suite("Currency parser")
struct CurrencyParserTests {
    @Test(arguments: [
        ("100 USD to EUR", 100.0, "USD", "EUR"),
        ("50 eur in usd", 50.0, "EUR", "USD"),
        ("100 USD EUR", 100.0, "USD", "EUR"),
        ("usd to eur", 1.0, "USD", "EUR"),
        ("usd eur", 1.0, "USD", "EUR"),
        ("20 GBP into JPY", 20.0, "GBP", "JPY"),
        ("1.5 cad -> usd", 1.5, "CAD", "USD"),
        ("10,5 EUR to USD", 10.5, "EUR", "USD"),
        ("1,000 USD to EUR", 1000.0, "USD", "EUR"),
        ("100 usd → eur", 100.0, "USD", "EUR"),
        ("$20 to €", 20.0, "USD", "EUR"),
        ("20$ to €", 20.0, "USD", "EUR"),
        ("€20 to USD", 20.0, "EUR", "USD"),
        ("£50 in usd", 50.0, "GBP", "USD"),
        ("A$50 to USD", 50.0, "AUD", "USD"),
        ("C$50 to USD", 50.0, "CAD", "USD"),
        ("100usd to eur", 100.0, "USD", "EUR")
    ])
    func parsesStandardQueries(query: String, amount: Double, from: String, to: String) {
        let parsed = CurrencyService.parse(query)
        #expect(parsed?.amount == amount)
        #expect(parsed?.from == from)
        #expect(parsed?.to == to)
    }

    @Test func rejectsNonCurrency() {
        #expect(CurrencyService.parse("Safari") == nil)
        #expect(CurrencyService.parse("12*8+4") == nil)
        #expect(CurrencyService.parse("100 XXX to YYY") == nil)
        #expect(CurrencyService.parse("100 USD to EURO") == nil)
        #expect(CurrencyService.parse("₽100 to usd") == nil)
        #expect(CurrencyService.parse("") == nil)
    }

    @Test func parseAmountThousandsAndDecimals() {
        #expect(CurrencyService.parseAmount("1,000") == 1000)
        #expect(CurrencyService.parseAmount("1,000.50") == 1000.5)
        #expect(CurrencyService.parseAmount("10,5") == 10.5)
        #expect(CurrencyService.parseAmount("1.5") == 1.5)
        #expect(CurrencyService.parseAmount("0.123", decimalIsComma: true) == 0.123)
        #expect(CurrencyService.parseAmount("0.123", decimalIsComma: false) == 0.123)
        #expect(CurrencyService.parseAmount("0,123", decimalIsComma: true) == 0.123)
        #expect(CurrencyService.parseAmount("12.345", decimalIsComma: false) == 12.345)
        #expect(CurrencyService.parseAmount("1.000", decimalIsComma: false) == 1.0)
        #expect(CurrencyService.parseAmount("1.000", decimalIsComma: true) == 1000)
        #expect(CurrencyService.parseAmount("1.234", decimalIsComma: true) == 1234)
        #expect(CurrencyService.parseAmount("1.234.567") == 1_234_567)
        #expect(CurrencyService.parseAmount("1.234,56") == 1234.56)
    }

    @Test func rejectsBareAppShapedQueries() {
        #expect(CurrencyService.parse("php") == nil)
        #expect(CurrencyService.parse("cad") == nil)
        #expect(CurrencyService.parse("100 USD") == nil)
    }
}

@Suite("Currency convert")
struct CurrencyConvertTests {
    @Test func convertsWithFixtureRates() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = CurrencyService(cacheURL: dir.appendingPathComponent("rates.json"))
        await service.replaceRatesForTesting(["USD": 1.1, "GBP": 0.85])
        let result = try #require(await service.convert(query: "110 USD to EUR"))
        #expect(result.copy.contains("100") || result.title.contains("100"))
    }

    @Test func identityDoesNotNeedRates() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = CurrencyService(cacheURL: dir.appendingPathComponent("rates.json"))
        let result = try #require(await service.convert(query: "100 USD to USD"))
        #expect(!result.copy.isEmpty)
        #expect(result.copy != "—")
    }

    @Test func emptyRatesShowsUnavailable() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = CurrencyService(cacheURL: dir.appendingPathComponent("rates.json"))
        let result = try #require(await service.convert(query: "100 USD to GBP"))
        #expect(result.title == "Currency rates unavailable")
        #expect(result.copy == "—")
    }
}

@Suite("Currency refresh")
struct CurrencyRefreshTests {
    @Test func intervalIsOneHour() {
        #expect(Constants.Currency.refreshInterval == 3600)
        #expect(Constants.Currency.attemptThrottle == 30)
    }

    @Test func launchForcesAFetch() {
        #expect(CurrencyRefreshTrigger.launch.forcesFetch)
        #expect(CurrencyRefreshTrigger.hourly.forcesFetch == false)
        #expect(CurrencyRefreshTrigger.panelShow.forcesFetch == false)
    }

    @Test func skipsFreshCacheUnlessForced() {
        let now = Date()
        #expect(
            CurrencyRefreshPolicy.shouldFetch(
                now: now,
                lastFetch: now.addingTimeInterval(-60),
                lastAttempt: now.addingTimeInterval(-60),
                hasRates: true,
                force: false
            ) == false
        )
        #expect(
            CurrencyRefreshPolicy.shouldFetch(
                now: now,
                lastFetch: now.addingTimeInterval(-60),
                lastAttempt: now.addingTimeInterval(-60),
                hasRates: true,
                force: true
            )
        )
    }

    @Test func fetchesWhenTheHourElapsed() {
        let now = Date()
        #expect(
            CurrencyRefreshPolicy.shouldFetch(
                now: now,
                lastFetch: now.addingTimeInterval(-3601),
                lastAttempt: now.addingTimeInterval(-60),
                hasRates: true,
                force: false
            )
        )
    }

    @Test func throttlesFailedAttempts() {
        let now = Date()
        #expect(
            CurrencyRefreshPolicy.shouldFetch(
                now: now,
                lastFetch: .distantPast,
                lastAttempt: now.addingTimeInterval(-10),
                hasRates: false,
                force: false
            ) == false
        )
        #expect(
            CurrencyRefreshPolicy.shouldFetch(
                now: now,
                lastFetch: .distantPast,
                lastAttempt: now.addingTimeInterval(-10),
                hasRates: false,
                force: true
            )
        )
    }
}
