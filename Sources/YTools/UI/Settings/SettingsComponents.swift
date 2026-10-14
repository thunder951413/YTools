import AppKit
import SwiftUI
import YToolsCore

@MainActor
final class FileImporterPresentation: ObservableObject {
    @Published var isPresented = false
}

// MARK: - Layout primitives (System Settings–style grouped cards)

/// Rounded colored square with a white SF Symbol, used in the sidebar and page header.
struct SettingsTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

struct NewBadge: View {
    var body: some View {
        Text("新")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
            .accessibilityLabel("新功能")
    }
}

/// A titled group: small heading above a rounded card. Rows inside are
/// separated with `SettingsDivider()`.
struct SettingsGroup<Content: View>: View {
    let title: String
    var isNew = false
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !title.isEmpty {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if isNew { NewBadge() }
                }
                .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.78),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.07)))
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 14)
    }
}

/// Title (and optional detail) on the left, control on the right.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var isNew = false
    var target: String?
    let trailing: Trailing

    init(title: String, detail: String? = nil, isNew: Bool = false, target: String? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.isNew = isNew
        self.target = target
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    if isNew { NewBadge() }
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 44)
        .settingsTarget(target ?? SettingsSearchCatalog.targetID(forRowTitle: title) ?? "row:" + title)
    }
}

/// A row whose control is a switch bound to `isOn`.
struct SettingsToggleRow: View {
    let title: String
    var detail: String?
    var isNew = false
    var target: String?
    @Binding var isOn: Bool

    init(_ title: String, detail: String? = nil, isNew: Bool = false, target: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self.isNew = isNew
        self.target = target
        _isOn = isOn
    }

    var body: some View {
        SettingsRow(title: title, detail: detail, isNew: isNew, target: target) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

/// Explanatory text with an optional action button at the end of a group.
struct SettingsNoteRow<Trailing: View>: View {
    let text: String
    let trailing: Trailing

    init(_ text: String, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

extension SettingsNoteRow where Trailing == EmptyView {
    init(_ text: String) {
        self.init(text) { EmptyView() }
    }
}

/// A list item: optional leading view, title + subtitle, trailing accessories.
struct SettingsListItem<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var monospaced = false
    let leading: Leading
    let trailing: Trailing

    init(title: String, subtitle: String? = nil, monospaced: Bool = false,
         @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.monospaced = monospaced
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(monospaced ? .system(size: 12, design: .monospaced) : .body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(minHeight: 40)
    }
}

extension SettingsListItem where Leading == EmptyView {
    init(title: String, subtitle: String? = nil, monospaced: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, monospaced: monospaced, leading: { EmptyView() }, trailing: trailing)
    }
}

struct SettingsEmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
    }
}

struct RemoveButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button("移除", action: action)
            .controlSize(.small)
            .accessibilityLabel(label)
    }
}

/// Small colored status label such as "● 已授权".
struct StatusPill: View {
    enum Tone { case positive, warning, neutral }
    let text: String
    let tone: Tone

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tone == .neutral ? Color.secondary : color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch tone {
        case .positive: .green
        case .warning: .orange
        case .neutral: .secondary
        }
    }
}

/// − value + control used for counts and lengths.
struct SettingsStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    let format: (Int) -> String

    var body: some View {
        HStack(spacing: 8) {
            Text(format(value))
                .monospacedDigit()
                .frame(minWidth: 54, alignment: .trailing)
            Stepper(format(value), value: $value, in: range, step: step)
                .labelsHidden()
        }
    }
}

/// Slider with a fixed-width value label.
struct SettingsSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: $value, in: range, step: step)
                .frame(width: 170)
            Text(label)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
    }
}

func abbreviatedHomePath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    guard path == home || path.hasPrefix(home + "/") else { return path }
    return "~" + path.dropFirst(home.count)
}

// MARK: - Legacy card (kept for component snapshots and compact layouts)

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
                Text("日历")
                    .font(.system(size: max(17, style.searchFontSize - 5), weight: .medium))
                Spacer()
            }
            .padding(style == .minimal || style == .classic ? 13 : 16)
            Divider()
            previewRow(icon: "calendar", title: "日历", subtitle: "/System/Applications/Calendar.app",
                       key: "↩", selected: true)
            previewRow(icon: "doc", title: "日历.ics", subtitle: "~/Downloads",
                       key: preferences.showNumberShortcuts ? "⌘2" : "", selected: false)
            if style.showsFooter {
                Divider()
                HStack {
                    Text("↑↓ 选择   ↩ 执行   → 动作")
                    Spacer()
                    Text(preferences.launcherHotKey.displayString)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 26)
            }
        }
        .background(style.backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: preferences.panelCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: preferences.panelCornerRadius).stroke(Color.primary.opacity(0.08)))
    }

    private func previewRow(icon: String, title: String, subtitle: String, key: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if preferences.showSubtitles {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(key).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, preferences.compactResults ? 7 : 11)
        .background(selected ? Color.accentColor.opacity(style.selectionOpacity) : Color.clear)
    }
}
