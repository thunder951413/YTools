import SwiftUI

struct PanelRootView: View {
    @ObservedObject var state: PanelState
    @ObservedObject var launcher: LauncherModel
    @ObservedObject var clipboard: ClipboardHistoryManager
    @ObservedObject var preferences: AppPreferences
    let onHide: () -> Void

    var body: some View {
        Group {
            switch state.mode {
            case .launcher:
                LauncherView(
                    model: launcher,
                    preferences: preferences,
                    searchFocusRequest: state.searchFocusRequest,
                    onActivate: onHide
                )
            case .clipboard:
                ClipboardHistoryView(
                    manager: clipboard,
                    preferences: preferences,
                    searchFocusRequest: state.searchFocusRequest,
                    onActivate: onHide
                )
            }
        }
        .id(state.mode)
        .tint(preferences.accentColor.color)
    }
}
