import SwiftUI

enum DesignTokens {
    static let defaultPanelWidth: CGFloat = 720
    static let panelMaximumHeight: CGFloat = 500
    static let panelMinimumHeight: CGFloat = 196
    static let headerHeight: CGFloat = 72
    static let footerHeight: CGFloat = 34
    static let emptyBodyHeight: CGFloat = 150
    // Includes the plain List's inter-row pitch. The visible backgrounds are
    // 52pt / 44pt; SwiftUI contributes the remaining 8pt between rows.
    static let comfortableRowHeight: CGFloat = 60
    static let compactRowHeight: CGFloat = 52
    static let panelCornerRadius: CGFloat = 14
    static let resultCornerRadius: CGFloat = 9
    static let resultIconSize: CGFloat = 34
    static let horizontalPadding: CGFloat = 18
}

extension AppAccentColor {
    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .green: .green
        case .orange: .orange
        }
    }
}

extension LauncherAppearanceStyle {
    var headerHeight: CGFloat {
        switch self {
        case .minimal: 40
        case .classic: 60
        case .modern: 68
        case .glass: 64
        }
    }

    var searchFontSize: CGFloat {
        switch self {
        case .minimal: 18
        case .classic: 22
        case .modern, .glass: 23
        }
    }

    var showsFooter: Bool { self == .modern }
    var collapsesWhenIdle: Bool { self != .modern }

    var emptyBodyHeight: CGFloat {
        switch self {
        case .minimal, .glass: 78
        case .classic: 96
        case .modern: DesignTokens.emptyBodyHeight
        }
    }

    var selectionOpacity: Double {
        switch self {
        case .minimal: 0.12
        case .classic: 0.18
        case .modern: 0.16
        case .glass: 0.20
        }
    }

    var backgroundStyle: AnyShapeStyle {
        switch self {
        case .minimal, .modern:
            AnyShapeStyle(.regularMaterial)
        case .classic:
            AnyShapeStyle(.thickMaterial)
        case .glass:
            AnyShapeStyle(.ultraThinMaterial)
        }
    }
}
