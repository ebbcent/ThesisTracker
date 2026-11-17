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

// MARK: - 5.24 Apparence de l'app : « Tuiles » ou d'origine
//
// Quand l'affichage Tuiles (VT) est choisi, toute l'app prend ses couleurs (fond, cartes, barre
// latérale, accent bleu, cartes plus rondes et sans liseré). Avec VA ou VD, la palette d'origine
// revient telle quelle. Valeur mise en cache : les couleurs sont lues des milliers de fois par image.

enum AppLook {
    private static var cached: Bool = compute()
    static var tiles: Bool { cached }

    private static func compute() -> Bool {
        (UserDefaults.standard.string(forKey: "interfaceMode") ?? "VT") == "VT"
    }

    /// À appeler quand l'affichage change (menu Affichage, tuile « Tableau de bord complet »).
    static func refresh() {
        cached = compute()
        Color.refreshAccent()
    }
}

// MARK: - Palette sombre premium (adaptative light / dark)

extension Color {

    /// Couleur clair / sombre, avec une variante pour l'apparence Tuiles.
    private static func look(classic: (light: UInt32, dark: UInt32), tiles: (light: UInt32, dark: UInt32)) -> Color {
        func ns(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
            let dark = trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let pair = AppLook.tiles ? tiles : classic
            return ns(dark ? pair.dark : pair.light)
        }))
    }

    // Fonds adaptatifs — palette warm-dark premium v3 ; variante Tuiles en 5.24
    static let appBg     = look(classic: (0xF8F7F5, 0x0C0B0A), tiles: (0xF1EFEA, 0x0F0E10))
    static let sidebarBg = look(classic: (0xF2F1EF, 0x0A0908), tiles: (0xE9E6DF, 0x151416))
    static let cardBg    = look(classic: (0xFFFFFF, 0x1A1816), tiles: (0xFFFFFF, 0x1C1B1E))   // 5.18 : plus distinct du fond

    static let cardBorder = adaptive(light: 0xE8E4E2, dark: 0x272320, hcLight: 0x8A8480, hcDark: 0x8C847C,
                                     tilesLight: 0xE9E5DD, tilesDark: 0x2A282C)   // 5.15 : contraste renforcé

    static let fieldBg = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        let dark = trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if AppLook.tiles {
            return dark ? NSColor(srgbRed: 0.157, green: 0.149, blue: 0.165, alpha: 1)   // #28262A
                        : NSColor(srgbRed: 0.945, green: 0.937, blue: 0.918, alpha: 1)   // #F1EFEA
        }
        return dark
            ? NSColor(red: 0.137, green: 0.125, blue: 0.114, alpha: 1)   // #23201D (5.18 : champ distinct de sa carte)
            : NSColor(white: 0, alpha: 0.04)
    }))

    static let labelMuted = adaptive(light: 0x6B6660, dark: 0xA09890, hcLight: 0x3F3B37, hcDark: 0xD6CFC8,
                                     tilesLight: 0x615C53, tilesDark: 0xA9A398)   // 5.15 : contraste renforcé

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
        if AppLook.tiles { return accentWarm }   // 5.24 : bleu d'encre de l'apparence Tuiles
        let hex = UserDefaults.standard.string(forKey: "accentColorHex") ?? "#F59E0B"
        return Color(hex: hex)
    }

    static func refreshAccent() {
        _accentCache = computeAccent()
    }
    // 5.15 — accents adaptatifs : inchangés en mode sombre ; plus soutenus en mode clair, où ils servent
    // aussi de couleur de texte (l'ambre #F59E0B sur blanc ne contrastait qu'à ≈ 2:1) ; encore plus nets
    // avec « Augmenter le contraste » (Réglages système › Accessibilité › Affichage).
    static let accentWarm  = adaptive(light: 0xD97706, dark: 0xF59E0B, hcLight: 0xB45309, hcDark: 0xFBBF24,
                                      tilesLight: 0x1F3FD1, tilesDark: 0x8FA3FF)  // ambre principal ; bleu d'encre en Tuiles
    static let accentGold  = adaptive(light: 0xEA580C, dark: 0xEA580C, hcLight: 0xC2410C, hcDark: 0xFB923C)  // orange profond
    static let accentGreen = adaptive(light: 0x16A34A, dark: 0x22C55E, hcLight: 0x15803D, hcDark: 0x4ADE80)  // succès
    static let accentRose  = adaptive(light: 0xE11D48, dark: 0xF43F5E, hcLight: 0xBE123C, hcDark: 0xFB7185)  // alertes

    /// Couleur dynamique : clair, sombre, et variantes « Augmenter le contraste ».
    static func adaptive(light: UInt32, dark: UInt32, hcLight: UInt32, hcDark: UInt32,
                         tilesLight: UInt32? = nil, tilesDark: UInt32? = nil) -> Color {
        func ns(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
            let match = trait.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            // 5.24 — apparence Tuiles (hors « Augmenter le contraste », qui garde ses variantes)
            if AppLook.tiles, let tilesLight, let tilesDark {
                if match == .darkAqua { return ns(tilesDark) }
                if match == .aqua { return ns(tilesLight) }
            }
            switch match {
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
        // 5.24 — apparence Tuiles : cartes plus rondes, plus aérées, sans liseré
        let tiles = AppLook.tiles
        let radius: CGFloat = tiles ? 22 : 12
        content
            .padding(compact ? 10 : (tiles ? 20 : 16))
            // 5.17 : cartes pleines (le contenu ne va pas sous verre : lisibilité, pas de verre sur verre)
            .background(Color.cardBg, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(tiles ? Color.clear : Color.cardBorder, lineWidth: 1)
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
            // 5.18 : titre de section en casse normale (les capitales espacées partout écrasaient la hiérarchie)
            Text(title)
                .font(TypeScale.sectionTitle)
                .foregroundColor(.labelMuted)
            Rectangle()
                .fill(Color.cardBorder)
                .frame(height: 1)
        }
    }
}
