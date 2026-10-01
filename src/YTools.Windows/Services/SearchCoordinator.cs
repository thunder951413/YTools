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
    IReadOnlyList<string> CustomApplicationPaths,
    IReadOnlyList<RegisteredSearchModule> RequestModules,
    CancellationToken CancellationToken,
    long Generation = 0);

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
            new(new SettingsModule(), SearchContentType.SystemTools, new ModuleResultPolicy()),
            new(new TextStatisticsModule(), SearchContentType.TextTools, new ModuleResultPolicy())
        };
        standards.AddRange((personalModules ?? []).Select(module =>
            new RegisteredSearchModule(module, SearchContentType.TextTools, new ModuleResultPolicy())));
        _standardModules = standards;
    }

    public Task PrepareAsync()
    {
        return Task.Run(() => _applications.Prepare());
    }

    public async Task<IReadOnlyList<LauncherResult>> SearchAsync(BackgroundSearchRequest request,
        Func<IReadOnlyList<LauncherResult>, Task>? onUpdate = null)
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
            cancellationToken.ThrowIfCancellationRequested();
            var sanitized = Sanitize(
                results,
                descriptor,
                new ModuleResultPolicy(
                    allowedCapabilities: new HashSet<ModuleCapability> { ModuleCapability.LocalFileRead }));
            if (onUpdate is not null) { await onUpdate(sanitized); }
            return sanitized;
        }

        var tasks = new List<Task<IReadOnlyList<LauncherResult>>>();
        if (request.EnabledContentTypes.Contains(SearchContentType.Applications))
        {
            tasks.Add(Task.Run(
                () => SearchApplications(
                    request.Query,
                    request.ApplicationAliases,
                    request.CustomApplicationPaths,
                    cancellationToken),
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
                () => SearchModule(registration.Module, request.Query, policy, cancellationToken),
                cancellationToken));
        }

        var combined = new List<LauncherResult>();
        while (tasks.Count > 0)
        {
            var completed = await Task.WhenAny(tasks).WaitAsync(cancellationToken);
            tasks.Remove(completed);
            var results = await completed;
            cancellationToken.ThrowIfCancellationRequested();
            combined.AddRange(results);
            if (results.Count > 0 && onUpdate is not null)
            { await onUpdate(combined.ToArray()); }
        }
        return combined;
    }

    private IReadOnlyList<LauncherResult> SearchApplications(
        string query,
        IReadOnlyDictionary<string, string> aliases,
        IReadOnlyList<string> customApplicationPaths,
        CancellationToken cancellationToken)
    {
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            var descriptor = new ModuleDescriptor(
                "applications",
                "应用程序",
                new HashSet<ModuleCapability>
                {
                    ModuleCapability.LocalFileRead,
                    ModuleCapability.ApplicationLaunch
                });
            var results = _applications.Search(query, aliases, customApplicationPaths);
            cancellationToken.ThrowIfCancellationRequested();
            return Sanitize(
                results,
                descriptor,
                new ModuleResultPolicy(
                    allowedCapabilities: new HashSet<ModuleCapability>
                    {
                        ModuleCapability.LocalFileRead,
                        ModuleCapability.ApplicationLaunch
                    }));
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            // One provider must never blank the whole result set.
            return [];
        }
    }

    private static async Task<IReadOnlyList<LauncherResult>> SearchModule(
        IYToolsModule module,
        string query,
        ModuleResultPolicy policy,
        CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(2));
        try
        {
            var request = new ModuleSearchRequest(query, 40, timeout.Token);
            var results = await module.SearchAsync(request).WaitAsync(timeout.Token);
            cancellationToken.ThrowIfCancellationRequested();
            return results
                .Take(request.MaximumResults)
                .Select(result => policy.Sanitize(result, module.Descriptor))
                .Where(result => result is not null)
                .Cast<LauncherResult>()
                .ToList();
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
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
