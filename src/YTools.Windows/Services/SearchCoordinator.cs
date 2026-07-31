using YTools.Models;
using YTools.ModuleKit;
using YTools.Services.Modules;

namespace YTools.Services;

public sealed record RegisteredSearchModule(
    IYToolsModule Module,
    SearchContentType ContentType,
    ModuleResultPolicy Policy);

public sealed record BackgroundSearchRequest(
    string Query,
    bool FileNavigationActive,
    bool ShowsHiddenFiles,
    FileNavigationSort FileNavigationSort,
    bool FileNavigationSortAscending,
    bool FileNavigationFoldersFirst,
    IReadOnlySet<SearchContentType> EnabledContentTypes,
    IReadOnlyDictionary<string, string> ApplicationAliases,
    IReadOnlyList<string> SearchScopePaths,
    int MaximumSearchResults,
    bool IncludeFilesInDefaultResults,
    IReadOnlyList<RegisteredSearchModule> RequestModules,
    CancellationToken CancellationToken);

/// <summary>
/// Owns every non-file query provider. All results—including trusted
/// built-ins—cross the same descriptor, capability, field and action policy.
/// </summary>
public sealed class SearchCoordinator
{
    private readonly ApplicationIndexService _applications = new();
    private readonly FileNavigationModule _fileNavigation = new();
    private readonly IReadOnlyList<RegisteredSearchModule> _standardModules;

    public SearchCoordinator(
        SpellingService spelling,
        IReadOnlyList<IYToolsModule>? personalModules = null)
    {
        var standards = new List<RegisteredSearchModule>
        {
            new(new CalculatorModule(), SearchContentType.Calculations, new ModuleResultPolicy()),
            new(new UnitConversionModule(), SearchContentType.Calculations, new ModuleResultPolicy()),
            new(new SpellingModule(spelling), SearchContentType.Dictionary, new ModuleResultPolicy()),
            new(new SettingsModule(), SearchContentType.SystemTools, new ModuleResultPolicy())
        };
        standards.AddRange((personalModules ?? []).Select(module =>
            new RegisteredSearchModule(module, SearchContentType.TextTools, new ModuleResultPolicy())));
        _standardModules = standards;
    }

    public Task PrepareAsync()
    {
        return Task.Run(() => _applications.Prepare());
    }

    public async Task<IReadOnlyList<LauncherResult>> SearchAsync(BackgroundSearchRequest request)
    {
        var cancellationToken = request.CancellationToken;
        if (request.FileNavigationActive)
        {
            if (!request.EnabledContentTypes.Contains(SearchContentType.Files))
            {
                return [];
            }

            var descriptor = new ModuleDescriptor(
                "file-navigation",
                "文件导航",
                new HashSet<ModuleCapability> { ModuleCapability.LocalFileRead });
            var results = await Task.Run(
                () => _fileNavigation.Results(
                    request.Query,
                    request.ShowsHiddenFiles,
                    request.FileNavigationSort,
                    request.FileNavigationSortAscending,
                    request.FileNavigationFoldersFirst),
                cancellationToken);
            return Sanitize(
                results,
                descriptor,
                new ModuleResultPolicy(
                    allowedCapabilities: new HashSet<ModuleCapability> { ModuleCapability.LocalFileRead }));
        }

        var tasks = new List<Task<IReadOnlyList<LauncherResult>>>();
        if (request.EnabledContentTypes.Contains(SearchContentType.Applications))
        {
            tasks.Add(Task.Run(
                () => SearchApplications(request.Query, request.ApplicationAliases),
                cancellationToken));
        }

        foreach (var registration in _standardModules.Concat(request.RequestModules))
        {
            if (!request.EnabledContentTypes.Contains(registration.ContentType))
            {
                continue;
            }

            var policy = registration.Policy;
            var descriptor = registration.Module.Descriptor;
            if (!policy.Permits(descriptor))
            {
                continue;
            }

            tasks.Add(Task.Run(
                () => SearchModule(registration.Module, request.Query, policy),
                cancellationToken));
        }

        var completed = await Task.WhenAll(tasks);
        return completed.SelectMany(results => results).ToList();
    }

    private IReadOnlyList<LauncherResult> SearchApplications(
        string query,
        IReadOnlyDictionary<string, string> aliases)
    {
        var descriptor = new ModuleDescriptor(
            "applications",
            "应用程序",
            new HashSet<ModuleCapability> { ModuleCapability.LocalFileRead });
        var results = _applications.Search(query, aliases);
        return Sanitize(
            results,
            descriptor,
            new ModuleResultPolicy(
                allowedCapabilities: new HashSet<ModuleCapability> { ModuleCapability.LocalFileRead }));
    }

    private static async Task<IReadOnlyList<LauncherResult>> SearchModule(
        IYToolsModule module,
        string query,
        ModuleResultPolicy policy)
    {
        try
        {
            var request = new ModuleSearchRequest(query, 40);
            var results = await module.SearchAsync(request);
            return results
                .Take(request.MaximumResults)
                .Select(result => policy.Sanitize(result, module.Descriptor))
                .Where(result => result is not null)
                .Cast<LauncherResult>()
                .ToList();
        }
        catch
        {
            return [];
        }
    }

    private static IReadOnlyList<LauncherResult> Sanitize(
        IReadOnlyList<LauncherResult> results,
        ModuleDescriptor descriptor,
        ModuleResultPolicy policy)
    {
        return results
            .Take(40)
            .Select(result => policy.Sanitize(result, descriptor))
            .Where(result => result is not null)
            .Cast<LauncherResult>()
            .ToList();
    }

}
