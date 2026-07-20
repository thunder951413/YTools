import Foundation

public enum CalculatorError: Error, Equatable, Sendable {
    case invalidExpression
    case divisionByZero
}

public struct ExpressionCalculator: Sendable {
    private enum Token: Equatable {
        case number(Double)
        case operation(Character)
        case leftParenthesis
        case rightParenthesis
    }

    public init() {}

    public func evaluate(_ expression: String) throws -> Double {
        let normalized = try resolveFunctions(in: expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "**", with: "^"))

        let tokens = try tokenize(normalized)
        guard !tokens.isEmpty else { throw CalculatorError.invalidExpression }
        let postfix = try makePostfix(tokens)
        return try evaluatePostfix(postfix)
    }

    public func format(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value.rounded() == value, abs(value) <= Double(Int64.max) {
            return String(Int64(value))
        }
        return String(format: "%.12g", value)
    }

    private func resolveFunctions(in expression: String) throws -> String {
        var value = expression
        let constants = ["pi": Double.pi, "e": M_E]
        for (name, number) in constants {
            value = value.replacingOccurrences(
                of: "\\b\(name)\\b",
                with: String(number),
                options: [.regularExpression, .caseInsensitive]
            )
        }

        let functions: [String: (Double) -> Double] = [
            "sqrt": sqrt,
            "abs": abs,
            "sin": sin,
            "cos": cos,
            "tan": tan,
            "ln": log,
            "log": log10,
            "floor": floor,
            "ceil": ceil,
            "round": round
        ]

        while let call = nextFunctionCall(in: value) {
            guard let function = functions[call.name.lowercased()] else {
                throw CalculatorError.invalidExpression
            }
            let argument = String(value[call.argumentRange])
            let argumentValue = try evaluate(argument)
            let result = function(argumentValue)
            guard result.isFinite else { throw CalculatorError.invalidExpression }
            value.replaceSubrange(call.fullRange, with: String(result))
        }
        return value
    }

    private func nextFunctionCall(
        in expression: String
    ) -> (name: String, fullRange: Range<String.Index>, argumentRange: Range<String.Index>)? {
        var index = expression.startIndex
        while index < expression.endIndex {
            guard expression[index].isLetter else {
                index = expression.index(after: index)
                continue
            }
            let nameStart = index
            while index < expression.endIndex, expression[index].isLetter {
                index = expression.index(after: index)
            }
            let name = String(expression[nameStart..<index])
            guard index < expression.endIndex, expression[index] == "(" else { continue }
            let open = index
            var depth = 0
            var cursor = open
            while cursor < expression.endIndex {
                if expression[cursor] == "(" { depth += 1 }
                if expression[cursor] == ")" {
                    depth -= 1
                    if depth == 0 {
                        let argumentStart = expression.index(after: open)
                        return (
                            name,
                            nameStart..<expression.index(after: cursor),
                            argumentStart..<cursor
                        )
                    }
                }
                cursor = expression.index(after: cursor)
            }
            return nil
        }
        return nil
    }

    private func tokenize(_ expression: String) throws -> [Token] {
        let characters = Array(expression)
        var tokens: [Token] = []
        var index = 0
        var expectsValue = true

        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
                continue
            }

            if character == "(" {
                tokens.append(.leftParenthesis)
                expectsValue = true
                index += 1
                continue
            }
            if character == ")" {
                tokens.append(.rightParenthesis)
                expectsValue = false
                index += 1
                continue
            }

            let isSignedNumber = (character == "+" || character == "-")
                && expectsValue
                && index + 1 < characters.count
                && (characters[index + 1].isNumber || characters[index + 1] == ".")

            if character.isNumber || character == "." || isSignedNumber {
                let start = index
                if isSignedNumber { index += 1 }
                var sawDecimalPoint = false
                while index < characters.count {
                    if characters[index] == "." {
                        if sawDecimalPoint { throw CalculatorError.invalidExpression }
                        sawDecimalPoint = true
                        index += 1
                    } else if characters[index].isNumber {
                        index += 1
                    } else {
                        break
                    }
                }
                guard let number = Double(String(characters[start..<index])) else {
                    throw CalculatorError.invalidExpression
                }
                tokens.append(.number(number))
                expectsValue = false
                continue
            }

            if "+-*/%^".contains(character) {
                if expectsValue, character == "-" {
                    tokens.append(.number(0))
                } else if expectsValue {
                    throw CalculatorError.invalidExpression
                }
                tokens.append(.operation(character))
                expectsValue = true
                index += 1
                continue
            }

            throw CalculatorError.invalidExpression
        }

        if expectsValue, !tokens.isEmpty { throw CalculatorError.invalidExpression }
        return tokens
    }

    private func makePostfix(_ tokens: [Token]) throws -> [Token] {
        var output: [Token] = []
        var operators: [Token] = []

        for token in tokens {
            switch token {
            case .number:
                output.append(token)
            case let .operation(operation):
                while case let .operation(top)? = operators.last,
                      precedence(top) > precedence(operation)
                        || (precedence(top) == precedence(operation) && operation != "^") {
                    output.append(operators.removeLast())
                }
                operators.append(token)
            case .leftParenthesis:
                operators.append(token)
            case .rightParenthesis:
                var foundLeftParenthesis = false
                while let top = operators.popLast() {
                    if top == .leftParenthesis {
                        foundLeftParenthesis = true
                        break
                    }
                    output.append(top)
                }
                if !foundLeftParenthesis { throw CalculatorError.invalidExpression }
            }
        }

        while let token = operators.popLast() {
            if token == .leftParenthesis { throw CalculatorError.invalidExpression }
            output.append(token)
        }
        return output
    }

    private func evaluatePostfix(_ tokens: [Token]) throws -> Double {
        var stack: [Double] = []
        for token in tokens {
            switch token {
            case let .number(number):
                stack.append(number)
            case let .operation(operation):
                guard stack.count >= 2 else { throw CalculatorError.invalidExpression }
                let right = stack.removeLast()
                let left = stack.removeLast()
                let result: Double
                switch operation {
                case "+": result = left + right
                case "-": result = left - right
                case "*": result = left * right
                case "/":
                    if right == 0 { throw CalculatorError.divisionByZero }
                    result = left / right
                case "%":
                    if right == 0 { throw CalculatorError.divisionByZero }
                    result = left.truncatingRemainder(dividingBy: right)
                case "^": result = pow(left, right)
                default: throw CalculatorError.invalidExpression
                }
                guard result.isFinite else { throw CalculatorError.invalidExpression }
                stack.append(result)
            default:
                throw CalculatorError.invalidExpression
            }
        }
        guard stack.count == 1, let result = stack.first else {
            throw CalculatorError.invalidExpression
        }
        return result
    }

    private func precedence(_ operation: Character) -> Int {
        switch operation {
        case "+", "-": 1
        case "*", "/", "%": 2
        case "^": 3
        default: 0
        }
    }
}
