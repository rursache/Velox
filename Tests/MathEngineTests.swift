import Testing
@testable import Velox

@Suite("Math engine")
struct MathEngineTests {
    @Test(arguments: [
        ("2+2", "4"),
        ("12*8+4", "100"),
        ("2^10", "1024"),
        ("(1+2)*3", "9"),
        ("10/4", "2.5"),
        ("-3+5", "2"),
        ("2**8", "256"),
        ("10 % 3", "1"),
        ("10%3", "1"),
        ("2^3^2", "512"),
        ("-(1+2)", "-3"),
        ("2^-2", "0.25"),
        ("2*pi", "6.283185307"),
        ("2(3+4)", "14"),
        ("sqrt(16)", "4"),
        ("abs(-3)", "3"),
        ("ceil(1.2)", "2"),
        ("floor(1.8)", "1"),
        ("sin(0)", "0"),
        ("sin(30)", "0.5"),
        ("cos(0)", "1"),
        ("cos(180)", "-1"),
        ("tan(0)", "0"),
        ("tan(45)", "1"),
        ("100+20%", "120"),
        ("100-20%", "80"),
        ("100/2+20%", "60"),
        ("100-50+20%", "60"),
        ("1% of 75000", "750"),
        ("15% of 200", "30"),
        ("2.5% of 1000", "25"),
        ("1 % of 75000", "750"),
        ("1%of75000", "750"),
        ("1% OF 75000", "750"),
        ("50 + 1% of 75000", "800"),
        ("1% of (100+50)", "1.5"),
        ("1% of -75000", "-750"),
        ("0% of 100", "0"),
        ("100% of 50", "50"),
        ("(2+3)% of 100", "5"),
        ("1 percent of 75000", "750"),
        ("1 pct of 75000", "750"),
        ("100 + 20 percent", "120"),
        ("100 - 20 percent", "80"),
        ("12 * 8", "96"),
        ("2×3", "6"),
        ("8÷2", "4"),
        ("5−3", "2"),
        ("-2^2", "-4"),
        ("-2^2^2", "-16"),
        ("21k*2", "42000"),
        ("1.5m + 500k", "2000000"),
        ("2b/1000", "2000000"),
        ("21K + 1", "21001"),
        ("40 is 45% of", "88.88888889"),
        ("40 is 45% of what", "88.88888889"),
        ("40 is 45% of what?", "88.88888889"),
        ("40 is 45 percent of", "88.88888889"),
        ("40 is 50% of", "80"),
        ("40 is what % of 80", "50%"),
        ("40 is what percent of 80", "50%"),
        ("30 is what % of 40?", "75%"),
        ("what is 45% of 40", "18"),
        ("45% of 40 is", "18"),
        ("45% of 40 is what?", "18"),
        ("10% of 20k", "2000"),
        ("1,000 + 1", "1001"),
        ("5,000 * 2", "10000"),
        ("1,234,567 - 567", "1234000"),
        ("1,5 * 2", "3"),
        ("10,25 + 0,75", "11"),
        ("1,000.5 + 0.5", "1001")
    ])
    func evaluatesExpressions(query: String, expected: String) {
        let result = MathEngine.evaluate(query)
        #expect(result?.display == expected)
    }

    @Test func implicitPiAndSpacedFunction() {
        #expect(MathEngine.evaluate("2pi")?.display == MathEngine.evaluate("2*pi")?.display)
        #expect(MathEngine.evaluate("2sin30")?.display == "1")
        #expect(MathEngine.evaluate("2 sin 30")?.display == "1")
    }

    @Test func piConstant() {
        let result = MathEngine.evaluate("pi")
        #expect(result != nil)
        #expect(result?.display.hasPrefix("3.14") == true)
    }

    @Test func plainNumberIsIgnored() {
        #expect(MathEngine.evaluate("42") == nil)
        #expect(MathEngine.evaluate("3.14") == nil)
    }

    @Test func nonMathIsIgnored() {
        #expect(MathEngine.evaluate("Safari") == nil)
        #expect(MathEngine.evaluate("100 usd to eur") == nil)
        #expect(MathEngine.evaluate("") == nil)
        #expect(MathEngine.evaluate("(1+2") == nil)
        #expect(MathEngine.evaluate("2+") == nil)
    }

    @Test func divideByZeroIsInfinity() {
        #expect(MathEngine.evaluate("1/0")?.display == "∞")
    }

    @Test func nearZeroTrigFormatsAsZero() {
        #expect(MathEngine.evaluate("cos(90)")?.display == "0")
        #expect(MathEngine.evaluate("sin(180)")?.display == "0")
    }

    @Test func nanIsNotAResult() {
        #expect(MathEngine.evaluate("0/0") == nil)
        #expect(MathEngine.evaluate("sqrt(-1)") == nil)
    }

    @Test func barePercentageIsNotACalculation() {
        #expect(MathEngine.evaluate("10%") == nil)
        #expect(MathEngine.evaluate("20 percent") == nil)
        #expect(MathEngine.evaluate("2.5 pct") == nil)
        #expect(MathEngine.evaluate("100+20%")?.display == "120")
    }

    @Test func scaleSuffixNeedsAnOperator() {
        #expect(MathEngine.evaluate("21k") == nil)
        #expect(MathEngine.evaluate("2m") == nil)
        #expect(MathEngine.evaluate("21kg*2") == nil)
    }

    @Test func percentQuestionCopiesTheNumberOnly() {
        let result = MathEngine.evaluate("40 is what % of 80")
        #expect(result?.display == "50%")
        #expect(result?.raw == "50")
    }

    @Test func strayCommasAreNotMath() {
        #expect(MathEngine.evaluate("1,,000 + 1") == nil)
        #expect(MathEngine.evaluate("1, + 2") == nil)
        #expect(MathEngine.evaluate("1,000") == nil)
    }

    @Test func percentOfDoesNotMatchDiscountOff() {
        #expect(MathEngine.evaluate("10% off 50") == nil)
    }
}
