import Foundation
import SQLite3

struct AlfredClipboardRecord: Sendable {
    let text: String
    let sourceApplication: String?
}

enum AlfredClipboardImportError: LocalizedError, Sendable {
    case databaseMissing
    case databaseOpenFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseMissing:
            "未找到 Alfred 剪贴板数据库。"
        case let .databaseOpenFailed(message):
            "无法只读打开 Alfred 剪贴板数据库：\(message)"
        case let .queryFailed(message):
            "无法读取 Alfred 剪贴板记录：\(message)"
        }
    }
}

actor AlfredClipboardImportService {
    nonisolated static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Alfred/Databases/clipboard.alfdb")
    }

    func loadTextRecords() throws -> [AlfredClipboardRecord] {
        let url = Self.databaseURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AlfredClipboardImportError.databaseMissing
        }

        var database: OpaquePointer?
        let openStatus = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard openStatus == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite open error"
            if let database { sqlite3_close(database) }
            throw AlfredClipboardImportError.databaseOpenFailed(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 2_000)

        let sql = "SELECT item, app FROM clipboard WHERE dataType = 0 ORDER BY ts DESC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw AlfredClipboardImportError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        var records: [AlfredClipboardRecord] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else {
                throw AlfredClipboardImportError.queryFailed(String(cString: sqlite3_errmsg(database)))
            }
            guard let textPointer = sqlite3_column_text(statement, 0) else { continue }
            let text = String(cString: textPointer)
            let sourceApplication = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            records.append(AlfredClipboardRecord(
                text: text,
                sourceApplication: sourceApplication?.isEmpty == false ? sourceApplication : "Alfred"
            ))
        }
        return records
    }
}
