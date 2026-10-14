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
        guard let value = try? calculator.evaluate(expression) else { return [] }
        let explanation = expression

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

/// "300 的 20%" and "200+15%" style expressions the plain calculator rejects.
/// Kept separate so it can be switched off in settings.
struct PercentModule: YToolsModule {
    let descriptor = ModuleDescriptor(id: "percent", name: "百分比")
    private let calculator = ExpressionCalculator()

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        let expression = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty,
              (try? calculator.evaluate(expression)) == nil,
              let percent = PercentCalculator.evaluate(expression, calculator: calculator) else { return [] }
        let result = calculator.format(percent.value)
        return [LauncherResult(
            id: "percent:\(expression)",
            moduleID: descriptor.id,
            title: result,
            subtitle: "\(percent.explanation)  ·  回车复制结果",
            icon: .system("percent"),
            score: 1_000,
            action: .copy(result)
        )]
    }
}
