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
}
