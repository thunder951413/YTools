using YTools.Core;
using YTools.ModuleKit;

namespace YTools.Services.Modules;

public sealed class CalculatorModule : IYToolsModule
{
    public ModuleDescriptor Descriptor { get; } = new("calculator", "计算器");

    public Task<IReadOnlyList<LauncherResult>> SearchAsync(ModuleSearchRequest request)
    {
        var rawExpression = request.Query.Trim();
        var shouldContinue = rawExpression.EndsWith('=');
        var expression = shouldContinue
            ? rawExpression[..^1].Trim()
            : rawExpression;
        var hasOperator = expression.IndexOfAny(['+', '-', '*', '/', '%', '^', '×', '÷']) >= 0;
        var hasLetters = expression.Any(char.IsLetter);
        if (string.IsNullOrEmpty(expression) || (!hasOperator && !hasLetters))
        {
            return Task.FromResult<IReadOnlyList<LauncherResult>>([]);
        }

        double value;
        try
        {
            value = ExpressionCalculator.Evaluate(expression);
        }
        catch
        {
            return Task.FromResult<IReadOnlyList<LauncherResult>>([]);
        }

        var result = ExpressionCalculator.Format(value);
        return Task.FromResult<IReadOnlyList<LauncherResult>>(
        [
            new LauncherResult(
                $"calculator:{expression}",
                Descriptor.Id,
                result,
                shouldContinue ? $"{expression}  ·  回车回填并继续计算" : $"{expression}  ·  回车复制结果",
                new ResultIcon.System("function"),
                1_000,
                shouldContinue ? new ResultAction.Navigate(result) : new ResultAction.Copy(result))
        ]);
    }
}
