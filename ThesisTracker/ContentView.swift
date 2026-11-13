import SwiftUI
import AppKit

// MARK: - Color hex helpers

extension Color {
    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components,
              components.count >= 3 else { return "#F59E0B" }
        return String(format: "#%02X%02X%02X",
                      Int(components[0] * 255),
                      Int(components[1] * 255),
                      Int(components[2] * 255))
    }
}

// MARK: - Palette sombre premium (adaptative light / dark)

extension Color {

    // Fonds adaptatifs — palette warm-dark premium v3
    static let appBg = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.047, green: 0.043, blue: 0.039, alpha: 1)   // #0c0b0a
            : NSColor(red: 0.973, green: 0.969, blue: 0.961, alpha: 1)   // #F8F7F5
    }))

    static let sidebarBg = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.039, green: 0.035, blue: 0.031, alpha: 1)   // #0a0908
            : NSColor(red: 0.949, green: 0.945, blue: 0.937, alpha: 1)   // #F2F1EF
    }))

    static let cardBg = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.078, green: 0.071, blue: 0.063, alpha: 1)   // #141210
            : NSColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1)   // #FFFFFF
    }))

    static let cardBorder = adaptive(light: 0xE8E4E2, dark: 0x272320, hcLight: 0x8A8480, hcDark: 0x8C847C)   // 5.15 : contraste renforcé

    static let fieldBg = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.102, green: 0.094, blue: 0.082, alpha: 1)   // #1a1815
            : NSColor(white: 0, alpha: 0.04)
    }))

    static let labelMuted = adaptive(light: 0x6B6660, dark: 0xA09890, hcLight: 0x3F3B37, hcDark: 0xD6CFC8)   // 5.15 : contraste renforcé

    static let glassFill = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0, alpha: 0.04)
    }))
    static let glassBorder = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.09)
    }))

    // Accent choisi par l'utilisateur (Réglages) :
    // CACHÉ : lire UserDefaults + parser hex à chaque accès (233 sites d'appel)
    // coûtait des milliers d'appels par frame. Invalidé via `refreshAccent()`
    // depuis DataStore.setAccentColor() quand l'utilisateur change la couleur.
    private static var _accentCache: Color = Self.computeAccent()
    static var accent: Color { _accentCache }

    private static func computeAccent() -> Color {
        let hex = UserDefaults.standard.string(forKey: "accentColorHex") ?? "#F59E0B"
        return Color(hex: hex)
    }

    static func refreshAccent() {
        _accentCache = computeAccent()
    }
    // 5.15 — accents adaptatifs : inchangés en mode sombre ; plus soutenus en mode clair, où ils servent
    // aussi de couleur de texte (l'ambre #F59E0B sur blanc ne contrastait qu'à ≈ 2:1) ; encore plus nets
    // avec « Augmenter le contraste » (Réglages système › Accessibilité › Affichage).
    static let accentWarm  = adaptive(light: 0xD97706, dark: 0xF59E0B, hcLight: 0xB45309, hcDark: 0xFBBF24)  // ambre principal
    static let accentGold  = adaptive(light: 0xEA580C, dark: 0xEA580C, hcLight: 0xC2410C, hcDark: 0xFB923C)  // orange profond
    static let accentGreen = adaptive(light: 0x16A34A, dark: 0x22C55E, hcLight: 0x15803D, hcDark: 0x4ADE80)  // succès
    static let accentRose  = adaptive(light: 0xE11D48, dark: 0xF43F5E, hcLight: 0xBE123C, hcDark: 0xFB7185)  // alertes

    /// Couleur dynamique : clair, sombre, et variantes « Augmenter le contraste ».
    static func adaptive(light: UInt32, dark: UInt32, hcLight: UInt32, hcDark: UInt32) -> Color {
        func ns(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
            switch trait.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
            case .darkAqua?: return ns(dark)
            case .accessibilityHighContrastAqua?: return ns(hcLight)
            case .accessibilityHighContrastDarkAqua?: return ns(hcDark)
            default: return ns(light)
            }
        }))
    }

    // Palette chapitres (graphiques)
    static let chapterPalette: [Color] = [
        Color(red: 0.961, green: 0.620, blue: 0.043),  // amber
        Color(red: 0.133, green: 0.773, blue: 0.369),  // green
        Color(red: 0.918, green: 0.345, blue: 0.047),  // orange
        Color(red: 0.627, green: 0.502, blue: 0.980),  // purple
        Color(red: 0.957, green: 0.247, blue: 0.369),  // rose
        Color(red: 0.373, green: 0.741, blue: 0.894),  // sky
    ]

    static func chapterColor(at index: Int) -> Color {
        chapterPalette[index % chapterPalette.count]
    }
}

// MARK: - GlassCard (style Notion : fond plat + bordure fine)

// MARK: - Compact dashboard environment key (#16)

private struct CompactDashboardKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var compactDashboard: Bool {
        get { self[CompactDashboardKey.self] }
        set { self[CompactDashboardKey.self] = newValue }
    }
}

struct GlassCard<Content: View>: View {
    @Environment(\.compactDashboard) private var compact
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(compact ? 10 : 16)
            // 5.16 : verre d'Apple (réglage « Verre ») ; bordure fine seulement sans verre
            .appGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.cardBorder, lineWidth: GlassIsOn.value ? 0 : 1)
            )
        // Suppression du .shadow(radius: 12) — il forçait un off-screen render
        // pass par carte (× 79 cartes sur le dashboard). Le contour 1px suffit
        // pour la profondeur (look Notion / Linear).
    }
}

typealias DarkCard = GlassCard

// MARK: - Couleurs des tags (style macOS)

extension ProjectTag {
    var color: Color {
        switch self {
        case .red:    return Color(red: 1.00, green: 0.27, blue: 0.23)
        case .orange: return Color(red: 1.00, green: 0.62, blue: 0.04)
        case .yellow: return Color(red: 1.00, green: 0.84, blue: 0.04)
        case .green:  return Color(red: 0.20, green: 0.84, blue: 0.29)
        case .blue:   return Color(red: 0.04, green: 0.52, blue: 1.00)
        case .purple: return Color(red: 0.72, green: 0.34, blue: 0.90)
        case .gray:   return Color(red: 0.60, green: 0.60, blue: 0.62)
        }
    }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.labelMuted)
                .kerning(1.2)
            Rectangle()
                .fill(Color.cardBorder)
                .frame(height: 1)
        }
    }
}
