import Foundation

enum MathEngine {
    private static let functions: Set<String> = [
        "sqrt", "abs", "ceil", "floor", "sin", "cos", "tan"
    ]

    static func evaluate(_ query: String) -> (display: String, raw: String)? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var expr = normalizeNumberSeparators(normalizeOperators(trimmed))
        if isBarePercentage(expr) { return nil }
        var resultIsPercent = false
        if let phrase = rewritePercentQuestion(expr) {
            expr = phrase.expression
            resultIsPercent = phrase.resultIsPercent
        }
        expr = rewritePercent(expr)
        guard looksLikeMath(expr) else { return nil }
        if expr.range(of: #"^[\d\.]+$"#, options: .regularExpression) != nil {
            return nil
        }

        if let value = evaluateExpression(expr), !value.isNaN {
            let display = format(value)
            return resultIsPercent ? (display + "%", display) : (display, display)
        }
        return nil
    }

    private static let percentWord = #"(?:%|percent|pct)"#

    /// `10%` on its own is not a calculation
    private static func isBarePercentage(_ input: String) -> Bool {
        input.range(
            of: #"(?i)^\d+(?:\.\d+)?\s*\#(percentWord)$"#,
            options: .regularExpression
        ) != nil
    }

    /// `40 is 45% of` asks for the whole, `40 is what % of 80` asks for the share
    private static func rewritePercentQuestion(_ input: String) -> (expression: String, resultIsPercent: Bool)? {
        var s = input
        s = replaceAll(in: s, pattern: #"(?i)^what\s+is\s+"#, template: "")
        if let m = captures(#"(?i)^(.+?)\s+is\s+(\d+(?:\.\d+)?)\s*\#(percentWord)\s+of(?:\s+what)?\s*\??$"#, in: s) {
            return ("(\(m[0]))/((\(m[1]))*0.01)", false)
        }
        if let m = captures(#"(?i)^(.+?)\s+is\s+what\s+\#(percentWord)\s+of\s+(.+?)\s*\??$"#, in: s) {
            return ("(\(m[0]))/(\(m[1]))*100", true)
        }
        s = replaceAll(in: s, pattern: #"(?i)\s+is(?:\s+what)?\s*\??$"#, template: "")
        return s == input ? nil : (s, false)
    }

    private static func captures(_ pattern: String, in input: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else {
            return nil
        }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: input).map { String(input[$0]) } ?? ""
        }
    }

    private static func normalizeOperators(_ input: String) -> String {
        input
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
    }

    /// `1,000 + 1` drops the thousands separators, `1,5*2` treats a short comma group as a decimal
    private static func normalizeNumberSeparators(_ input: String) -> String {
        guard input.contains(",") else { return input }
        var s = replaceAll(in: input, pattern: #"(\d),(?=\d{3}(?!\d))"#, template: "$1")
        s = replaceAll(in: s, pattern: #"(\d),(?=\d)"#, template: "$1.")
        return s
    }

    private static func looksLikeMath(_ trimmed: String) -> Bool {
        let mathPattern = #"^[\d\s\.\+\-\*/%\^\(\)\,]+$"#
        if trimmed.range(of: mathPattern, options: .regularExpression) != nil {
            return trimmed.range(of: #"[\+\-\*/%\^\(]"#, options: .regularExpression) != nil
        }
        let fnPattern = #"^(?i)[\d\s\.\+\-\*/%\^\(\)\,sqrtabsceilfloorsincostanpiekmb]+$"#
        guard trimmed.range(of: fnPattern, options: .regularExpression) != nil else {
            return false
        }
        let lowered = trimmed.lowercased()
        return trimmed.range(of: #"[\+\-\*/%\^\(]"#, options: .regularExpression) != nil
            || functions.contains(where: { lowered.contains($0) })
            || lowered.contains("pi")
    }

    /// `1% of 75000` and `1 percent of 75000` become `(1*0.01)*75000`
    private static func rewritePercent(_ input: String) -> String {
        var s = replaceAll(
            in: input,
            pattern: #"(?i)((?:\d+(?:\.\d+)?)|\([^()]+\))\s*(?:%|percent|pct)\s*of(?![a-zA-Z])\s*"#,
            template: "($1*0.01)*"
        )
        if let range = s.range(
            of: #"(?i)([+-])\s*(\d+(?:\.\d+)?)\s*(?:%|percent|pct)\s*$"#,
            options: .regularExpression
        ) {
            let token = String(s[range])
            guard let opRange = token.rangeOfCharacter(from: CharacterSet(charactersIn: "+-")) else {
                return s
            }
            let num = token.filter { $0.isNumber || $0 == "." }
            let sign = token[opRange] == "+" ? "+" : "-"
            let left = String(s[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !left.isEmpty {
                s = "(\(left))*(1\(sign)\(num)*0.01)"
            }
        }
        while let range = s.range(of: #"(\d+(?:\.\d+)?)%(?!\d)"#, options: .regularExpression) {
            let token = String(s[range])
            let num = token.dropLast()
            s.replaceSubrange(range, with: "(\(num)*0.01)")
        }
        while let range = s.range(of: #"(?i)(\d+(?:\.\d+)?)\s*(?:percent|pct)\b"#, options: .regularExpression) {
            let token = String(s[range])
            let num = token.filter { $0.isNumber || $0 == "." }
            s.replaceSubrange(range, with: "(\(num)*0.01)")
        }
        return s.replacingOccurrences(of: "^", with: "**")
    }

    private static func replaceAll(in input: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: template)
    }

    private static func format(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if !value.isFinite { return value < 0 ? "-∞" : "∞" }
        if abs(value) < 1e-10 { return "0" }
        if value.rounded() == value, abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        var s = String(format: "%.10g", value)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    private static func evaluateExpression(_ input: String) -> Double? {
        let tokens = tokenize(input)
        guard !tokens.isEmpty else { return nil }
        guard let rpn = toRPN(tokens) else { return nil }
        return evalRPN(rpn)
    }

    private enum Token {
        case number(Double)
        case op(Character)
        case fn(String)
        case lparen
        case rparen
    }

    private static func insertImplicitMultiply(_ tokens: inout [Token]) {
        guard let last = tokens.last else { return }
        switch last {
        case .number, .rparen:
            tokens.append(.op("*"))
        default:
            break
        }
    }

    private static func tokenize(_ input: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(input.replacingOccurrences(of: " ", with: ""))
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isNumber || c == "." {
                var j = i
                while j < chars.count && (chars[j].isNumber || chars[j] == ".") {
                    j += 1
                }
                let numStr = String(chars[i..<j])
                // 21k, 1.5m, 2b: a lone scale letter right after the number
                var scale: Double = 1
                if j < chars.count, let factor = CurrencyService.shorthandMultiplier(chars[j]),
                   j + 1 == chars.count || !chars[j + 1].isLetter {
                    scale = factor
                    j += 1
                }
                if let v = Double(numStr) {
                    insertImplicitMultiply(&tokens)
                    tokens.append(.number(v * scale))
                }
                i = j
                continue
            }
            if c.isLetter {
                var j = i
                while j < chars.count && chars[j].isLetter {
                    j += 1
                }
                let name = String(chars[i..<j]).lowercased()
                if name == "pi" {
                    insertImplicitMultiply(&tokens)
                    tokens.append(.number(.pi))
                } else if functions.contains(name) {
                    insertImplicitMultiply(&tokens)
                    tokens.append(.fn(name))
                } else {
                    return []
                }
                i = j
                continue
            }
            if c == "-" {
                let prev = tokens.last
                let unary: Bool
                switch prev {
                case .none, .op, .lparen, .fn: unary = true
                default: unary = false
                }
                if unary {
                    tokens.append(.op("~"))
                    i += 1
                    continue
                }
            }
            if c == "*" && i + 1 < chars.count && chars[i + 1] == "*" {
                tokens.append(.op("^"))
                i += 2
                continue
            }
            switch c {
            case "+", "-", "*", "/", "^", "%":
                tokens.append(.op(c))
            case "(":
                insertImplicitMultiply(&tokens)
                tokens.append(.lparen)
            case ")":
                tokens.append(.rparen)
            default:
                return []
            }
            i += 1
        }
        return tokens
    }

    private static func precedence(_ op: Character) -> Int {
        switch op {
        case "+", "-": return 1
        case "*", "/", "%": return 2
        case "^": return 3
        case "~": return 3
        default: return 0
        }
    }

    private static func toRPN(_ tokens: [Token]) -> [Token]? {
        var output: [Token] = []
        var stack: [Token] = []
        for token in tokens {
            switch token {
            case .number:
                output.append(token)
            case .fn:
                stack.append(token)
            case .op(let op):
                while let last = stack.last, case .op(let top) = last {
                    let rightAssoc = op == "^" || op == "~"
                    if (!rightAssoc && precedence(top) >= precedence(op))
                        || (rightAssoc && precedence(top) > precedence(op)) {
                        output.append(stack.removeLast())
                    } else {
                        break
                    }
                }
                stack.append(token)
            case .lparen:
                stack.append(token)
            case .rparen:
                var found = false
                while let last = stack.last {
                    if case .lparen = last {
                        stack.removeLast()
                        found = true
                        break
                    }
                    output.append(stack.removeLast())
                }
                if !found { return nil }
                if let last = stack.last, case .fn = last {
                    output.append(stack.removeLast())
                }
            }
        }
        while let last = stack.last {
            if case .lparen = last { return nil }
            if case .rparen = last { return nil }
            output.append(stack.removeLast())
        }
        return output
    }

    private static func evalRPN(_ tokens: [Token]) -> Double? {
        var stack: [Double] = []
        for token in tokens {
            switch token {
            case .number(let n):
                stack.append(n)
            case .fn(let name):
                guard let a = stack.popLast() else { return nil }
                let r: Double
                switch name {
                case "sqrt": r = sqrt(a)
                case "abs": r = abs(a)
                case "ceil": r = ceil(a)
                case "floor": r = floor(a)
                case "sin": r = sin(a * .pi / 180)
                case "cos": r = cos(a * .pi / 180)
                case "tan": r = tan(a * .pi / 180)
                default: return nil
                }
                stack.append(r)
            case .op(let op):
                if op == "~" {
                    guard let a = stack.popLast() else { return nil }
                    stack.append(-a)
                    continue
                }
                guard stack.count >= 2 else { return nil }
                let b = stack.removeLast()
                let a = stack.removeLast()
                let r: Double
                switch op {
                case "+": r = a + b
                case "-": r = a - b
                case "*": r = a * b
                case "/": r = a / b
                case "%": r = a.truncatingRemainder(dividingBy: b)
                case "^": r = pow(a, b)
                default: return nil
                }
                stack.append(r)
            default:
                return nil
            }
        }
        return stack.count == 1 ? stack[0] : nil
    }
}
