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

            Check("paths.rejectDriveRelative", !LocalPathPolicy.IsValid(@"C:notes.txt"));
            Check("paths.rejectUnc", !LocalPathPolicy.IsValid(@"\\server\share\notes.txt"));
            Check("paths.acceptLocalAbsolute", LocalPathPolicy.IsValid(@"C:\Users\Example\notes.txt"));
            var historyId = Guid.NewGuid();
            var currentHistory = new YTools.Models.ClipboardHistoryItem(historyId, YTools.Models.ClipboardItemKind.Text,
                ["self-test"], DateTimeOffset.FromUnixTimeSeconds(100), null, UpdatedAt: DateTimeOffset.FromUnixTimeSeconds(300));
            var staleDelete = ClipboardCloudSyncService.ClipboardCloudEvent.Delete(1, Guid.NewGuid(), [historyId], DateTimeOffset.FromUnixTimeSeconds(200));
            Check("clipboard.rejectStaleDelete", ClipboardCloudSyncService.ApplyEvents([currentHistory], [staleDelete]).Count == 1);
            var oldUpsert = ClipboardCloudSyncService.ClipboardCloudEvent.Upsert(2, Guid.NewGuid(), currentHistory);
            Check("clipboard.persistedTombstone", ClipboardCloudSyncService.ApplyEvents([], [oldUpsert],
                new Dictionary<Guid, DateTimeOffset> { [historyId] = DateTimeOffset.FromUnixTimeSeconds(400) }).Count == 0);

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
                router.Command(new PanelKeyEvent(0x31, PanelKeyModifiers.Command), PanelInputMode.Launcher)?.Payload
                    == 0
                && router.Command(new PanelKeyEvent(0x30, PanelKeyModifiers.Command), PanelInputMode.Launcher)?.Payload
                    == 9);
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

            const string registeredAppId = "Contoso.Sample_123!App";
            var applicationCapabilities = new HashSet<ModuleCapability> { ModuleCapability.ApplicationLaunch };
            var applicationPolicy = new ModuleResultPolicy(allowedCapabilities: applicationCapabilities);
            var applicationModule = new ModuleDescriptor("applications", "应用程序", applicationCapabilities);
            var registeredApplication = new LauncherResult(
                $"application:registered:{registeredAppId}",
                "applications",
                "Sample",
                "Microsoft Store 应用",
                new ResultIcon.RegisteredApplication(registeredAppId),
                900,
                new ResultAction.ActivateApplication(registeredAppId));
            Check(
                "policy.registeredApplication",
                applicationPolicy.Sanitize(registeredApplication, applicationModule) is not null);

            var clipboardPolicy = new ClipboardTextPolicy(100);
            Check("clipboardPolicy.limit", !clipboardPolicy.ShouldStore(new string('a', 101)));

            var placement = RelativePanelPlacement.Create(0.25, 0.5, 800, 600);
            Check(
                "placement.roundTrip",
                placement is { } value && value.ResolvedLeft(0, 800) == 200 && value.ResolvedTop(0, 600) == 300);

            var calculatorModule = new CalculatorModule();
            var calculatorResults = calculatorModule.SearchAsync(new ModuleSearchRequest("1+2", 5)).GetAwaiter().GetResult();
            Check("module.calculator", calculatorResults.Count == 1 && calculatorResults[0].Title == "3");

            // Regression: the "=" continuation result must survive the host-side
            // result policy instead of being silently dropped.
            var continuationResults = calculatorModule.SearchAsync(new ModuleSearchRequest("1+2=", 5)).GetAwaiter().GetResult();
            Check(
                "module.calculatorContinuation",
                continuationResults.Count == 1
                && continuationResults[0].Action is ResultAction.EditQuery
                && new ModuleResultPolicy().Sanitize(continuationResults[0], calculatorModule.Descriptor) is not null);

            var unitModule = new UnitConversionModule();
            var unitResults = unitModule.SearchAsync(new ModuleSearchRequest("1 km to m", 5)).GetAwaiter().GetResult();
            Check("module.unitConversion", unitResults.Count == 1 && unitResults[0].Title == "1000 m");

            var textStats = new TextStatisticsModule();
            var statsResults = textStats.SearchAsync(new ModuleSearchRequest("统计 hello world", 5)).GetAwaiter().GetResult();
            Check("module.textStatistics", statsResults.Count == 1 && statsResults[0].Title.Contains("字符"));

            var searchFixture = Path.Combine(Path.GetTempPath(), "ytools-selftest-search-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(searchFixture);
            try
            {
                var fixtureApp = Path.Combine(searchFixture, "YTools SelfTest.exe");
                File.WriteAllText(fixtureApp, "fixture");
                var applicationIndex = new ApplicationIndexService(
                    [searchFixture],
                    Path.Combine(searchFixture, "WindowsApps"),
                    includesRegisteredApplications: false);
                applicationIndex.Prepare();
                var applicationResults = applicationIndex.Search("selftest", new Dictionary<string, string>());
                Check("applications.index", applicationResults.Count > 0);

                var fixtureFile = Path.Combine(searchFixture, "selftest-document.txt");
                File.WriteAllText(fixtureFile, "fixture");
                using var fileSearch = new FileSearchService(enableEverything: false);
                IReadOnlyList<LauncherResult> fileResults = [];
                for (var attempt = 0; attempt < 20 && fileResults.Count == 0; attempt++)
                {
                    fileResults = fileSearch.SearchAsync(
                        "selftest-document",
                        FileSearchMode.Default,
                        [searchFixture],
                        5,
                        CancellationToken.None).GetAwaiter().GetResult();
                    if (fileResults.Count == 0)
                    {
                        Thread.Sleep(25);
                    }
                }
                Check("files.index", fileResults.Count > 0);
            }
            finally
            {
                try
                {
                    Directory.Delete(searchFixture, recursive: true);
                }
                catch
                {
                    // Best-effort cleanup.
                }
            }

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
            var ipcTestPath = @"C:\Tools\YTools.exe";
            var ipcText = Encoding.Unicode.GetBytes(ipcTestPath + '\0');
            var ipcBuffer = new byte[28 + sizeof(uint) + ipcText.Length];
            BitConverter.GetBytes(1u).CopyTo(ipcBuffer, 0);
            BitConverter.GetBytes(1u).CopyTo(ipcBuffer, 4);
            BitConverter.GetBytes(4u).CopyTo(ipcBuffer, 12);
            BitConverter.GetBytes(1u).CopyTo(ipcBuffer, 16);
            BitConverter.GetBytes(28u).CopyTo(ipcBuffer, 24);
            BitConverter.GetBytes((uint)ipcTestPath.Length).CopyTo(ipcBuffer, 28);
            ipcText.CopyTo(ipcBuffer, 32);
            Check(
                "everything.ipcParser",
                EverythingClient.ParseResultBuffer(ipcBuffer).SequenceEqual([ipcTestPath]));
            Console.WriteLine(
                everything is null
                    ? "[INFO] Everything 未运行，将使用内置文件名扫描"
                    : $"[INFO] Everything 状态={everything.AvailabilityStatus} PID={everything.EverythingProcessId}，" +
                        (everything.IsAvailable ? "使用本机 IPC" : "使用内置文件名扫描"));
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
