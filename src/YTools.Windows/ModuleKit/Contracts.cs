using System.IO;
using YTools.Core;

namespace YTools.ModuleKit;

public enum ModuleCapability
{
    LocalFileRead,
    ApplicationLaunch,
    ClipboardRead,
    ContactsRead,
    CalendarRead
}

public sealed record ModuleDescriptor(
    string Id,
    string Name,
    IReadOnlySet<ModuleCapability> Capabilities)
{
    public ModuleDescriptor(string id, string name)
        : this(id, name, new HashSet<ModuleCapability>())
    {
    }
}

public readonly struct ModuleSearchRequest
{
    public ModuleSearchRequest(
        string query,
        int maximumResults = 20,
        CancellationToken cancellationToken = default)
    {
        Query = query;
        MaximumResults = Math.Clamp(maximumResults, 1, 100);
        CancellationToken = cancellationToken;
    }

    public string Query { get; }

    public int MaximumResults { get; }

    public CancellationToken CancellationToken { get; }
}

/// <summary>Source-compiled personal modules implement this contract.</summary>
public interface IYToolsModule
{
    ModuleDescriptor Descriptor { get; }

    Task<IReadOnlyList<LauncherResult>> SearchAsync(ModuleSearchRequest request);
}

public abstract record ResultIcon
{
    public sealed record System(string Name) : ResultIcon;

    public sealed record Application(string Path) : ResultIcon;

    public sealed record RegisteredApplication(string AppUserModelId) : ResultIcon;

    public sealed record File(string Path) : ResultIcon;
}

/// <summary>
/// The complete action vocabulary available to a compiled module. Deliberately
/// excludes arbitrary shell commands, scripts, dynamic code and URL opening.
/// </summary>
public abstract record ResultAction
{
    public sealed record Copy(string Text) : ResultAction;

    public sealed record Open(string Path) : ResultAction;

    public sealed record ActivateApplication(string AppUserModelId) : ResultAction;

    public sealed record Reveal(string Path) : ResultAction;

    public sealed record Navigate(string Path) : ResultAction;

    /// <summary>Replaces the launcher query with the given text (calculator
    /// continuation). Purely a UI edit; never interpreted as a path or command.</summary>
    public sealed record EditQuery(string Text) : ResultAction;

    public sealed record HideApplication(string ExecutablePath) : ResultAction;

    public sealed record QuitApplication(string ExecutablePath) : ResultAction;

    public sealed record ShowTrash : ResultAction;

    public sealed record EmptyTrash : ResultAction;

    public sealed record StartScreenSaver : ResultAction;

    public sealed record SleepDisplays : ResultAction;

    public sealed record OpenFocusSettings : ResultAction;

    public sealed record OpenAppearanceSettings : ResultAction;

    public sealed record OpenSettings : ResultAction;

    public sealed record None : ResultAction;
}

public sealed record LauncherResult(
    string Id,
    string ModuleId,
    string Title,
    string Subtitle,
    ResultIcon Icon,
    int Score,
    ResultAction Action)
{
    public string? FilePath => Icon switch
    {
        ResultIcon.File file => file.Path,
        _ => null
    };

    public string? ResourcePath => Icon switch
    {
        ResultIcon.Application application => application.Path,
        ResultIcon.File file => file.Path,
        _ => null
    };

    public bool IsApplication => Icon is ResultIcon.Application or ResultIcon.RegisteredApplication;

    public LauncherResult WithScore(int newScore)
    {
        return this with { Score = newScore };
    }

    public LauncherResult HostedBy(string moduleId, int lowerBound, int upperBound)
    {
        return this with
        {
            ModuleId = moduleId,
            Score = Math.Clamp(Score, lowerBound, upperBound)
        };
    }
}

/// <summary>
/// Host-side validation for source-compiled modules. Capability declarations
/// are not trusted by themselves; the host must also grant each capability.
/// </summary>
public sealed class ModuleResultPolicy
{
    public ModuleResultPolicy(
        IReadOnlySet<ModuleCapability>? allowedCapabilities = null,
        int scoreLowerBound = -10_000,
        int scoreUpperBound = 10_000,
        bool allowsPrivilegedActions = false)
    {
        AllowedCapabilities = allowedCapabilities ?? new HashSet<ModuleCapability>();
        ScoreLowerBound = scoreLowerBound;
        ScoreUpperBound = scoreUpperBound;
        AllowsPrivilegedActions = allowsPrivilegedActions;
    }

