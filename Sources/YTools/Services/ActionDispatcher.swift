import AppKit
import UniformTypeIdentifiers

enum ActionExecutionOutcome {
    case hidePanel
    case keepPanel
    case navigate(String)
    case preview(URL)
    case clearFileBufferAndHide
}

@MainActor
protocol SnippetSaving: AnyObject {
    var saveError: String? { get }
    func save(text: String, title: String?, keyword: String, collection: String) -> Bool
}

extension SnippetSaving {
    func save(text: String) -> Bool {
        save(text: text, title: nil, keyword: "", collection: "默认")
    }
}

@MainActor
protocol RecentDocumentsRecording: AnyObject {
    func record(_ url: URL)
}

/// Executes the bounded native action vocabulary. LauncherModel owns selection
/// state; this object owns AppKit/System side effects and file operation errors.
@MainActor
final class ActionDispatcher {
    // Finder.sdef declares the bounded empty-trash command as `fndr/empt`.
    // Keep both codes compile-time fixed and never attach user-provided parameters.
    private static let finderEventClass: AEEventClass = 0x666E6472 // 'fndr'
    private static let finderEmptyTrashEvent: AEEventID = 0x656D7074 // 'empt'

    private let snippets: any SnippetSaving
    private let recentDocuments: any RecentDocumentsRecording
    private let fileOperations = FileOperationService()
    private let onOpenSettings: () -> Void
    private let onShowLargeType: (String) -> Void

    init(
        snippets: any SnippetSaving,
        recentDocuments: any RecentDocumentsRecording,
        onOpenSettings: @escaping () -> Void,
        onShowLargeType: @escaping (String) -> Void
    ) {
        self.snippets = snippets
        self.recentDocuments = recentDocuments
        self.onOpenSettings = onOpenSettings
        self.onShowLargeType = onShowLargeType
    }

