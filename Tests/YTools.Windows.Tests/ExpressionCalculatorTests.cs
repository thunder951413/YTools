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
    [InlineData("round(2.5)", 2)]
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
    public void Format_ReturnsExpected(double value, string expected)
    {
        Assert.Equal(expected, ExpressionCalculator.Format(value));
    }
}
