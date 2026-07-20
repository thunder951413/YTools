import AppKit
import SwiftUI

@MainActor
final class FileImporterPresentation: ObservableObject {
    @Published var isPresented = false
}

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.headline)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07)))
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

struct PrivacyLine: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct LauncherAppearancePreview: View {
    @ObservedObject var preferences: AppPreferences

    private var style: LauncherAppearanceStyle { preferences.launcherAppearanceStyle }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text("calendar")
                    .font(.system(size: max(17, style.searchFontSize - 5), weight: .medium))
                Spacer()
            }
            .padding(style == .minimal || style == .classic ? 13 : 16)
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "calendar").font(.title2).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("日历").font(.headline)
                    if preferences.showSubtitles {
                        Text("/System/Applications/Calendar.app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("↩").foregroundStyle(.secondary)
            }
            .padding(preferences.compactResults ? 10 : 15)
            .background(Color.accentColor.opacity(style.selectionOpacity))
            if style.showsFooter {
                Divider()
                HStack {
                    Text("↑↓ 选择   ↩ 执行   → 动作")
                    Spacer()
                    Text("⌘Space")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 26)
            }
        }
        .background(style.backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.primary.opacity(0.08)))
    }
}
