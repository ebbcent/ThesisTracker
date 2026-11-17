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

    /// Rayon de coin selon l'apparence (d'origine, Tuiles).
    static func r(_ classic: CGFloat, _ tilesRadius: CGFloat) -> CGFloat { tiles ? tilesRadius : classic }

    /// Liseré des cartes et des champs : absent en Tuiles.
    static var hairline: Color { tiles ? .clear : .cardBorder }

    /// Texte posé sur la couleur d'accent.
    static var onAccent: Color { .white }

    /// Panneau flottant arrondi en Tuiles (5.25), rectangle plein sinon.
    static func panelShape(_ radius: CGFloat) -> AnyShape {
        tiles ? AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous)) : AnyShape(Rectangle())
    }

    // 5.25 — fond « papier » (chaud) ou neutre, réglage « Fond » des Réglages
    private static var paperCached: Bool = computePaper()
    static var paper: Bool { paperCached }

    private static func computePaper() -> Bool {
        UserDefaults.standard.object(forKey: "tilesPaper") == nil ? true : UserDefaults.standard.bool(forKey: "tilesPaper")
    }

    // 5.25 — couleur d'accent de l'apparence Tuiles (réglage séparé de celui des affichages d'origine)
    static let defaultAccentHex = "#1F3FD1"
    private static var accentCached: (light: NSColor, dark: NSColor) = computeAccent()
    static var tilesAccent: (light: NSColor, dark: NSColor) { accentCached }

    static var tilesAccentHex: String {
        UserDefaults.standard.string(forKey: "tilesAccentHex") ?? defaultAccentHex
    }

    private static func ns(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    private static func computeAccent() -> (light: NSColor, dark: NSColor) {
        let hex = tilesAccentHex.uppercased()
        // Bleu d'encre par défaut : une teinte plus claire en sombre, pour rester lisible sur fond foncé.
        if hex == defaultAccentHex { return (ns(0x1F3FD1), ns(0x5F7BFF)) }
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return (ns(0x1F3FD1), ns(0x5F7BFF)) }
        return (ns(value), ns(value))
    }

    /// 5.26 — clair forcé, sombre forcé ou apparence du système, pour toutes les fenêtres de l'app.
    static func applyAppearance() {
        let defaults = UserDefaults.standard
        let name: NSAppearance.Name? = defaults.bool(forKey: "forceDarkMode") ? .darkAqua
            : (defaults.bool(forKey: "forceLightMode") ? .aqua : nil)
        NSApp.appearance = name.flatMap { NSAppearance(named: $0) }
    }

    /// À appeler quand l'affichage, le fond ou l'accent change.
    static func refresh() {
        cached = compute()
        paperCached = computePaper()
        accentCached = computeAccent()
        Color.refreshAccent()
    }
}

// MARK: - Palette sombre premium (adaptative light / dark)

extension Color {

    /// Couleur clair / sombre, avec une variante pour l'apparence Tuiles.
    private static func look(classic: (light: UInt32, dark: UInt32), tiles: (light: UInt32, dark: UInt32),
                             paper: (light: UInt32, dark: UInt32)) -> Color {
        func ns(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
            let dark = trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let pair = AppLook.tiles ? (AppLook.paper ? paper : tiles) : classic
            return ns(dark ? pair.dark : pair.light)
        }))
    }

    // Fonds adaptatifs — palette warm-dark premium v3 ; variante Tuiles en 5.24
    // 5.25 : troisième variante, « papier » (fond et cartes légèrement chauds)
    static let appBg     = look(classic: (0xF8F7F5, 0x0C0B0A), tiles: (0xF1EFEA, 0x0F0E10), paper: (0xEAE5DA, 0x11100F))
    static let sidebarBg = look(classic: (0xF2F1EF, 0x0A0908), tiles: (0xE9E6DF, 0x151416), paper: (0xE3DDD0, 0x171614))
    static let cardBg    = look(classic: (0xFFFFFF, 0x1A1816), tiles: (0xFFFFFF, 0x1C1B1E), paper: (0xFBF9F4, 0x1B1A18))   // 5.18 : plus distinct du fond
    /// Fond des jauges et des anneaux (partie non remplie).
    static let trackBg   = look(classic: (0xE8E4E2, 0x272320), tiles: (0xE3DFD6, 0x333136), paper: (0xE4DDCF, 0x302E2A))

    static let cardBorder = adaptive(light: 0xE8E4E2, dark: 0x272320, hcLight: 0x8A8480, hcDark: 0x8C847C,
                                     tilesLight: 0xE9E5DD, tilesDark: 0x2A282C)   // 5.15 : contraste renforcé

    static let fieldBg = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        let dark = trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if AppLook.tiles, AppLook.paper {
            return dark ? NSColor(srgbRed: 0.149, green: 0.141, blue: 0.133, alpha: 1)   // #262422
                        : NSColor(srgbRed: 0.945, green: 0.925, blue: 0.882, alpha: 1)   // #F1ECE1
        }
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
    // ambre principal ; en Tuiles (5.25) : la couleur d'accent choisie dans les Réglages
    static let accentWarm = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        func ns(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        let match = trait.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
        if AppLook.tiles {
            let dark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            return dark ? AppLook.tilesAccent.dark : AppLook.tilesAccent.light
        }
        switch match {
        case .darkAqua?: return ns(0xF59E0B)
        case .accessibilityHighContrastAqua?: return ns(0xB45309)
        case .accessibilityHighContrastDarkAqua?: return ns(0xFBBF24)
        default: return ns(0xD97706)
        }
    }))
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

    // 5.26 — couleurs de sens (alerte, succès, repères) : une teinte foncée sur fond clair, une teinte
    // claire sur fond sombre, pour rester lisibles comme texte dans les deux modes. Elles remplacent les
    // mêmes couleurs écrites en dur dans les pages (pensées pour le seul mode sombre).
    private static func sem(_ light: UInt32, _ dark: UInt32) -> Color {
        adaptive(light: light, dark: dark, hcLight: light, hcDark: dark)
    }
    static let semAmber  = sem(0xA85D00, 0xF5A623)
    static let semOrange = sem(0xC2410C, 0xF8843A)
    static let semRed    = sem(0xBF2A22, 0xF36C6C)
    static let semPink   = sem(0xBE185D, 0xF4619B)
    static let semPurple = sem(0x6739B7, 0xB49CF2)
    static let semViolet = sem(0x7C3AB8, 0xCB9DFB)
    static let semBlue   = sem(0x1D4ED8, 0x6D9BF8)
    static let semSky    = sem(0x0F6CB0, 0x62B4EE)
    static let semGreen  = sem(0x15803D, 0x45C97A)
    static let semYellow = sem(0x8A6A00, 0xF3C63A)

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
            // 5.25 — en Tuiles : titre de section net, sans filet
            Text(title)
                .font(AppLook.tiles ? .system(size: 15, weight: .bold) : TypeScale.sectionTitle)
                .foregroundColor(AppLook.tiles ? .primary : .labelMuted)
            Rectangle()
                .fill(AppLook.hairline)
                .frame(height: 1)
        }
    }
}
