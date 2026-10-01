namespace YTools.Core;

public enum DiagnosticPlatform { MacOS, Windows }
public enum DiagnosticFileBackend { Spotlight, Everything, FileNameScan }
/// <summary>Only aggregate counts, fixed enums and health flags enter the report.</summary>
public static class LocalDiagnosticReport
{
    public static string Text(string version, DiagnosticPlatform platform, DiagnosticFileBackend backend,
        int historyCount, int pinnedCount, int snippetCount, bool preferencesHealthy, bool clipboardHealthy,
        bool snippetsHealthy, bool recentDocumentsHealthy, bool cloudEnabled)
    {
        var safeVersion = Version.TryParse(version, out var parsed) ? parsed.ToString() : "开发版";
        var backendName = backend switch { DiagnosticFileBackend.Spotlight => "Spotlight", DiagnosticFileBackend.Everything => "Everything", _ => "本机文件名扫描" };
        return $"YTools 本机诊断\n版本：{safeVersion}\n平台：{(platform == DiagnosticPlatform.Windows ? "Windows" : "macOS")}\n文件搜索：{backendName}"
            + $"\n剪贴板记录：{Math.Max(0, historyCount)}；固定：{Math.Max(0, pinnedCount)}\n文本片段：{Math.Max(0, snippetCount)}"
            + $"\n偏好存储：{Health(preferencesHealthy)}\n剪贴板存储：{Health(clipboardHealthy)}\n片段存储：{Health(snippetsHealthy)}\n最近文档存储：{Health(recentDocumentsHealthy)}"
            + $"\n坚果云同步：{(cloudEnabled ? "已启用" : "已关闭")}\n此报告不含路径、查询、剪贴板内容、应用名称或凭据。";
    }
    private static string Health(bool healthy) => healthy ? "正常" : "需处理";
}
