import Foundation

public enum CalculatorError: Error, Equatable, Sendable {
    case invalidExpression
    case divisionByZero
}

/// Whitelisted arithmetic evaluator implemented as a recursive-descent parser.
///
/// Grammar (whitespace is ignored between tokens):
///
///     expression := term (('+' | '-') term)*
///     term       := unary (('*' | '/' | '%') unary)*
///     unary      := ('+' | '-') unary | power
///     power      := primary ('^' unary)?          // right-associative
///     primary    := number | constant | function '(' expression ')' | '(' expression ')'
///
/// Unary minus binds looser than `^` (`-2^2 == -4`) and the exponent may carry
/// its own sign (`2^-1 == 0.5`). Functions and constants are tokens, never text
/// substitutions, so results in exponent notation and nested calls are exact.
/// Input length and nesting depth are bounded so pasted input cannot exhaust
/// the stack. The Windows port in `Core/ExpressionCalculator.cs` mirrors this
/// grammar and must stay behaviourally identical.
public struct ExpressionCalculator: Sendable {
    public static let maximumLength = 512
    public static let maximumDepth = 64

    public init() {}

    public func evaluate(_ expression: String) throws -> Double {
        let normalized = expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "**", with: "^")
        guard normalized.unicodeScalars.count <= Self.maximumLength else {
            throw CalculatorError.invalidExpression
        }
        var parser = Parser(scalars: Array(normalized.unicodeScalars))
        return try parser.parse()
    }

    /// Integers that are exactly representable (|x| < 2^53) print without a
    /// fractional part; everything else uses 12 significant digits.
    public func format(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value.rounded() == value, abs(value) < 9_007_199_254_740_992 {
            return String(Int64(value))
        }
        return String(format: "%.12g", value)
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        var index = 0
        var depth = 0

        init(scalars: [Unicode.Scalar]) {
            self.scalars = scalars
        }

        mutating func parse() throws -> Double {
            let value = try parseExpression()
            skipWhitespace()
            guard index == scalars.count else { throw CalculatorError.invalidExpression }
            return value
        }

        private mutating func enter() throws {
            depth += 1
            if depth > ExpressionCalculator.maximumDepth { throw CalculatorError.invalidExpression }
        }

        private mutating func parseExpression() throws -> Double {
            try enter()
            defer { depth -= 1 }
            var value = try parseTerm()
            while true {
                if consume("+") {
                    let right = try parseTerm()
                    value = try checked(value + right)
                } else if consume("-") {
                    let right = try parseTerm()
                    value = try checked(value - right)
                } else {
                    return value
                }
            }
        }

        private mutating func parseTerm() throws -> Double {
            var value = try parseUnary()
            while true {
                if consume("*") {
                    let right = try parseUnary()
                    value = try checked(value * right)
                } else if consume("/") {
                    let right = try parseUnary()
                    guard right != 0 else { throw CalculatorError.divisionByZero }
                    value = try checked(value / right)
                } else if consume("%") {
                    let right = try parseUnary()
                    guard right != 0 else { throw CalculatorError.divisionByZero }
                    value = try checked(value.truncatingRemainder(dividingBy: right))
                } else {
                    return value
                }
            }
        }

        private mutating func parseUnary() throws -> Double {
            if consume("-") {
                try enter()
                defer { depth -= 1 }
                let operand = try parseUnary()
                return -operand
            }
            if consume("+") {
                try enter()
                defer { depth -= 1 }
                return try parseUnary()
            }
            return try parsePower()
        }

        private mutating func parsePower() throws -> Double {
            let base = try parsePrimary()
            guard consume("^") else { return base }
            let exponent = try parseUnary()
            return try checked(pow(base, exponent))
        }

        private mutating func parsePrimary() throws -> Double {
            skipWhitespace()
            guard index < scalars.count else { throw CalculatorError.invalidExpression }
            let scalar = scalars[index]
            if scalar == "(" {
                index += 1
                let value = try parseExpression()
                guard consume(")") else { throw CalculatorError.invalidExpression }
                return value
            }
            if Self.isDigit(scalar) || scalar == "." {
                return try parseNumber()
            }
            if Self.isLetter(scalar) {
                let name = parseIdentifier()
                if let constant = Self.constant(named: name) { return constant }
                guard consume("(") else { throw CalculatorError.invalidExpression }
                let argument = try parseExpression()
                guard consume(")"),
                      let result = Self.apply(function: name, to: argument) else {
                    throw CalculatorError.invalidExpression
                }
                return try checked(result)
            }
            throw CalculatorError.invalidExpression
        }

        private mutating func parseNumber() throws -> Double {
            var text = ""
            var sawDigit = false
            var sawPoint = false
            while index < scalars.count {
                let scalar = scalars[index]
                if Self.isDigit(scalar) {
                    sawDigit = true
                    text.unicodeScalars.append(scalar)
                } else if scalar == ".", !sawPoint {
                    sawPoint = true
                    if !sawDigit { text += "0" }
                    text += "."
                } else {
                    break
                }
                index += 1
            }
            guard sawDigit else { throw CalculatorError.invalidExpression }
            if text.hasSuffix(".") { text += "0" }

            // Optional exponent (`1e-5`). A bare `e` that is not followed by
            // digits is left for the caller, so `2e` stays invalid.
            if index < scalars.count, scalars[index] == "e" || scalars[index] == "E" {
                var lookahead = index + 1
                var sign = ""
                if lookahead < scalars.count, scalars[lookahead] == "+" || scalars[lookahead] == "-" {
                    sign = String(Character(scalars[lookahead]))
                    lookahead += 1
                }
                if lookahead < scalars.count, Self.isDigit(scalars[lookahead]) {
                    text += "e" + sign
                    index = lookahead
                    while index < scalars.count, Self.isDigit(scalars[index]) {
                        text.unicodeScalars.append(scalars[index])
                        index += 1
                    }
                }
            }
            guard let number = Double(text), number.isFinite else {
                throw CalculatorError.invalidExpression
            }
            return number
        }

        private mutating func parseIdentifier() -> String {
            var name = ""
            while index < scalars.count, Self.isLetter(scalars[index]) {
                name.unicodeScalars.append(scalars[index])
                index += 1
            }
            return name.lowercased()
        }

        private mutating func consume(_ expected: Unicode.Scalar) -> Bool {
            skipWhitespace()
            guard index < scalars.count, scalars[index] == expected else { return false }
            index += 1
            return true
        }

        private mutating func skipWhitespace() {
            while index < scalars.count, scalars[index].properties.isWhitespace {
                index += 1
            }
        }

        private func checked(_ value: Double) throws -> Double {
            guard value.isFinite else { throw CalculatorError.invalidExpression }
            return value
        }

        private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
            ("0"..."9").contains(scalar)
        }

        private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
            ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
        }

        private static func constant(named name: String) -> Double? {
            switch name {
            case "pi": Double.pi
            case "e": M_E
            default: nil
            }
        }

        /// `round` rounds half away from zero on both platforms.
        private static func apply(function name: String, to value: Double) -> Double? {
            switch name {
            case "sqrt": sqrt(value)
            case "abs": abs(value)
            case "sin": sin(value)
            case "cos": cos(value)
            case "tan": tan(value)
            case "ln": log(value)
            case "log": log10(value)
            case "floor": floor(value)
            case "ceil": ceil(value)
            case "round": value.rounded(.toNearestOrAwayFromZero)
            default: nil
            }
        }
    }
}
