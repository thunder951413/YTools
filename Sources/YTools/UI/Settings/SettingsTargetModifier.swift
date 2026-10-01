import SwiftUI
import YToolsCore

private struct SettingsTargetKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var highlightedSetting: String? {
        get { self[SettingsTargetKey.self] }
        set { self[SettingsTargetKey.self] = newValue }
    }
}
private struct SettingsTargetModifier: ViewModifier {
    let id: String
    @Environment(\.highlightedSetting) private var highlighted
    func body(content: Content) -> some View {
        content.id(id).accessibilityIdentifier("setting-" + id)
            .background(RoundedRectangle(cornerRadius: 6).fill(highlighted == id ? Color.accentColor.opacity(0.14) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(highlighted == id ? Color.accentColor : .clear, lineWidth: 2))
    }
}
extension View {
    func settingsTarget(_ id: String) -> some View { modifier(SettingsTargetModifier(id: id)) }
}
