import Foundation

struct ActionMenuController {
    private let registry = ActionRegistry()
    private(set) var actions: [LauncherAction] = []
    private(set) var subject: LauncherResult?
    private(set) var titleOverride: String?
    var selectedIndex = 0

    var isShowing: Bool { !actions.isEmpty }
    var title: String { titleOverride ?? subject?.title ?? "" }
    var selectedAction: LauncherAction? {
        actions.indices.contains(selectedIndex) ? actions[selectedIndex] : nil
    }

    mutating func show(for result: LauncherResult) -> Bool {
        let available = registry.actions(for: result)
        guard !available.isEmpty else { return false }
        actions = available
        subject = result
        titleOverride = nil
        selectedIndex = 0
        return true
    }

    mutating func show(forBufferedURLs urls: [URL]) -> Bool {
        let available = registry.actions(forBufferedURLs: urls)
        guard !available.isEmpty else { return false }
        actions = available
        subject = nil
        titleOverride = "\(urls.count) 个缓冲项目"
        selectedIndex = 0
        return true
    }

    mutating func moveSelection(by offset: Int) {
        guard !actions.isEmpty else { return }
        selectedIndex = (selectedIndex + offset + actions.count) % actions.count
    }

    mutating func dismiss() {
        actions = []
        subject = nil
        titleOverride = nil
        selectedIndex = 0
    }
}
