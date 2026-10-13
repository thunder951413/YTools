import XCTest
import YToolsCore

final class ExpressionCalculatorTests: XCTestCase {
    private let calculator = ExpressionCalculator()

    func testRespectsOperatorPrecedence() throws {
        XCTAssertEqual(try calculator.evaluate("2 + 3 * 4"), 14)
    }

    func testSupportsParenthesesAndExponentiation() throws {
        XCTAssertEqual(try calculator.evaluate("(2 + 3) ^ 2"), 25)
        XCTAssertEqual(try calculator.evaluate("2 ^ 3 ^ 2"), 512)
    }

    func testSupportsSignedNumbersAndNativeSymbols() throws {
        XCTAssertEqual(try calculator.evaluate("-2 × 4 + 10 ÷ 2"), -3)
    }

    func testRejectsUnsafeOrInvalidInput() {
        XCTAssertThrowsError(try calculator.evaluate("open('/tmp')"))
        XCTAssertThrowsError(try calculator.evaluate("1 / 0")) { error in
            XCTAssertEqual(error as? CalculatorError, .divisionByZero)
        }
    }

    func testSupportsWhitelistedFunctionsAndConstants() throws {
        XCTAssertEqual(try calculator.evaluate("sqrt(16) + abs(-2)"), 6)
        XCTAssertEqual(try calculator.evaluate("round(pi)"), 3)
    }

    func testUnaryMinusBindsLooserThanPowerButTighterThanProducts() throws {
        XCTAssertEqual(try calculator.evaluate("2*-(3)"), -6)
        XCTAssertEqual(try calculator.evaluate("2^-1"), 0.5)
        XCTAssertEqual(try calculator.evaluate("2^-(1)"), 0.5)
        XCTAssertEqual(try calculator.evaluate("-2^2"), -4)
        XCTAssertEqual(try calculator.evaluate("--2"), 2)
        XCTAssertEqual(try calculator.evaluate("3 - -2"), 5)
    }

    func testFunctionResultsInExponentNotationStillEvaluate() throws {
        XCTAssertEqual(try calculator.evaluate("sqrt(1e-10)"), 1e-5, accuracy: 1e-20)
        XCTAssertEqual(try calculator.evaluate("floor(1e20)"), 1e20)
        XCTAssertEqual(try calculator.evaluate("1.5e3 + .5"), 1500.5)
        XCTAssertEqual(try calculator.evaluate("abs(sqrt(16)) * PI / pi"), 4)
    }

    func testRoundsHalfAwayFromZeroLikeWindows() throws {
        XCTAssertEqual(try calculator.evaluate("round(2.5)"), 3)
        XCTAssertEqual(try calculator.evaluate("round(-2.5)"), -3)
    }

    func testRejectsAmbiguousOrOutOfDomainInput() {
        for expression in ["", "1+", "(1+2", "1+2)", "abc", "1..2", "2e", "2pi", "pi(2)", "sqrt(-1)", "10^400"] {
            XCTAssertThrowsError(try calculator.evaluate(expression), expression)
        }
    }

    func testRejectsPathologicalNestingWithoutCrashing() throws {
        let deep = String(repeating: "(", count: 100) + "1" + String(repeating: ")", count: 100)
        XCTAssertThrowsError(try calculator.evaluate(deep))
        let nestedCalls = String(repeating: "abs(", count: 200) + "1" + String(repeating: ")", count: 200)
        XCTAssertThrowsError(try calculator.evaluate(nestedCalls))
        XCTAssertThrowsError(try calculator.evaluate(String(repeating: "-", count: 600) + "1"))
        let shallow = String(repeating: "(", count: 30) + "1" + String(repeating: ")", count: 30)
        XCTAssertEqual(try calculator.evaluate(shallow), 1)
    }

    func testFormatNeverTrapsOnLargeIntegers() throws {
        XCTAssertEqual(calculator.format(try calculator.evaluate("2^63")), "9.22337203685e+18")
        XCTAssertEqual(calculator.format(9_007_199_254_740_991), "9007199254740991")
        XCTAssertEqual(calculator.format(-0.0), "0")
        XCTAssertEqual(calculator.format(0.0000001), "1e-07")
    }
}
