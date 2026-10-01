using System.Globalization;
using System.Text.RegularExpressions;
using YTools.ModuleKit;

namespace YTools.Services.Modules;

public sealed class UnitConversionModule : IYToolsModule
{
    private enum Kind
    {
        Length,
        Mass,
        Temperature,
        Duration,
        Storage
    }

    private sealed record UnitDefinition(Kind Kind, string Symbol, Func<double, double> ToBase, Func<double, double> FromBase);

    public ModuleDescriptor Descriptor { get; } = new("unit-conversion", "单位换算");

    private static readonly Regex InchPattern = new(
        @"^(-?\d+(?:\.\d+)?)\s+in\s+(\S+)$",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    private static readonly Regex ConversionPattern = new(
        @"^(-?\d+(?:\.\d+)?)\s*(\S+)\s+(?:to|in)\s+(\S+)$",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    public Task<IReadOnlyList<LauncherResult>> SearchAsync(ModuleSearchRequest request)
    {
        var normalized = request.Query.ToLowerInvariant()
            .Replace("转换为", " to ")
            .Replace("转", " to ")
            .Trim();

        (double Value, string Source, string Target)? parsed = null;
        var inchMatch = InchPattern.Match(normalized);
        if (inchMatch.Success
            && double.TryParse(inchMatch.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var inchValue))
        {
            parsed = (inchValue, "in", inchMatch.Groups[2].Value);
        }
        else
        {
            var match = ConversionPattern.Match(normalized);
            if (match.Success
                && double.TryParse(match.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var value))
            {
                parsed = (value, match.Groups[2].Value, match.Groups[3].Value);
            }
        }

        if (parsed is null
            || !Units.TryGetValue(parsed.Value.Source, out var source)
            || !Units.TryGetValue(parsed.Value.Target, out var target)
            || source.Kind != target.Kind)
        {
            return Task.FromResult<IReadOnlyList<LauncherResult>>([]);
        }

        var converted = target.FromBase(source.ToBase(parsed.Value.Value));
        if (double.IsNaN(converted) || double.IsInfinity(converted))
        {
            return Task.FromResult<IReadOnlyList<LauncherResult>>([]);
        }

        var text = Format(converted);
        return Task.FromResult<IReadOnlyList<LauncherResult>>(
        [
            new LauncherResult(
                $"convert:{normalized}",
                Descriptor.Id,
                $"{text} {target.Symbol}",
                $"{Format(parsed.Value.Value)} {source.Symbol} → {target.Symbol} · 离线换算",
                new ResultIcon.System("ruler"),
                1_020,
                new ResultAction.Copy(text))
        ]);
    }

    private static readonly IReadOnlyDictionary<string, UnitDefinition> Units = BuildUnits();

    private static Dictionary<string, UnitDefinition> BuildUnits()
    {
        var output = new Dictionary<string, UnitDefinition>();

        void Add(string[] aliases, UnitDefinition unit)
        {
            foreach (var alias in aliases)
            {
                output[alias] = unit;
            }
        }

        UnitDefinition Linear(Kind kind, string symbol, double factor)
        {
            return new UnitDefinition(kind, symbol, value => value * factor, value => value / factor);
        }

        Add(["m", "米"], Linear(Kind.Length, "m", 1));
        Add(["km", "公里", "千米"], Linear(Kind.Length, "km", 1_000));
        Add(["cm", "厘米"], Linear(Kind.Length, "cm", 0.01));
        Add(["mm", "毫米"], Linear(Kind.Length, "mm", 0.001));
        Add(["mi", "mile", "miles", "英里"], Linear(Kind.Length, "mi", 1_609.344));
        Add(["ft", "feet", "英尺"], Linear(Kind.Length, "ft", 0.3048));
        Add(["in", "inch", "inches", "英寸"], Linear(Kind.Length, "in", 0.0254));
        Add(["kg", "千克", "公斤"], Linear(Kind.Mass, "kg", 1));
        Add(["g", "克"], Linear(Kind.Mass, "g", 0.001));
        Add(["lb", "lbs", "磅"], Linear(Kind.Mass, "lb", 0.45359237));
        Add(["s", "sec", "秒"], Linear(Kind.Duration, "s", 1));
        Add(["min", "分钟"], Linear(Kind.Duration, "min", 60));
        Add(["h", "hr", "小时"], Linear(Kind.Duration, "h", 3_600));
        Add(["mb"], Linear(Kind.Storage, "MB", 1_000_000));
        Add(["gb"], Linear(Kind.Storage, "GB", 1_000_000_000));
        Add(["mib"], Linear(Kind.Storage, "MiB", 1_048_576));
        Add(["gib"], Linear(Kind.Storage, "GiB", 1_073_741_824));
        Add(
            ["c", "°c", "摄氏度"],
            new UnitDefinition(Kind.Temperature, "°C", value => value, value => value));
        Add(
            ["f", "°f", "华氏度"],
            new UnitDefinition(Kind.Temperature, "°F", value => (value - 32) * 5 / 9, value => value * 9 / 5 + 32));
        Add(
            ["k", "开尔文"],
            new UnitDefinition(Kind.Temperature, "K", value => value - 273.15, value => value + 273.15));
        return output;
    }

    private static string Format(double value)
    {
        return value.ToString("G12", CultureInfo.InvariantCulture);
    }
}
