using System.Globalization;
using System.Text.RegularExpressions;

namespace YTools.Core;

public enum CalculatorError
{
    InvalidExpression,
    DivisionByZero
}

/// <summary>
/// Port of the macOS YToolsCore expression calculator: whitelisted functions,
/// constants, %, ^ and full parentheses support. Never executes shell input.
/// </summary>
public static class ExpressionCalculator
{
    private readonly record struct Token(TokenKind Kind, double Number = 0, char Operation = '\0');

    private enum TokenKind
    {
        Number,
        Operation,
        LeftParenthesis,
        RightParenthesis
    }

    private static readonly IReadOnlyDictionary<string, Func<double, double>> Functions =
        new Dictionary<string, Func<double, double>>
        {
            ["sqrt"] = Math.Sqrt,
            ["abs"] = Math.Abs,
            ["sin"] = Math.Sin,
            ["cos"] = Math.Cos,
            ["tan"] = Math.Tan,
            ["ln"] = Math.Log,
            ["log"] = Math.Log10,
            ["floor"] = Math.Floor,
            ["ceil"] = Math.Ceiling,
            ["round"] = Math.Round
        };

    public static double Evaluate(string expression)
    {
        var normalized = ResolveFunctions(expression
            .Replace("×", "*")
            .Replace("÷", "/")
            .Replace("**", "^"));

        var tokens = Tokenize(normalized);
        if (tokens.Count == 0)
        {
            throw new CalculatorException(CalculatorError.InvalidExpression);
        }

        var postfix = MakePostfix(tokens);
        return EvaluatePostfix(postfix);
    }

    public static string Format(double value)
    {
        if (double.IsNaN(value) || double.IsInfinity(value))
        {
            return "";
        }

        if (Math.Round(value) == value && Math.Abs(value) <= long.MaxValue)
        {
            return ((long)value).ToString(CultureInfo.InvariantCulture);
        }

        return value.ToString("G12", CultureInfo.InvariantCulture);
    }

