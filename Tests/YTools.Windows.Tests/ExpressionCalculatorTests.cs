using YTools.Core;

namespace YTools.Windows.Tests;

public class ExpressionCalculatorTests
{
    [Theory]
    [InlineData("1+2", 3)]
    [InlineData("2*3+4", 10)]
    [InlineData("2+3*4", 14)]
    [InlineData("(2+3)*4", 20)]
    [InlineData("2^3^2", 512)]
    [InlineData("10%3", 1)]
    [InlineData("sqrt(16)", 4)]
    [InlineData("sqrt(2+2)", 2)]
    [InlineData("abs(-5)", 5)]
    [InlineData("floor(1.9)", 1)]
    [InlineData("ceil(1.1)", 2)]
    [InlineData("round(2.5)", 3)]
    [InlineData("round(-2.5)", -3)]
    [InlineData("2*-(3)", -6)]
    [InlineData("2^-1", 0.5)]
    [InlineData("2^-(1)", 0.5)]
    [InlineData("-2^2", -4)]
    [InlineData("--2", 2)]
    [InlineData("3 - -2", 5)]
    [InlineData("sqrt(1e-10)", 1e-5)]
    [InlineData("floor(1e20)", 1e20)]
    [InlineData("1.5e3 + .5", 1500.5)]
    [InlineData("abs(sqrt(16)) * PI / pi", 4)]
    [InlineData("e^1", 2.718281828459045)]
    [InlineData("pi", 3.141592653589793)]
    [InlineData("-5+3", -2)]
    [InlineData("6×7", 42)]
    [InlineData("8÷2", 4)]
    public void Evaluate_ReturnsExpected(string expression, double expected)
    {
        Assert.Equal(expected, ExpressionCalculator.Evaluate(expression), 10);
    }

    [Fact]
    public void Evaluate_ThrowsOnDivisionByZero()
    {
        var exception = Assert.Throws<CalculatorException>(() => ExpressionCalculator.Evaluate("1/0"));
        Assert.Equal(CalculatorError.DivisionByZero, exception.Error);
    }

    [Theory]
    [InlineData("")]
    [InlineData("1+")]
    [InlineData("(1+2")]
    [InlineData("1+2)")]
    [InlineData("abc")]
    [InlineData("1..2")]
    [InlineData("2e")]
    [InlineData("2pi")]
    [InlineData("pi(2)")]
    [InlineData("open(1)")]
    [InlineData("sqrt(-1)")]
    [InlineData("10^400")]
    [InlineData("1+２")]
    public void Evaluate_ThrowsOnInvalidExpression(string expression)
    {
        Assert.Throws<CalculatorException>(() => ExpressionCalculator.Evaluate(expression));
    }

    [Theory]
    [InlineData(3.0, "3")]
    [InlineData(3.14159265358979, "3.14159265359")]
    [InlineData(0.1, "0.1")]
    [InlineData(-2.5, "-2.5")]
    [InlineData(double.NaN, "")]
    [InlineData(double.PositiveInfinity, "")]
    [InlineData(-0.0, "0")]
    [InlineData(9007199254740991.0, "9007199254740991")]
    [InlineData(9223372036854775808.0, "9.22337203685e+18")]
    [InlineData(0.0000001, "1e-07")]
    public void Format_ReturnsExpected(double value, string expected)
    {
        Assert.Equal(expected, ExpressionCalculator.Format(value));
    }

    [Fact]
    public void Evaluate_RejectsPathologicalInput()
    {
        Assert.Throws<CalculatorException>(() => ExpressionCalculator.Evaluate(new string('(', 100) + "1" + new string(')', 100)));
        Assert.Throws<CalculatorException>(() => ExpressionCalculator.Evaluate(string.Concat(Enumerable.Repeat("abs(", 200)) + "1" + new string(')', 200)));
        Assert.Throws<CalculatorException>(() => ExpressionCalculator.Evaluate(new string('-', 600) + "1"));
        Assert.Equal(1, ExpressionCalculator.Evaluate(new string('(', 30) + "1" + new string(')', 30)));
    }

    [Fact]
    public void Format_OfTwoToThe63_DoesNotOverflow()
    {
        Assert.Equal("9.22337203685e+18", ExpressionCalculator.Format(ExpressionCalculator.Evaluate("2^63")));
    }
}
