import Combine

enum PanelMode {
    case launcher
    case clipboard
}

@MainActor
final class PanelState: ObservableObject {
    @Published var mode: PanelMode = .launcher
    @Published private(set) var searchFocusRequest = 0

    func requestSearchFocus() {
        searchFocusRequest &+= 1
    }
}