    func execute(_ action: ResultAction) -> ActionExecutionOutcome {
        switch action {
        case let .copy(text):
            copyText(text)
        case let .openDictionary(term):
            return openDictionary(term)
        case let .open(url):
            guard url.isFileURL else {
                showAlert(title: "已阻止外部链接", message: "YTools 只允许打开本机文件和应用。")
                return .keepPanel
            }
            return openLocalURL(url)
        case let .reveal(url):
            guard url.isFileURL else { return .keepPanel }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case let .navigate(path):
            return .navigate(path)
        case let .hideApplication(bundleID):
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.hide() }
        case let .quitApplication(bundleID):
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
        case .showTrash:
            let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            NSWorkspace.shared.open(trash)
        case .emptyTrash:
            return emptyTrash()
        case .startScreenSaver:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"))
        case .sleepDisplays:
            do {
                try runFixedSystemCommand()
            } catch {
                showAlert(title: "无法关闭显示器", message: error.localizedDescription)
                return .keepPanel
            }
        case .openFocusSettings:
            return openSystemSettingsPane("com.apple.Focus-Settings.extension")
        case .openAppearanceSettings:
            return openSystemSettingsPane("com.apple.Appearance-Settings.extension")
        case .openSettings:
            onOpenSettings()
        case .none:
            return .keepPanel
        }
        return .hidePanel
    }

    func execute(_ kind: LauncherActionKind) -> ActionExecutionOutcome {
        switch kind {
        case let .perform(action):
            return execute(action)
        case let .copyPath(url):
            copyText(url.path)
        case let .copyText(text):
            copyText(text)
        case let .largeType(text):
            onShowLargeType(text)
        case let .saveSnippet(text):
            guard snippets.save(text: text) else {
                showAlert(title: "无法保存文本片段", message: snippets.saveError ?? "加密存储当前不可用。")
                return .keepPanel
            }
            NSSound(named: "Glass")?.play()
        case let .preview(url):
            return .preview(url)
        case let .openWith(url):
            return openWithApplication(url)
        case let .copyFile(url):
            return beginFileOperation(.copy, source: url)
        case let .moveFile(url):
            return beginFileOperation(.move, source: url)
        case let .trash(url):
            return moveToTrash(url)
        case let .openMany(urls):
            let failed = urls.filter {
                !FileManager.default.fileExists(atPath: $0.path) || !NSWorkspace.shared.open($0)
            }
            guard failed.isEmpty else {
                showBatchFailure(title: "部分项目无法打开", failed: failed)
                return .keepPanel
            }
            return .clearFileBufferAndHide
        case let .revealMany(urls):
            let failed = urls.filter { !FileManager.default.fileExists(atPath: $0.path) }
            guard failed.isEmpty else {
                showBatchFailure(title: "部分项目已不存在", failed: failed)
                return .keepPanel
            }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            return .clearFileBufferAndHide
        case let .copyPaths(urls):
            copyText(urls.map(\.path).joined(separator: "\n"))
        }
        return .hidePanel
    }

    func reveal(_ url: URL) {
        guard url.isFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPath(_ url: URL) {
        copyText(url.path)
    }

    private func openLocalURL(_ url: URL) -> ActionExecutionOutcome {
        guard FileManager.default.fileExists(atPath: url.path) else {
            showAlert(title: "项目已不存在", message: url.path)
            return .keepPanel
        }

        if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
                guard let error else { return }
                Task { @MainActor [weak self] in
                    self?.showAlert(title: "无法启动应用", message: error.localizedDescription)
                }
            }
            return .hidePanel
        }

        guard NSWorkspace.shared.open(url) else {
            showAlert(title: "无法打开项目", message: url.path)
            return .keepPanel
        }
        recentDocuments.record(url)
        return .hidePanel
    }

    private func beginFileOperation(
        _ operation: FileOperationService.Operation,
        source: URL
    ) -> ActionExecutionOutcome {
        guard source.isFileURL, FileManager.default.fileExists(atPath: source.path) else {
            showAlert(title: "项目已不存在", message: source.path)
            return .keepPanel
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = operation == .move ? "移动到这里" : "复制到这里"
        guard panel.runModal() == .OK, let directory = panel.url else { return .keepPanel }

        Task { [weak self, fileOperations] in
            do {
                try await fileOperations.perform(operation, source: source, destinationDirectory: directory)
            } catch {
                self?.showAlert(
                    title: operation == .move ? "移动失败" : "复制失败",
                    message: error.localizedDescription
                )
            }
        }
        return .hidePanel
    }

    private func openWithApplication(_ url: URL) -> ActionExecutionOutcome {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            showAlert(title: "项目已不存在", message: url.path)
            return .keepPanel
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "使用此应用打开"
        guard panel.runModal() == .OK, let applicationURL = panel.url else { return .keepPanel }
        recentDocuments.record(url)
        Task { [weak self] in
            do {
                try await NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: applicationURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
            } catch {
                self?.showAlert(title: "无法打开文件", message: error.localizedDescription)
            }
        }
        return .hidePanel
    }

    private func moveToTrash(_ url: URL) -> ActionExecutionOutcome {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            showAlert(title: "项目已不存在", message: url.path)
            return .keepPanel
        }
        let alert = NSAlert()
        alert.messageText = "将“\(url.lastPathComponent)”移入废纸篓？"
        alert.informativeText = "YTools 不会永久删除项目。你仍可从访达废纸篓恢复。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移入废纸篓")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return .keepPanel }
        NSWorkspace.shared.recycle([url]) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                self?.showAlert(title: "无法移入废纸篓", message: error.localizedDescription)
            }
        }
        return .hidePanel
    }

    private func emptyTrash() -> ActionExecutionOutcome {
        let alert = NSAlert()
        alert.messageText = "永久清空废纸篓？"
        alert.informativeText = "Finder 将永久删除所有磁盘卷废纸篓中的项目，此操作无法撤销。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "清空废纸篓")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return .keepPanel }

        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        guard let targetDescriptor = target.aeDesc else {
            showAlert(title: "无法连接 Finder", message: "无法创建受控的 Finder 请求。")
            return .keepPanel
        }

        let permission = AEDeterminePermissionToAutomateTarget(
            targetDescriptor,
            Self.finderEventClass,
            Self.finderEmptyTrashEvent,
            true
        )
        guard permission == noErr else {
            let message = permission == errAEEventNotPermitted
                ? "请在“系统设置 → 隐私与安全性 → 自动化”中允许 YTools 控制 Finder。"
                : "Finder 自动化请求失败（错误 \(permission)）。"
            showAlert(title: "无法清空废纸篓", message: message)
            return .keepPanel
        }

        let event = NSAppleEventDescriptor(
            eventClass: Self.finderEventClass,
            eventID: Self.finderEmptyTrashEvent,
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        do {
            _ = try event.sendEvent(options: [.noReply, .canInteract], timeout: 10)
        } catch {
            showAlert(title: "无法清空废纸篓", message: error.localizedDescription)
            return .keepPanel
        }
        return .hidePanel
    }

    private func openSystemSettingsPane(_ identifier: String) -> ActionExecutionOutcome {
        guard let url = URL(string: "x-apple.systempreferences:\(identifier)"),
              NSWorkspace.shared.open(url) else {
            showAlert(title: "无法打开系统设置", message: "当前 macOS 版本不支持该设置面板。")
            return .keepPanel
        }
        return .hidePanel
    }

    private func openDictionary(_ term: String) -> ActionExecutionOutcome {
        let allowed = CharacterSet.urlHostAllowed.subtracting(.init(charactersIn: "/?#"))
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "dict://\(encoded)"),
              url.scheme == "dict",
              NSWorkspace.shared.open(url) else {
            showAlert(title: "无法打开系统词典", message: "Dictionary 当前无法查询“\(term)”。")
            return .keepPanel
        }
        return .hidePanel
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func runFixedSystemCommand() throws {
        let executable = "/usr/bin/pmset"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["displaysleepnow"]
        try process.run()
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func showBatchFailure(title: String, failed: [URL]) {
        let names = failed.prefix(8).map(\.lastPathComponent).joined(separator: "\n")
        let remainder = failed.count > 8 ? "\n另有 \(failed.count - 8) 项" : ""
        showAlert(
            title: title,
            message: "失败项目仍保留在文件缓冲区：\n\(names)\(remainder)"
        )
    }
}
