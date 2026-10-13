import SwiftUI

// CockpitTheme remapped to Writing Process's design system
enum CockpitTheme {
    static func backgroundTop(for scheme: ColorScheme) -> Color { Color.appBg }
    static func backgroundBottom(for scheme: ColorScheme) -> Color { Color.appBg }
    static func panel(for scheme: ColorScheme) -> Color { Color.cardBg }
    static func panelElevated(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.118, green: 0.106, blue: 0.094)   // #1E1B18
            : Color(red: 0.953, green: 0.949, blue: 0.941)   // #F3F2F0
    }
    static func stroke(for scheme: ColorScheme) -> Color { Color.cardBorder }
    static func overlayFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)
    }
    static func shadow(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.12)
    }

    // Semantic accent colors mapped to warm palette
    static let glow    = Color(red: 0.04, green: 0.52, blue: 1.00)  // blue (long break)
    static let accent  = Color.accentWarm                            // amber (focus)
    static let success = Color.accentGreen                           // green (short break)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.18)   // yellow

    static func textPrimary(for scheme: ColorScheme) -> Color { .primary }
    static func textSecondary(for scheme: ColorScheme) -> Color { .secondary }
    static func textTertiary(for scheme: ColorScheme) -> Color { Color.labelMuted }
}
