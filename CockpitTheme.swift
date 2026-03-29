import SwiftUI

// CockpitTheme remapped to Writing Process's design system
enum CockpitTheme {
    static func backgroundTop(for scheme: ColorScheme) -> Color { Color.appBg }
    static func backgroundBottom(for scheme: ColorScheme) -> Color { Color.appBg }
    static func panel(for scheme: ColorScheme) -> Color { Color.cardBg }
    static func panelElevated(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.14, green: 0.14, blue: 0.16)
            : Color(red: 0.94, green: 0.94, blue: 0.96)
    }
    static func stroke(for scheme: ColorScheme) -> Color { Color.cardBorder }
    static func overlayFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }
    static func shadow(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.30) : Color.black.opacity(0.10)
    }

    // Semantic accent colors mapped to WP palette
    static let glow    = Color(red: 0.04, green: 0.52, blue: 1.00)  // blue (long break)
    static let accent  = Color.accentWarm                            // orange (focus)
    static let success = Color.accentGreen                           // green (short break)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.18)   // yellow

    static func textPrimary(for scheme: ColorScheme) -> Color { .primary }
    static func textSecondary(for scheme: ColorScheme) -> Color { .secondary }
    static func textTertiary(for scheme: ColorScheme) -> Color { Color.labelMuted }
}
