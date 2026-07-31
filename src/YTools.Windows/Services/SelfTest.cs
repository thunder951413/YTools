using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using YTools.Core;
using YTools.ModuleKit;
using YTools.Services.Modules;

namespace YTools.Services;

/// <summary>
/// Console self-test entry point (--selftest): validates the ported core,
/// offline dictionary, spelling engine and module policies without launching
/// the UI. Mirrors the macOS YToolsCoreChecks entry.
/// </summary>
public static class SelfTest
{
    public static int Run()
    {
        AttachConsole();
        var failures = new List<string>();
        var passed = 0;

        void Check(string name, bool ok, string? detail = null)
        {
            if (ok)
            {
                passed += 1;
                Console.WriteLine($"[PASS] {name}");
            }
            else
            {
                failures.Add(string.IsNullOrEmpty(detail) ? name : $"{name}: {detail}");
                Console.WriteLine($"[FAIL] {name} — {detail ?? "未通过"}");
            }
        }

        try
        {
            Check("calculator.basic", ExpressionCalculator.Evaluate("2+3*4") == 14);
            Check("calculator.power", ExpressionCalculator.Evaluate("2^3^2") == 512);
            Check("calculator.function", ExpressionCalculator.Evaluate("sqrt(16)") == 4);
            Check("calculator.divisionByZero", Throws<CalculatorException>(() => ExpressionCalculator.Evaluate("1/0")));
            Check("calculator.format", ExpressionCalculator.Format(3.14159265358979) == "3.14159265359");

            var normalizer = new SearchTextNormalizer();
            var forms = normalizer.Forms("微信");
            Check("normalizer.pinyin", forms.Transliteration == "weixin" && forms.TransliterationInitials == "wx");
            Check("normalizer.abbreviation", normalizer.Forms("Visual Studio Code").Abbreviation == "vsc");
            Check("normalizer.fuzzy", normalizer.FuzzyScore("slk", "Slack") is { } fuzzy && fuzzy is >= 1 and <= 99);

            var router = new PanelCommandRouter();
            Check(
                "router.enter",
                router.Command(new PanelKeyEvent(0x0D, PanelKeyModifiers.None), PanelInputMode.Launcher)?.Kind
                    == PanelCommandKind.ActivateSelected);
            Check(
                "router.ctrlNumber",
                router.Command(new PanelKeyEvent(0x35, PanelKeyModifiers.Command), PanelInputMode.Launcher)?.Payload
                    == 5);
            Check(
                "router.altUp",
                router.Command(new PanelKeyEvent(0x26, PanelKeyModifiers.Option), PanelInputMode.Launcher)?.Kind
                    == PanelCommandKind.AddSelectedToBuffer);

            var policy = new ModuleResultPolicy();
            var module = new ModuleDescriptor("module", "模块");
            var fileResult = new LauncherResult(
                "id",
                "module",
                "title",
                "subtitle",
                new ResultIcon.File(@"C:\Windows\win.ini"),
                100,
                new ResultAction.Open(@"C:\Windows\win.ini"));
            Check("policy.rejectsFileWithoutCapability", policy.Sanitize(fileResult, module) is null);

            var privilegedPolicy = new ModuleResultPolicy(allowsPrivilegedActions: true);
            Check(
                "policy.allowsPrivileged",
                privilegedPolicy.Sanitize(
                    fileResult with { Action = new ResultAction.EmptyTrash(), Icon = new ResultIcon.System("trash") },
                    module) is not null);

            var clipboardPolicy = new ClipboardTextPolicy(100);
            Check("clipboardPolicy.limit", !clipboardPolicy.ShouldStore(new string('a', 101)));

            var placement = RelativePanelPlacement.Create(0.25, 0.5, 800, 600);
            Check(
                "placement.roundTrip",
                placement is { } value && value.ResolvedLeft(0, 800) == 200 && value.ResolvedTop(0, 600) == 300);

            var calculatorModule = new CalculatorModule();
            var calculatorResults = calculatorModule.SearchAsync(new ModuleSearchRequest("1+2", 5)).GetAwaiter().GetResult();
            Check("module.calculator", calculatorResults.Count == 1 && calculatorResults[0].Title == "3");

            var unitModule = new UnitConversionModule();
            var unitResults = unitModule.SearchAsync(new ModuleSearchRequest("1 km to m", 5)).GetAwaiter().GetResult();
            Check("module.unitConversion", unitResults.Count == 1 && unitResults[0].Title == "1000 m");

            var textStats = new TextStatisticsModule();
            var statsResults = textStats.SearchAsync(new ModuleSearchRequest("统计 hello world", 5)).GetAwaiter().GetResult();
            Check("module.textStatistics", statsResults.Count == 1 && statsResults[0].Title.Contains("字符"));

            var applicationIndex = new ApplicationIndexService();
            applicationIndex.Prepare();
            var applicationResults = applicationIndex.Search("note", new Dictionary<string, string>());
            Check("applications.index", applicationResults.Count > 0);

            var fileSearch = new FileSearchService();
            var fileResults = fileSearch.SearchAsync(
                "documents",
                FileSearchMode.Default,
                [],
                5,
                CancellationToken.None).GetAwaiter().GetResult();
            Check("files.index", fileResults.Count > 0);
            fileSearch.Dispose();

            var dictionary = new DictionaryService();
            var englishResults = dictionary.Search("hello", 5);
            var chineseResults = dictionary.Search("微信", 5);
            Check("dictionary.english", englishResults.Count > 0 && englishResults[0].Definitions.Count > 0);
            Check("dictionary.chinese", chineseResults.Count > 0 && chineseResults[0].Simplified == "微信");

            var spelling = new SpellingService();
            var correct = spelling.Check("hello");
            var misspelled = spelling.Check("helllo");
            Console.WriteLine(
                $"[INFO] spelling helllo correct={misspelled.IsCorrect} suggestions={misspelled.Suggestions.Count} [{string.Join(",", misspelled.Suggestions)}]");
            Check("spelling.correct", correct.IsCorrect);
            Check(
                "spelling.suggestions",
                !misspelled.IsCorrect && misspelled.Suggestions.Count > 0,
                $"correct={misspelled.IsCorrect} suggestions={misspelled.Suggestions.Count}");

            var tempDirectory = Path.Combine(Path.GetTempPath(), "ytools-selftest-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempDirectory);
            try
            {
                File.WriteAllText(Path.Combine(tempDirectory, "sample.txt"), "hello");
                var navigation = new FileNavigationModule();
                var navigationResults = navigation.Results(
                    tempDirectory + "\\",
                    showsHiddenFiles: false,
                    Models.FileNavigationSort.Name,
                    ascending: true,
                    foldersFirst: true);
                Check("fileNavigation.listing", navigationResults.Count > 0);
            }
            finally
            {
                try
                {
                    Directory.Delete(tempDirectory, recursive: true);
                }
                catch
                {
                    // Best-effort cleanup.
                }
            }

            var everything = EverythingClient.TryCreate();
            Console.WriteLine(
                everything?.IsAvailable == true
                    ? "[INFO] Everything 引擎可用"
                    : "[INFO] Everything 未安装，将使用内置文件名扫描");
            everything?.Dispose();
        }
        catch (Exception exception)
        {
            failures.Add($"unexpected: {exception}");
            Console.WriteLine($"[FAIL] unexpected — {exception}");
        }

        Console.WriteLine();
        Console.WriteLine($"通过 {passed} 项，失败 {failures.Count} 项。");
        try
        {
            var logPath = Path.Combine(Path.GetTempPath(), "ytools-selftest.log");
            File.WriteAllText(
                logPath,
                $"通过 {passed} 项，失败 {failures.Count} 项。{Environment.NewLine}{string.Join(Environment.NewLine, failures)}");
        }
        catch
        {
            // The log file is best-effort diagnostics.
        }

        return failures.Count == 0 ? 0 : 1;
    }

    private static bool Throws<T>(Action action)
        where T : Exception
    {
        try
        {
            action();
            return false;
        }
        catch (T)
        {
            return true;
        }
    }

    private static void AttachConsole()
    {
        if (!AttachConsole(0xFFFFFFFF))
        {
            _ = AllocConsole();
        }

        try
        {
            Console.OutputEncoding = Encoding.UTF8;
        }
        catch
        {
            // Console encoding is best-effort.
        }
    }

    [DllImport("kernel32.dll")]
    private static extern bool AttachConsole(uint dwProcessId);

    [DllImport("kernel32.dll")]
    private static extern bool AllocConsole();
}
