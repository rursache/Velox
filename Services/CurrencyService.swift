import Foundation

enum CurrencyRefreshTrigger: Equatable, Sendable {
    case launch
    case hourly
    case panelShow

    var forcesFetch: Bool { self == .launch }
}

enum CurrencyRefreshPolicy {
    static func shouldFetch(
        now: Date = Date(),
        lastFetch: Date,
        lastAttempt: Date,
        hasRates: Bool,
        force: Bool,
        interval: TimeInterval = Constants.Currency.refreshInterval,
        attemptThrottle: TimeInterval = Constants.Currency.attemptThrottle
    ) -> Bool {
        if force { return true }
        if hasRates, now.timeIntervalSince(lastFetch) < interval { return false }
        return now.timeIntervalSince(lastAttempt) >= attemptThrottle
    }
}

actor CurrencyService {
    static let shared = CurrencyService()
    nonisolated let signal = NotificationToken()

    private var rates: [String: Double] = [:] // relative to EUR (Frankfurter base)
    private var base = "EUR"
    private var asOf: String = ""
    private var lastFetch = Date.distantPast
    private var lastAttempt = Date.distantPast

    private let cacheURL: URL

    init(cacheURL: URL? = nil) {
        if let cacheURL {
            self.cacheURL = cacheURL
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent(Constants.App.supportFolderName, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.cacheURL = dir.appendingPathComponent(Constants.Currency.cacheFileName)
        }
    }

    func replaceRatesForTesting(_ rates: [String: Double], base: String = "EUR", asOf: String = "test") {
        self.base = base
        self.rates = rates
        self.rates[base] = 1
        self.asOf = asOf
        lastFetch = Date()
    }

    func prepare() {
        loadCache()
    }

    func refreshIfNeeded(trigger: CurrencyRefreshTrigger) async {
        await refreshIfNeeded(force: trigger.forcesFetch)
    }

    func refreshIfNeeded(force: Bool = false) async {
        loadCache()
        guard CurrencyRefreshPolicy.shouldFetch(
            lastFetch: lastFetch,
            lastAttempt: lastAttempt,
            hasRates: !rates.isEmpty,
            force: force
        ) else { return }
        lastAttempt = Date()
        await fetchRemote()
    }

    func convert(query: String) -> (title: String, subtitle: String, copy: String)? {
        guard let parsed = Self.parse(query) else { return nil }
        return convert(parsed: parsed)
    }

    func convert(parsed: Parsed) -> (title: String, subtitle: String, copy: String)? {
        loadCache()
        return formattedConversion(parsed)
    }

    func convert(parsed: Parsed) async -> (title: String, subtitle: String, copy: String)? {
        loadCache()
        return formattedConversion(parsed)
    }

    private func formattedConversion(_ parsed: Parsed) -> (title: String, subtitle: String, copy: String)? {
        guard let result = convertAmount(parsed.amount, from: parsed.from, to: parsed.to) else {
            return (
                "Currency rates unavailable",
                "Rates refresh when you are online",
                "—"
            )
        }

        let formatted = format(result, currency: parsed.to)
        let title = "\(formatted)"
        let subtitle = "\(format(parsed.amount, currency: parsed.from)) → \(parsed.to)"
            + (asOf.isEmpty ? "" : " · \(asOf)")
        return (title, subtitle, formatted)
    }

    private func convertAmount(_ amount: Double, from: String, to: String) -> Double? {
        let f = from.uppercased()
        let t = to.uppercased()
        if f == t { return amount }

        // Rates stored as: 1 EUR = rates[CODE]
        let fromRate: Double
        let toRate: Double
        if f == base {
            fromRate = 1
        } else if let r = rates[f] {
            fromRate = r
        } else {
            return nil
        }
        if t == base {
            toRate = 1
        } else if let r = rates[t] {
            toRate = r
        } else {
            return nil
        }

        // amount in EUR = amount / fromRate; then * toRate
        let inBase = amount / fromRate
        return inBase * toRate
    }

    private func format(_ value: Double, currency: String) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = currency
        nf.maximumFractionDigits = 4
        nf.minimumFractionDigits = 2
        if let s = nf.string(from: NSNumber(value: value)) {
            return s
        }
        return String(format: "%.4f %@", value, currency)
    }

    private func fetchRemote() async {
        // Frankfurter: latest rates base EUR
        let urls = [
            URL(string: Constants.Currency.primaryAPI)!,
            URL(string: Constants.Currency.fallbackAPI)!
        ]
        for url in urls {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    continue
                }
                if let parsed = try? JSONDecoder().decode(FrankfurterResponse.self, from: data) {
                    base = parsed.base
                    rates = parsed.rates
                    rates[parsed.base] = 1
                    asOf = parsed.date
                    lastFetch = Date()
                    saveCache(data: data)
                    print("[Velox] Currency rates updated (\(parsed.date)), \(parsed.rates.count) currencies")
                    await MainActor.run {
                        NotificationCenter.default.post(name: .veloxRatesDidChange, object: signal)
                    }
                    return
                }
            } catch {
                continue
            }
        }
        print("[Velox] Currency fetch failed; using cache if any")
    }

    private func loadCache() {
        guard rates.isEmpty else { return }
        guard let data = try? Data(contentsOf: cacheURL),
              let parsed = try? JSONDecoder().decode(FrankfurterResponse.self, from: data) else {
            return
        }
        base = parsed.base
        rates = parsed.rates
        rates[parsed.base] = 1
        asOf = parsed.date
        lastFetch = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))
            .flatMap(\.contentModificationDate) ?? .distantPast
    }

    private func saveCache(data: Data) {
        try? data.write(to: cacheURL, options: .atomic)
    }

    // MARK: - Parsing

    struct Parsed {
        let amount: Double
        let from: String
        let to: String
    }

    private static let symbols: [String: String] = [
        "A$": "AUD", "C$": "CAD",
        "$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY",
        "₩": "KRW", "₹": "INR", "₺": "TRY"
    ]

    private static let codeSet: Set<String> = [
        "USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "NZD", "CNY", "HKD", "SGD",
        "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "RON", "BGN", "TRY", "INR", "KRW",
        "BRL", "MXN", "ZAR", "ILS", "THB", "IDR", "PHP", "MYR", "ISK"
    ]

    private static let connector = #"(?:to|in|into|->|→)"#
    // Optional k / m / b shorthand: $21k, 1.5m usd. Backtracking keeps "100mxn" as 100 MXN
    private static let amountToken = #"(\d+(?:[.,]\d+)*[kKmMbB]?)"#
    private static let codeToken = #"([A-Za-z]{3})"#

    static func parse(_ query: String) -> Parsed? {
        var q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }

        for (sym, code) in symbols.sorted(by: { $0.key.count > $1.key.count }) {
            q = q.replacingOccurrences(of: sym, with: " \(code) ")
        }
        q = q.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let patterns: [(String, (String, NSTextCheckingResult) -> Parsed?)] = [
            (#"(?i)^\#(amountToken)\s*\#(codeToken)\s+\#(connector)\s+\#(codeToken)$"#, { q, m in
                parsed(q, m, amount: 1, from: 2, to: 3)
            }),
            (#"(?i)^\#(codeToken)\s*\#(amountToken)\s+\#(connector)\s+\#(codeToken)$"#, { q, m in
                parsed(q, m, amount: 2, from: 1, to: 3)
            }),
            (#"(?i)^\#(codeToken)\s+\#(connector)\s+\#(codeToken)$"#, { q, m in
                parsed(q, m, amount: nil, from: 1, to: 2)
            }),
            (#"(?i)^\#(amountToken)\s+\#(codeToken)\s+\#(codeToken)$"#, { q, m in
                parsed(q, m, amount: 1, from: 2, to: 3)
            }),
            (#"(?i)^\#(codeToken)\s+\#(codeToken)$"#, { q, m in
                parsed(q, m, amount: nil, from: 1, to: 2)
            })
        ]

        let range = NSRange(q.startIndex..., in: q)
        for (pattern, builder) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: q, range: range),
                  let parsed = builder(q, match) else { continue }
            return parsed
        }
        return nil
    }

    private static func parsed(
        _ q: String,
        _ match: NSTextCheckingResult,
        amount: Int?,
        from: Int,
        to: Int
    ) -> Parsed? {
        let value: Double
        if let amount {
            guard let ar = Range(match.range(at: amount), in: q),
                  let parsedAmount = parseAmount(String(q[ar])) else { return nil }
            value = parsedAmount
        } else {
            value = 1
        }
        guard let fr = Range(match.range(at: from), in: q),
              let tr = Range(match.range(at: to), in: q) else { return nil }
        let fromCode = String(q[fr]).uppercased()
        let toCode = String(q[tr]).uppercased()
        guard codeSet.contains(fromCode), codeSet.contains(toCode) else { return nil }
        return Parsed(amount: value, from: fromCode, to: toCode)
    }

    static func parseAmount(_ raw: String, locale: Locale = .current) -> Double? {
        parseAmount(raw, decimalIsComma: usesCommaDecimal(locale))
    }

    static func parseAmount(_ raw: String, decimalIsComma: Bool) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        var multiplier: Double = 1
        if let last = s.last, let scale = shorthandMultiplier(last) {
            multiplier = scale
            s.removeLast()
        }
        return parseNumber(s, decimalIsComma: decimalIsComma).map { $0 * multiplier }
    }

    static func shorthandMultiplier(_ suffix: Character) -> Double? {
        switch suffix.lowercased() {
        case "k": return 1_000
        case "m": return 1_000_000
        case "b": return 1_000_000_000
        default: return nil
        }
    }

    private static func parseNumber(_ s: String, decimalIsComma: Bool) -> Double? {
        if s.range(of: #"^[1-9]\d{0,2}(,\d{3})+(\.\d+)?$"#, options: .regularExpression) != nil {
            return Double(s.replacingOccurrences(of: ",", with: ""))
        }
        if s.range(of: #"^\d{1,3}(\.\d{3}){2,}$"#, options: .regularExpression) != nil
            || s.range(of: #"^\d{1,3}(\.\d{3})+,\d+$"#, options: .regularExpression) != nil {
            return Double(
                s.replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: ".")
            )
        }
        if decimalIsComma,
           s.range(of: #"^[1-9]\d{0,2}(\.\d{3})+$"#, options: .regularExpression) != nil {
            return Double(s.replacingOccurrences(of: ".", with: ""))
        }
        if decimalIsComma,
           s.range(of: #"^\d+,\d+$"#, options: .regularExpression) != nil {
            return Double(s.replacingOccurrences(of: ",", with: "."))
        }
        if s.range(of: #"^\d+,\d{1,2}$"#, options: .regularExpression) != nil {
            return Double(s.replacingOccurrences(of: ",", with: "."))
        }
        return Double(s)
    }

    static func usesCommaDecimal(_ locale: Locale) -> Bool {
        if let sep = locale.decimalSeparator, !sep.isEmpty {
            return sep == ","
        }
        let id = locale.identifier.lowercased()
        return id.hasPrefix("de") || id.hasPrefix("fr") || id.hasPrefix("ro")
            || id.hasPrefix("it") || id.hasPrefix("nl")
            || id.hasPrefix("pl")
    }
}

private struct FrankfurterResponse: Codable {
    let amount: Double?
    let base: String
    let date: String
    let rates: [String: Double]
}