    private static string ResolveFunctions(string expression)
    {
        var value = expression;
        value = Regex.Replace(
            value,
            @"\bpi\b",
            Math.PI.ToString("R", CultureInfo.InvariantCulture),
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        value = Regex.Replace(
            value,
            @"\be\b",
            Math.E.ToString("R", CultureInfo.InvariantCulture),
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

        while (TryNextFunctionCall(value, out var call))
        {
            if (!Functions.TryGetValue(call.Name.ToLowerInvariant(), out var function))
            {
                throw new CalculatorException(CalculatorError.InvalidExpression);
            }

            var argument = value.Substring(call.ArgumentStart, call.ArgumentLength);
            var argumentValue = Evaluate(argument);
            var result = function(argumentValue);
            if (double.IsNaN(result) || double.IsInfinity(result))
            {
                throw new CalculatorException(CalculatorError.InvalidExpression);
            }

            value = value
                .Remove(call.FullStart, call.FullLength)
                .Insert(call.FullStart, result.ToString("R", CultureInfo.InvariantCulture));
        }

        return value;
    }

    private static bool TryNextFunctionCall(string expression, out FunctionCall call)
    {
        call = default;
        var index = 0;
        while (index < expression.Length)
        {
            if (!char.IsLetter(expression[index]))
            {
                index += 1;
                continue;
            }

            var nameStart = index;
            while (index < expression.Length && char.IsLetter(expression[index]))
            {
                index += 1;
            }

            var name = expression.Substring(nameStart, index - nameStart);
            if (index >= expression.Length || expression[index] != '(')
            {
                continue;
            }

            var open = index;
            var depth = 0;
            var cursor = open;
            while (cursor < expression.Length)
            {
                if (expression[cursor] == '(')
                {
                    depth += 1;
                }

                if (expression[cursor] == ')')
                {
                    depth -= 1;
                    if (depth == 0)
                    {
                        var argumentStart = open + 1;
                        call = new FunctionCall(
                            name,
                            nameStart,
                            cursor + 1 - nameStart,
                            argumentStart,
                            cursor - argumentStart);
                        return true;
                    }
                }

                cursor += 1;
            }

            return false;
        }

        return false;
    }

    private static List<Token> Tokenize(string expression)
    {
        var tokens = new List<Token>();
        var index = 0;
        var expectsValue = true;

        while (index < expression.Length)
        {
            var character = expression[index];
            if (char.IsWhiteSpace(character))
            {
                index += 1;
                continue;
            }

            if (character == '(')
            {
                tokens.Add(new Token(TokenKind.LeftParenthesis));
                expectsValue = true;
                index += 1;
                continue;
            }

            if (character == ')')
            {
                tokens.Add(new Token(TokenKind.RightParenthesis));
                expectsValue = false;
                index += 1;
                continue;
            }

            var isSignedNumber = (character == '+' || character == '-')
                && expectsValue
                && index + 1 < expression.Length
                && (char.IsDigit(expression[index + 1]) || expression[index + 1] == '.');

            if (char.IsDigit(character) || character == '.' || isSignedNumber)
            {
                var start = index;
                if (isSignedNumber)
                {
                    index += 1;
                }

                var sawDecimalPoint = false;
                while (index < expression.Length)
                {
                    if (expression[index] == '.')
                    {
                        if (sawDecimalPoint)
                        {
                            throw new CalculatorException(CalculatorError.InvalidExpression);
                        }

                        sawDecimalPoint = true;
                        index += 1;
                    }
                    else if (char.IsDigit(expression[index]))
                    {
                        index += 1;
                    }
                    else
                    {
                        break;
                    }
                }

                if (!double.TryParse(
                        expression.Substring(start, index - start),
                        NumberStyles.Float,
                        CultureInfo.InvariantCulture,
                        out var number))
                {
                    throw new CalculatorException(CalculatorError.InvalidExpression);
                }

                tokens.Add(new Token(TokenKind.Number, number));
                expectsValue = false;
                continue;
            }

            if ("+-*/%^".Contains(character))
            {
                if (expectsValue && character == '-')
                {
                    tokens.Add(new Token(TokenKind.Number, 0));
                }
                else if (expectsValue)
                {
                    throw new CalculatorException(CalculatorError.InvalidExpression);
                }

                tokens.Add(new Token(TokenKind.Operation, Operation: character));
                expectsValue = true;
                index += 1;
                continue;
            }

            throw new CalculatorException(CalculatorError.InvalidExpression);
        }

        if (expectsValue && tokens.Count > 0)
        {
            throw new CalculatorException(CalculatorError.InvalidExpression);
        }

        return tokens;
    }

    private static List<Token> MakePostfix(List<Token> tokens)
    {
        var output = new List<Token>();
        var operators = new Stack<Token>();

        foreach (var token in tokens)
        {
            switch (token.Kind)
            {
                case TokenKind.Number:
                    output.Add(token);
                    break;
                case TokenKind.Operation:
                    while (operators.Count > 0
                           && operators.Peek().Kind == TokenKind.Operation
                           && (Precedence(operators.Peek().Operation) > Precedence(token.Operation)
                               || (Precedence(operators.Peek().Operation) == Precedence(token.Operation)
                                   && token.Operation != '^')))
                    {
                        output.Add(operators.Pop());
                    }

                    operators.Push(token);
                    break;
                case TokenKind.LeftParenthesis:
                    operators.Push(token);
                    break;
                case TokenKind.RightParenthesis:
                    var foundLeftParenthesis = false;
                    while (operators.Count > 0)
                    {
                        var top = operators.Pop();
                        if (top.Kind == TokenKind.LeftParenthesis)
                        {
                            foundLeftParenthesis = true;
                            break;
                        }

                        output.Add(top);
                    }

                    if (!foundLeftParenthesis)
                    {
                        throw new CalculatorException(CalculatorError.InvalidExpression);
                    }

                    break;
            }
        }

        while (operators.Count > 0)
        {
            var token = operators.Pop();
            if (token.Kind == TokenKind.LeftParenthesis)
            {
                throw new CalculatorException(CalculatorError.InvalidExpression);
            }

            output.Add(token);
        }

        return output;
    }

    private static double EvaluatePostfix(List<Token> tokens)
    {
        var stack = new Stack<double>();
        foreach (var token in tokens)
        {
            switch (token.Kind)
            {
                case TokenKind.Number:
                    stack.Push(token.Number);
                    break;
                case TokenKind.Operation:
                    if (stack.Count < 2)
                    {
                        throw new CalculatorException(CalculatorError.InvalidExpression);
                    }

                    var right = stack.Pop();
                    var left = stack.Pop();
                    double result;
                    switch (token.Operation)
                    {
                        case '+':
                            result = left + right;
                            break;
                        case '-':
                            result = left - right;
                            break;
                        case '*':
                            result = left * right;
                            break;
                        case '/':
                            if (right == 0)
                            {
                                throw new CalculatorException(CalculatorError.DivisionByZero);
                            }

                            result = left / right;
                            break;
                        case '%':
                            if (right == 0)
                            {
                                throw new CalculatorException(CalculatorError.DivisionByZero);
                            }

                            result = left % right;
                            break;
                        case '^':
                            result = Math.Pow(left, right);
                            break;
                        default:
                            throw new CalculatorException(CalculatorError.InvalidExpression);
                    }

                    if (double.IsNaN(result) || double.IsInfinity(result))
                    {
                        throw new CalculatorException(CalculatorError.InvalidExpression);
                    }

                    stack.Push(result);
                    break;
                default:
                    throw new CalculatorException(CalculatorError.InvalidExpression);
            }
        }

        if (stack.Count != 1)
        {
            throw new CalculatorException(CalculatorError.InvalidExpression);
        }

        return stack.Pop();
    }

    private static int Precedence(char operation)
    {
        return operation switch
        {
            '+' or '-' => 1,
            '*' or '/' or '%' => 2,
            '^' => 3,
            _ => 0
        };
    }

    private readonly record struct FunctionCall(
        string Name,
        int FullStart,
        int FullLength,
        int ArgumentStart,
        int ArgumentLength);
}

public sealed class CalculatorException : Exception
{
    public CalculatorException(CalculatorError error)
        : base(error == CalculatorError.DivisionByZero ? "除以零" : "无效表达式")
    {
        Error = error;
    }

    public CalculatorError Error { get; }
}
