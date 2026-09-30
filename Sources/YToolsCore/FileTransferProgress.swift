import Foundation

public struct FileTransferProgress: Sendable, Equatable {
    public enum Phase: Sendable { case scanning, copying, committing, completed }
    public let completedBytes: Int64
    public let totalBytes: Int64
    public let phase: Phase
    public init(completedBytes: Int64, totalBytes: Int64, phase: Phase) {
        self.totalBytes = max(0, totalBytes)
        self.completedBytes = min(max(0, completedBytes), max(0, totalBytes))
        self.phase = phase
    }
    public var percentage: Int { totalBytes > 0 ? Int(Double(completedBytes) / Double(totalBytes) * 100) : (phase == .completed ? 100 : 0) }
    public var detail: String {
        switch phase {
        case .scanning: return "正在统计文件…"
        case .committing: return "正在提交文件…"
        case .completed: return "已完成"
        case .copying:
            return "\(percentage)% · \(ByteCountFormatter.string(fromByteCount: completedBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
        }
    }
}
