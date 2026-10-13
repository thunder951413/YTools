using System.Globalization;

namespace YTools.Core;

public enum CalculatorError
{
    InvalidExpression,
    DivisionByZero
}

/// <summary>
/// Whitelisted arithmetic evaluator implemented as a recursive-descent parser.
/// Mirrors <c>Sources/YToolsCore/ExpressionCalculator.swift</c> exactly:
/// <code>
/// expression := term (('+' | '-') term)*
/// term       := unary (('*' | '/' | '%') unary)*
/// unary      := ('+' | '-') unary | power
/// power      := primary ('^' unary)?          // right-associative
/// primary    := number | constant | function '(' expression ')' | '(' expression ')'
/// </code>
/// Unary minus binds looser than <c>^</c> (<c>-2^2 == -4</c>), the exponent may
/// carry its own sign (<c>2^-1 == 0.5</c>), and functions/constants are tokens
/// rather than text substitutions. Input length and nesting depth are bounded.
/// Never executes shell input.
/// </summary>
public static class ExpressionCalculator
{
    public const int MaximumLength = 512;
    public const int MaximumDepth = 64;

    public static double Evaluate(string expression)
    {
        var normalized = expression
            .Replace("×", "*")
            .Replace("÷", "/")
            .Replace("**", "^");
        if (normalized.Length > MaximumLength)
        {
            throw Invalid();
        }

        return new Parser(normalized).Parse();
    }

    /// <summary>
    /// Integers that are exactly representable (|x| &lt; 2^53) print without a
    /// fractional part; everything else uses 12 significant digits with a
    /// lowercase exponent, matching the macOS <c>%.12g</c> output.
    /// </summary>
    public static string Format(double value)
    {
        if (double.IsNaN(value) || double.IsInfinity(value))
        {
            return "";
        }

        if (Math.Round(value) == value && Math.Abs(value) < 9_007_199_254_740_992d)
        {
            return ((long)value).ToString(CultureInfo.InvariantCulture);
        }

        return value.ToString("G12", CultureInfo.InvariantCulture).Replace('E', 'e');
    }

    private static CalculatorException Invalid() => new(CalculatorError.InvalidExpression);

    private sealed class Parser
    {
        private readonly string _text;
        private int _index;
        private int _depth;

        public Parser(string text)
        {
            _text = text;
        }

        public double Parse()
        {
            var value = ParseExpression();
            SkipWhitespace();
            if (_index != _text.Length)
            {
                throw Invalid();
            }

            return value;
        }

        private void Enter()
        {
            _depth += 1;
            if (_depth > MaximumDepth)
            {
                throw Invalid();
            }
        }

        private double ParseExpression()
        {
            Enter();
            try
            {
                var value = ParseTerm();
                while (true)
                {
                    if (Consume('+'))
                    {
                        var right = ParseTerm();
                        value = Checked(value + right);
                    }
                    else if (Consume('-'))
                    {
                        var right = ParseTerm();
                        value = Checked(value - right);
                    }
                    else
                    {
                        return value;
                    }
                }
            }
            finally
            {
                _depth -= 1;
            }
        }

        private double ParseTerm()
        {
            var value = ParseUnary();
            while (true)
            {
                if (Consume('*'))
                {
                    var right = ParseUnary();
                    value = Checked(value * right);
                }
                else if (Consume('/'))
                {
                    var right = ParseUnary();
                    if (right == 0)
                    {
                        throw new CalculatorException(CalculatorError.DivisionByZero);
                    }

                    value = Checked(value / right);
                }
                else if (Consume('%'))
                {
                    var right = ParseUnary();
                    if (right == 0)
                    {
                        throw new CalculatorException(CalculatorError.DivisionByZero);
                    }

                    value = Checked(value % right);
                }
                else
                {
                    return value;
                }
            }
        }

        private double ParseUnary()
        {
            if (Consume('-'))
            {
                Enter();
                try
                {
                    return -ParseUnary();
                }
                finally
                {
                    _depth -= 1;
                }
            }

            if (Consume('+'))
            {
                Enter();
                try
                {
                    return ParseUnary();
                }
                finally
                {
                    _depth -= 1;
                }
            }

            return ParsePower();
        }

        private double ParsePower()
        {
            var baseValue = ParsePrimary();
            if (!Consume('^'))
            {
                return baseValue;
            }

            var exponent = ParseUnary();
            return Checked(Math.Pow(baseValue, exponent));
        }

