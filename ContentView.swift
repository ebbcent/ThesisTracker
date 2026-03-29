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

// MARK: - Palette Notion × Amber (adaptative light / dark)

extension Color {

    // Fonds adaptatifs
    static let appBg = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        trait.name == .darkAqua
            ? NSColor(red: 0.098, green: 0.098, blue: 0.098, alpha: 1)   // #191919
            : NSColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1)   // #ffffff
    }))

    static let sidebarBg = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        trait.name == .darkAqua
            ? NSColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1)   // #1e1e1e
            : NSColor(red: 0.969, green: 0.969, blue: 0.961, alpha: 1)   // #f7f7f5
    }))

    static let cardBg = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        trait.name == .darkAqua
            ? NSColor(red: 0.141, green: 0.141, blue: 0.141, alpha: 1)   // #242424
            : NSColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1)   // #ffffff
    }))

    static let cardBorder = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        trait.name == .darkAqua
            ? NSColor(red: 0.220, green: 0.220, blue: 0.220, alpha: 1)   // #383838
            : NSColor(red: 0.910, green: 0.910, blue: 0.902, alpha: 1)   // #e8e8e6
    }))

    static let fieldBg = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        trait.name == .darkAqua
            ? NSColor(white: 0, alpha: 0.30)
            : NSColor(white: 0, alpha: 0.05)
    }))

    static let labelMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        trait.name == .darkAqua
            ? NSColor(red: 0.471, green: 0.467, blue: 0.455, alpha: 1)   // #787774
            : NSColor(red: 0.608, green: 0.604, blue: 0.592, alpha: 1)   // #9b9a97
    }))

    // Alias pour compatibilité (boutons sidebar toggle, etc.)
    static let glassFill = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        trait.name == .darkAqua ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 0, alpha: 0.04)
    }))
    static let glassBorder = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        trait.name == .darkAqua ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.10)
    }))

    // Accents — identiques en mode clair et sombre
    static var accent: Color {
        let hex = UserDefaults.standard.string(forKey: "accentColorHex") ?? "#F59E0B"
        return Color(hex: hex)
    }
    static let accentWarm  = Color(red: 0.929, green: 0.435, blue: 0.114)  // orange chaud
    static let accentGold  = Color(red: 0.843, green: 0.329, blue: 0.125)  // gold profond
    static let accentGreen   = Color(red: 0.196, green: 0.784, blue: 0.549)  // teal (complétion)
    static let destructiveRed  = Color(red: 1.000, green: 0.350, blue: 0.350) // suppression / danger
    static let urgentRed       = Color(red: 0.929, green: 0.329, blue: 0.329) // deadline / urgence
    static let sessionBlue     = Color(red: 0.220, green: 0.600, blue: 0.900) // sessions pomodoro
    static let challengePurple = Color(red: 0.580, green: 0.400, blue: 0.900) // défis écriture
    static let insightPurple   = Color(red: 0.706, green: 0.502, blue: 0.984) // insights / stats

    // Palette chapitres (graphiques)
    static let chapterPalette: [Color] = [
        Color(red: 0.961, green: 0.620, blue: 0.043),  // amber
        Color(red: 0.196, green: 0.784, blue: 0.549),  // teal
        Color(red: 0.929, green: 0.435, blue: 0.114),  // orange
        Color(red: 0.706, green: 0.502, blue: 0.984),  // purple
        Color(red: 0.878, green: 0.306, blue: 0.376),  // coral
        Color(red: 0.373, green: 0.741, blue: 0.894),  // sky
    ]

    static func chapterColor(at index: Int) -> Color {
        chapterPalette[index % chapterPalette.count]
    }
}

// MARK: - GlassCard (style Notion : fond plat + bordure fine)

struct GlassCard<Content: View>: View {
    @State private var isHovered = false
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(18)
            .background(Color.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isHovered ? Color.cardBorder.opacity(1) : Color.cardBorder,
                        lineWidth: isHovered ? 1.5 : 1
                    )
            )
            .scaleEffect(isHovered ? 1.004 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
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
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(1.4)
            Spacer()
        }
    }
}
