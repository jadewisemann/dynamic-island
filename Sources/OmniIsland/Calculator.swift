import Foundation

/// Evaluates simple arithmetic typed into the launcher: + − × ÷ ^ %,
/// parentheses, decimals and 0x hex numbers. A small recursive-descent
/// parser, because NSExpression raises Objective-C exceptions on bad input.
enum Calculator {
    /// The value of `text`, or nil when it is not arithmetic (a lone
    /// number is not worth a row).
    static func evaluate(_ text: String) -> Double? {
        let source = text.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .lowercased()
        guard source.contains(where: \.isNumber) else { return nil }
        var parser = Parser(Array(source.filter { !$0.isWhitespace }))
        guard let value = parser.expression(), parser.atEnd, parser.sawOperator, value.isFinite else { return nil }
        return value
    }

    static func format(_ value: Double) -> String {
        if value.rounded() == value && abs(value) < 1e15 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            return f.string(from: NSNumber(value: value)) ?? String(Int(value))
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumSignificantDigits = 12
        f.usesSignificantDigits = true
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Plain digits for the clipboard.
    static func plain(_ value: Double) -> String {
        if value.rounded() == value && abs(value) < 1e15 { return String(Int64(value)) }
        var text = String(format: "%.12g", value)
        if text.contains("e") { return text }
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) { text.removeLast() }
        return text
    }

    private struct Parser {
        let chars: [Character]
        var i = 0
        var sawOperator = false

        init(_ chars: [Character]) { self.chars = chars }

        var atEnd: Bool { i == chars.count }
        private var peek: Character? { i < chars.count ? chars[i] : nil }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while let op = peek, op == "+" || op == "-" {
                i += 1
                sawOperator = true
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func term() -> Double? {
            guard var value = power() else { return nil }
            while let op = peek, op == "*" || op == "/" || op == "%" {
                i += 1
                sawOperator = true
                guard let rhs = power() else { return nil }
                switch op {
                case "*": value *= rhs
                case "/": value /= rhs
                default: value = value.truncatingRemainder(dividingBy: rhs)
                }
            }
            return value
        }

        mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if peek == "^" {
                i += 1
                sawOperator = true
                guard let exponent = power() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        mutating func unary() -> Double? {
            if peek == "-" {
                i += 1
                return unary().map { -$0 }
            }
            if peek == "+" {
                i += 1
                return unary()
            }
            return primary()
        }

        mutating func primary() -> Double? {
            if peek == "(" {
                i += 1
                sawOperator = true
                guard let value = expression(), peek == ")" else { return nil }
                i += 1
                return value
            }
            return number()
        }

        mutating func number() -> Double? {
            if peek == "0", i + 1 < chars.count, chars[i + 1] == "x" {
                var j = i + 2
                var digits = ""
                while j < chars.count, chars[j].isHexDigit { digits.append(chars[j]); j += 1 }
                guard !digits.isEmpty, let value = UInt64(digits, radix: 16) else { return nil }
                i = j
                sawOperator = true // "0xC00" alone is worth converting
                return Double(value)
            }
            var text = ""
            while let c = peek, c.isNumber || c == "." {
                text.append(c)
                i += 1
            }
            return Double(text)
        }
    }
}