        private double ParsePrimary()
        {
            SkipWhitespace();
            if (_index >= _text.Length)
            {
                throw Invalid();
            }

            var character = _text[_index];
            if (character == '(')
            {
                _index += 1;
                var value = ParseExpression();
                if (!Consume(')'))
                {
                    throw Invalid();
                }

                return value;
            }

            if (IsDigit(character) || character == '.')
            {
                return ParseNumber();
            }

            if (IsLetter(character))
            {
                var name = ParseIdentifier();
                var constant = Constant(name);
                if (constant is { } constantValue)
                {
                    return constantValue;
                }

                if (!Consume('('))
                {
                    throw Invalid();
                }

                var argument = ParseExpression();
                if (!Consume(')') || Apply(name, argument) is not { } result)
                {
                    throw Invalid();
                }

                return Checked(result);
            }

            throw Invalid();
        }

        private double ParseNumber()
        {
            var builder = new System.Text.StringBuilder();
            var sawDigit = false;
            var sawPoint = false;
            while (_index < _text.Length)
            {
                var character = _text[_index];
                if (IsDigit(character))
                {
                    sawDigit = true;
                    builder.Append(character);
                }
                else if (character == '.' && !sawPoint)
                {
                    sawPoint = true;
                    if (!sawDigit)
                    {
                        builder.Append('0');
                    }

                    builder.Append('.');
                }
                else
                {
                    break;
                }

                _index += 1;
            }

            if (!sawDigit)
            {
                throw Invalid();
            }

            if (builder[^1] == '.')
            {
                builder.Append('0');
            }

            // Optional exponent (1e-5). A bare e not followed by digits is left
            // for the caller, so "2e" stays invalid.
            if (_index < _text.Length && (_text[_index] == 'e' || _text[_index] == 'E'))
            {
                var lookahead = _index + 1;
                var sign = "";
                if (lookahead < _text.Length && (_text[lookahead] == '+' || _text[lookahead] == '-'))
                {
                    sign = _text[lookahead].ToString();
                    lookahead += 1;
                }

                if (lookahead < _text.Length && IsDigit(_text[lookahead]))
                {
                    builder.Append('e').Append(sign);
                    _index = lookahead;
                    while (_index < _text.Length && IsDigit(_text[_index]))
                    {
                        builder.Append(_text[_index]);
                        _index += 1;
                    }
                }
            }

            if (!double.TryParse(
                    builder.ToString(),
                    NumberStyles.AllowDecimalPoint | NumberStyles.AllowExponent,
                    CultureInfo.InvariantCulture,
                    out var number)
                || double.IsNaN(number)
                || double.IsInfinity(number))
            {
                throw Invalid();
            }

            return number;
        }

        private string ParseIdentifier()
        {
            var start = _index;
            while (_index < _text.Length && IsLetter(_text[_index]))
            {
                _index += 1;
            }

            return _text[start.._index].ToLowerInvariant();
        }

        private bool Consume(char expected)
        {
            SkipWhitespace();
            if (_index >= _text.Length || _text[_index] != expected)
            {
                return false;
            }

            _index += 1;
            return true;
        }

        private void SkipWhitespace()
        {
            while (_index < _text.Length && char.IsWhiteSpace(_text[_index]))
            {
                _index += 1;
            }
        }

        private static double Checked(double value)
        {
            if (double.IsNaN(value) || double.IsInfinity(value))
            {
                throw Invalid();
            }

            return value;
        }

        private static bool IsDigit(char character) => character is >= '0' and <= '9';

        private static bool IsLetter(char character) =>
            character is (>= 'a' and <= 'z') or (>= 'A' and <= 'Z');

        private static double? Constant(string name) => name switch
        {
            "pi" => Math.PI,
            "e" => Math.E,
            _ => null
        };

        /// <summary><c>round</c> rounds half away from zero on both platforms.</summary>
        private static double? Apply(string name, double value) => name switch
        {
            "sqrt" => Math.Sqrt(value),
            "abs" => Math.Abs(value),
            "sin" => Math.Sin(value),
            "cos" => Math.Cos(value),
            "tan" => Math.Tan(value),
            "ln" => Math.Log(value),
            "log" => Math.Log10(value),
            "floor" => Math.Floor(value),
            "ceil" => Math.Ceiling(value),
            "round" => Math.Round(value, MidpointRounding.AwayFromZero),
            _ => null
        };
    }
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
