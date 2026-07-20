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
                || expression.rangeOfCharacter(from: .letters) != nil,
              let value = try? calculator.evaluate(expression) else {
            return []
        }

        let result = calculator.format(value)
        return [LauncherResult(
            id: "calculator:\(expression)",
            moduleID: descriptor.id,
            title: result,
            subtitle: shouldContinue ? "\(expression)  ·  回车回填并继续计算" : "\(expression)  ·  回车复制结果",
            icon: .system("function"),
            score: 1_000,
            action: shouldContinue ? .navigate(result) : .copy(result)
        )]
    }
}
