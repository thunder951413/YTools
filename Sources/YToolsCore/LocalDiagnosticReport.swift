import Foundation

/// Only aggregate counts, fixed enums and health flags enter the report.
public struct LocalDiagnosticReport: Sendable {
    public enum Platform: String, Sendable { case macOS, windows = "Windows" }
    public enum Backend: String, Sendable { case spotlight = "Spotlight", everything = "Everything", fileNameScan = "本机文件名扫描" }
    public static func text(version: String, platform: Platform, backend: Backend, historyCount: Int, pinnedCount: Int,
                            snippetCount: Int, preferencesHealthy: Bool, clipboardHealthy: Bool, snippetsHealthy: Bool,
                            recentDocumentsHealthy: Bool, cloudEnabled: Bool) -> String {
        let safeVersion = !version.isEmpty && version.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) ? version : "开发版"
        return """
        YTools 本机诊断
        版本：\(safeVersion)
        平台：\(platform.rawValue)
        文件搜索：\(backend.rawValue)
        剪贴板记录：\(max(0, historyCount))；固定：\(max(0, pinnedCount))
        文本片段：\(max(0, snippetCount))
        偏好存储：\(preferencesHealthy ? "正常" : "需处理")
        剪贴板存储：\(clipboardHealthy ? "正常" : "需处理")
        片段存储：\(snippetsHealthy ? "正常" : "需处理")
        最近文档存储：\(recentDocumentsHealthy ? "正常" : "需处理")
        坚果云同步：\(cloudEnabled ? "已启用" : "已关闭")
        此报告不含路径、查询、剪贴板内容、应用名称或凭据。
        """
    }
}