    public IReadOnlySet<ModuleCapability> AllowedCapabilities { get; }

    public int ScoreLowerBound { get; }

    public int ScoreUpperBound { get; }

    public bool AllowsPrivilegedActions { get; }

    public bool Permits(ModuleDescriptor descriptor)
    {
        var id = descriptor.Id.Trim();
        var name = descriptor.Name.Trim();
        return !string.IsNullOrEmpty(id)
            && id.Length <= 100
            && !string.IsNullOrEmpty(name)
            && name.Length <= 200
            && descriptor.Capabilities.IsSubsetOf(AllowedCapabilities);
    }

    public LauncherResult? Sanitize(LauncherResult result, ModuleDescriptor descriptor)
    {
        if (!Permits(descriptor)
            || string.IsNullOrEmpty(result.Id)
            || result.Id.Length > 500
            || string.IsNullOrEmpty(result.Title)
            || result.Title.Length > 1_000
            || result.Subtitle.Length > 4_000
            || !Permits(result.Icon, descriptor)
            || !Permits(result.Action, descriptor))
        {
            return null;
        }

        return result.HostedBy(descriptor.Id, ScoreLowerBound, ScoreUpperBound);
    }

    private static bool Permits(ResultIcon icon, ModuleDescriptor descriptor)
    {
        switch (icon)
        {
            case ResultIcon.System system:
                return !string.IsNullOrEmpty(system.Name) && system.Name.Length <= 200;
            case ResultIcon.Application application:
                return descriptor.Capabilities.Contains(ModuleCapability.LocalFileRead)
                    && LocalPathPolicy.IsValid(application.Path);
            case ResultIcon.RegisteredApplication application:
                return descriptor.Capabilities.Contains(ModuleCapability.ApplicationLaunch)
                    && IsValidAppUserModelId(application.AppUserModelId);
            case ResultIcon.File file:
                return descriptor.Capabilities.Contains(ModuleCapability.LocalFileRead)
                    && LocalPathPolicy.IsValid(file.Path);
            default:
                return false;
        }
    }

    private bool Permits(ResultAction action, ModuleDescriptor descriptor)
    {
        switch (action)
        {
            case ResultAction.Copy copy:
                return copy.Text.Length <= 1_000_000;
            case ResultAction.None:
            case ResultAction.OpenSettings:
                return true;
            case ResultAction.Open open:
                return descriptor.Capabilities.Contains(ModuleCapability.LocalFileRead)
                    && LocalPathPolicy.IsValid(open.Path);
            case ResultAction.ActivateApplication application:
                return descriptor.Capabilities.Contains(ModuleCapability.ApplicationLaunch)
                    && IsValidAppUserModelId(application.AppUserModelId);
            case ResultAction.Reveal reveal:
                return descriptor.Capabilities.Contains(ModuleCapability.LocalFileRead)
                    && LocalPathPolicy.IsValid(reveal.Path);
            case ResultAction.Navigate navigate:
                return descriptor.Capabilities.Contains(ModuleCapability.LocalFileRead)
                    && navigate.Path.Length <= 4_096
                    && (LocalPathPolicy.IsValid(navigate.Path) || IsTildePath(navigate.Path));
            case ResultAction.EditQuery editQuery:
                return editQuery.Text.Length <= 1_000;
            case ResultAction.HideApplication hide:
                return AllowsPrivilegedActions && IsExecutablePath(hide.ExecutablePath);
            case ResultAction.QuitApplication quit:
                return AllowsPrivilegedActions && IsExecutablePath(quit.ExecutablePath);
            case ResultAction.ShowTrash:
            case ResultAction.EmptyTrash:
            case ResultAction.StartScreenSaver:
            case ResultAction.SleepDisplays:
            case ResultAction.OpenFocusSettings:
            case ResultAction.OpenAppearanceSettings:
                return AllowsPrivilegedActions;
            default:
                return false;
        }
    }

    private static bool IsValidAppUserModelId(string value)
    {
        return !string.IsNullOrWhiteSpace(value)
            && value.Length <= 512
            && value.All(character => !char.IsControl(character));
    }

    private static bool IsExecutablePath(string path)
    {
        return LocalPathPolicy.IsValid(path)
            && Path.GetExtension(path).Equals(".exe", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsTildePath(string path)
    {
        return path == "~"
            || path.StartsWith("~/", StringComparison.Ordinal)
            || path.StartsWith("~\\", StringComparison.Ordinal);
    }
}
