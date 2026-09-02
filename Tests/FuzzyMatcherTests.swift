import Testing
@testable import Velox

@Suite("Fuzzy matcher")
struct FuzzyMatcherTests {
    @Test(arguments: [
        ("Safari", "Safari"),
        ("calculator", "Calculator"),
        ("notes", "Notes")
    ])
    func exactMatchOutranksEverything(query: String, name: String) {
        let exact = FuzzyMatcher.match(query: query, in: name)
        let prefix = FuzzyMatcher.match(query: String(query.prefix(3)), in: name)
        #expect(exact.matched)
        #expect(exact.score > prefix.score)
    }

    @Test(arguments: [
        ("calc", "Calculator"),
        ("saf", "Safari"),
        ("xco", "Xcode")
    ])
    func prefixMatch(query: String, name: String) {
        let match = FuzzyMatcher.match(query: query, in: name)
        #expect(match.matched)
        #expect(match.score >= 80_000)
    }

    @Test func acronymGoogleChrome() {
        let match = FuzzyMatcher.match(query: "gc", in: "Google Chrome")
        #expect(match.matched)
        #expect(match.score >= 45_000)
    }

    @Test(arguments: [
        ("vs code", "Visual Studio Code"),
        ("v s c", "Visual Studio Code"),
        ("goo ch", "Google Chrome"),
        ("sys set", "System Settings")
    ])
    func spacedAbbreviationsMatchLikeInitials(query: String, name: String) {
        let spaced = FuzzyMatcher.match(query: query, in: name)
        let joined = FuzzyMatcher.match(query: query.replacingOccurrences(of: " ", with: ""), in: name)
        #expect(spaced.matched)
        #expect(spaced.score >= 45_000)
        #expect(spaced.score == joined.score)
    }

    @Test func spacedWordPrefixStillMatches() {
        let match = FuzzyMatcher.match(query: "1 pass", in: "1Password")
        #expect(match.matched)
        #expect(match.score >= 45_000)
    }

    @Test func spacedAbbreviationDoesNotInventMatches() {
        #expect(!FuzzyMatcher.match(query: "vs cade", in: "Visual Studio Code").matched)
        #expect(!FuzzyMatcher.match(query: "x y", in: "Safari").matched)
    }

    @Test func wordPrefixOnePassword() {
        let match = FuzzyMatcher.match(query: "1p", in: "1Password")
        #expect(match.matched)
    }

    @Test func acronymUsesOriginalCamelCase() {
        let match = FuzzyMatcher.match(
            normalizedQuery: "gc",
            in: "google chrome",
            original: "Google Chrome"
        )
        #expect(match.matched)
        #expect(match.score >= 45_000)
    }

    @Test func wordStartSubstringBeatsMidToken() {
        let word = FuzzyMatcher.match(query: "store", in: "App Store")
        let mid = FuzzyMatcher.match(query: "store", in: "Restore")
        #expect(word.score > mid.score)
    }

    @Test func contiguousSubstring() {
        let match = FuzzyMatcher.match(query: "note", in: "Apple Notes")
        #expect(match.matched)
        #expect(match.score >= 60_000)
    }

    @Test func shorterNameWinsWhenScoresTie() {
        let safari = FuzzyMatcher.match(query: "saf", in: "Safari")
        let preview = FuzzyMatcher.match(query: "saf", in: "Safari Technology Preview")
        #expect(safari.matched && preview.matched)
        #expect(safari.score > preview.score)
    }

    @Test func emptyQueryIsNotAHit() {
        let match = FuzzyMatcher.match(query: "", in: "Safari")
        #expect(match.score == 0)
        #expect(!match.matched)
    }

    @Test func wordPrefixOnePasswordLong() {
        let match = FuzzyMatcher.match(query: "1pass", in: "1Password")
        #expect(match.matched)
    }

    @Test func shortSubsequenceSafari() {
        let match = FuzzyMatcher.match(query: "sf", in: "Safari")
        #expect(match.matched)
    }

    @Test func sparseSubsequenceRejected() {
        let match = FuzzyMatcher.match(query: "aeiou", in: "Calendar Helper Extra Long Name")
        #expect(!match.matched)
    }

    @Test func queryLongerThanNameDoesNotMatch() {
        let match = FuzzyMatcher.match(query: "safaritechnology", in: "Safari")
        #expect(!match.matched)
    }

    @Test func unrelatedNameDoesNotMatch() {
        let match = FuzzyMatcher.match(query: "zzzz", in: "Safari")
        #expect(!match.matched)
        #expect(match.score == 0)
    }
}
