import Foundation
import YToolsCore
import YToolsModuleKit

struct CalculatorModule: YToolsModule {
    let descriptor = ModuleDescriptor(id: "calculator", name: "计算器")
    private let calculator = ExpressionCalculator()

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        let rawExpression = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldContinue = rawExpression.hasSuffix("=")
        let expression = shouldContinue
            ? String(rawExpression.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            : rawExpression
        guard !expression.isEmpty,
              expression.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/%^×÷")) != nil
                || expression.rangeOfCharacter(from: .letters) != nil else {
            return []
        }
        let value: Double
        var explanation = expression
        if let evaluated = try? calculator.evaluate(expression) {
            value = evaluated
        } else if let percent = PercentCalculator.evaluate(expression, calculator: calculator) {
            value = percent.value
            explanation = percent.explanation
        } else {
            return []
        }

        let result = calculator.format(value)
        return [LauncherResult(
            id: "calculator:\(expression)",
            moduleID: descriptor.id,
            title: result,
            subtitle: shouldContinue ? "\(explanation)  ·  回车回填并继续计算" : "\(explanation)  ·  回车复制结果",
            icon: .system("function"),
            score: 1_000,
            action: shouldContinue ? .editQuery(result) : .copy(result)
        )]
    }
}
