import Foundation

/// Fast launcher fuzzy matcher.
/// Prefers exact → prefix → contiguous substring → word-boundary → tight subsequence.
enum FuzzyMatcher {
    struct Match: Sendable {
        let score: Int
        let matched: Bool
    }

    static func match(query: String, in text: String) -> Match {
        match(
            normalizedQuery: query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            in: text.lowercased(),
            original: text
        )
    }

    static func match(normalizedQuery q: String, in t: String, original: String? = nil) -> Match {
        guard !q.isEmpty else { return Match(score: 0, matched: false) }

        // Exact
        if t == q {
            return Match(score: 100_000, matched: true)
        }

        // Prefix (Calculator for "calc")
        if t.hasPrefix(q) {
            return Match(score: 80_000 + max(0, 200 - t.count), matched: true)
        }

        // Contiguous substring
        if let range = t.range(of: q) {
            let pos = t.distance(from: t.startIndex, to: range.lowerBound)
            var score = 60_000 + max(0, 100 - pos) + max(0, 100 - t.count)
            let original = original ?? t
            let boundaryChars = Array(original)
            if pos == 0 || (pos < boundaryChars.count && isBoundary(boundaryChars, pos)) {
                score += 400
            }
            return Match(score: score, matched: true)
        }

        // Word / camelCase initials: "gc" → Google Chrome, "1p" → 1Password
        if let acronymScore = acronymMatch(query: q, text: original ?? t) {
            return Match(score: acronymScore, matched: true)
        }

        // Tight subsequence only for short queries (avoid "calculator" ~ random noise)
        // Require query length ≤ 4 OR high density match
        if let sub = subsequenceMatch(query: q, text: t) {
            // Reject weak subsequence matches (e.g. sparse letter hits across long names)
            let density = Double(q.count) / Double(max(sub.span, 1))
            if q.count <= 4 || density >= 0.45 {
                return Match(score: sub.score, matched: true)
            }
        }

        return Match(score: 0, matched: false)
    }

    // MARK: - Helpers

    private static func acronymMatch(query: String, text: String) -> Int? {
        let initials = wordInitials(text)
        guard !initials.isEmpty else { return nil }
        if initials.hasPrefix(query) {
            return 50_000 + max(0, 50 - text.count)
        }
        // Also allow query as concatenation of word prefixes: "1pass" → 1Password
        let words = splitWords(text)
        var remaining = query
        for word in words {
            let w = word.lowercased()
            guard !remaining.isEmpty else { break }
            if remaining.hasPrefix(w) {
                remaining.removeFirst(w.count)
            } else if w.hasPrefix(remaining) {
                remaining = ""
            } else {
                // consume matching prefix of this word
                var i = 0
                let rArr = Array(remaining)
                let wArr = Array(w)
                while i < rArr.count, i < wArr.count, rArr[i] == wArr[i] { i += 1 }
                if i == 0 { return nil }
                remaining = String(rArr.dropFirst(i))
            }
        }
        if remaining.isEmpty {
            return 45_000 + max(0, 40 - text.count)
        }
        return nil
    }

    private static func subsequenceMatch(query: String, text: String) -> (score: Int, span: Int)? {
        let q = Array(query)
        let t = Array(text)
        var qi = 0
        var score = 0
        var consecutive = 0
        var first = -1
        var last = -1

        for (ti, ch) in t.enumerated() {
            guard qi < q.count else { break }
            if ch == q[qi] {
                if first < 0 { first = ti }
                if last == ti - 1 {
                    consecutive += 1
                    score += 20 + consecutive * 12
                } else {
                    consecutive = 0
                    score += 8
                    if last >= 0 {
                        score -= min(40, (ti - last - 1) * 3) // gap penalty
                    }
                }
                if ti == 0 || isBoundary(t, ti) {
                    score += 30
                }
                last = ti
                qi += 1
            }
        }

        guard qi == q.count, first >= 0 else { return nil }
        let span = last - first + 1
        score += max(0, 250 - span * 4)
        score += max(0, 80 - text.count)
        // Must not be absurdly sparse
        if span > query.count * 4 { return nil }
        return (max(score, 1), span)
    }

    private static func isBoundary(_ chars: [Character], _ index: Int) -> Bool {
        guard index > 0 else { return true }
        let prev = chars[index - 1]
        if prev == " " || prev == "-" || prev == "_" || prev == "." { return true }
        // camelCase boundary
        if prev.isLowercase && chars[index].isUppercase { return true }
        if prev.isNumber && chars[index].isLetter { return true }
        return false
    }

    private static func splitWords(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            if ch.isLetter || ch.isNumber {
                if !current.isEmpty {
                    let prev = current.last!
                    let camel = prev.isLowercase && ch.isUppercase
                    let numBound = prev.isNumber != ch.isNumber
                    if camel || numBound {
                        words.append(current)
                        current = String(ch)
                        continue
                    }
                }
                current.append(ch)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
            _ = i
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func wordInitials(_ text: String) -> String {
        splitWords(text).compactMap { $0.first.map { String($0).lowercased() } }.joined()
    }
}
