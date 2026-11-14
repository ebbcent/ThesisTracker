import AppKit
import SwiftUI

// MARK: - 5.19 Cadran du minuteur, modernisé
//
// - Graduations : 60 traits fins autour de l'anneau ; ceux déjà écoulés prennent la couleur
//   de la phase (on lit la progression d'un coup d'œil, comme une montre).
// - Plus de halo ni de pulsation en boucle (une oscillation lente permanente fatigue l'œil
//   et ignore « Réduire les animations ») : l'anneau avance, c'est tout.
// - Chiffres arrondis, chasse fixe, transition numérique ; heure de fin sous le temps.

struct TimerDialView: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let timeText: String
    let progress: Double
    let accentColor: Color
    var size: CGFloat = 280
    /// Ligne sous le temps (« fin à 15:42 », « en pause »). Vide : rien.
    var detail: String = ""
    var isPaused: Bool = false

    private var ringWidth: CGFloat { max(4, size * 0.032) }
    private var tickRadius: CGFloat { size / 2 - size * 0.025 }
    private var ringInset: CGFloat { size * 0.09 }

    var body: some View {
        ZStack {
            ticks

            Circle()
                .inset(by: ringInset)
                .stroke(CockpitTheme.stroke(for: colorScheme).opacity(0.9), lineWidth: ringWidth)

            Circle()
                .inset(by: ringInset)
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(accentColor.opacity(isPaused ? 0.45 : 1),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .appAnimation(.linear(duration: 0.9), value: progress)
                .appAnimation(Motion.panel, value: accentColor)

            VStack(spacing: size * 0.025) {
                Text(title.uppercased())
                    .font(.system(size: max(10, size * 0.05), weight: .semibold, design: .rounded))
                    .kerning(size < 160 ? 0.4 : 1.1)
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: size * 0.6)   // 5.21 : reste dans l'anneau (« CONCENTRATION » débordait à 112 pt)
                    .appAnimation(Motion.quick, value: title)

                Text(timeText)
                    .font(.system(size: size * 0.2, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
                    .kerning(-size * 0.004)
                    .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme).opacity(isPaused ? 0.55 : 1))
                    .contentTransition(.numericText(countsDown: true))
                    .appAnimation(.linear(duration: 0.15), value: timeText)

                Text(detail.isEmpty ? " " : detail)
                    .font(.system(size: max(10, size * 0.046), weight: .medium).monospacedDigit())
                    .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(timeText) restantes\(detail.isEmpty ? "" : ", \(detail)")")
    }

    /// 60 graduations ; une sur cinq plus longue. Les graduations écoulées sont colorées.
    private var ticks: some View {
        let lit = Int((min(1, max(0, progress)) * 60).rounded(.down))
        return ZStack {
            ForEach(0..<60, id: \.self) { i in
                let major = i % 5 == 0
                Capsule()
                    .fill(i < lit && progress > 0 ? accentColor.opacity(isPaused ? 0.4 : 0.85)
                                                  : CockpitTheme.textTertiary(for: colorScheme).opacity(major ? 0.45 : 0.22))
                    .frame(width: major ? 2 : 1.2, height: major ? size * 0.04 : size * 0.025)
                    .offset(y: -tickRadius)
                    .rotationEffect(.degrees(Double(i) * 6))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 5.21 Anneau de la barre des menus

/// Petit anneau de progression pour l'icône de la barre des menus (image « modèle » :
/// macOS la teinte en blanc ou en noir selon la barre, comme les icônes système).
@MainActor
enum MenuBarRing {
    static func image(progress: Double, paused: Bool) -> NSImage {
        let p = min(1, max(0, progress))
        let view = ZStack {
            Circle().stroke(Color.black.opacity(0.3), lineWidth: 1.8)
            Circle()
                .trim(from: 0, to: max(0.001, p))
                .stroke(Color.black, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if paused {
                HStack(spacing: 1.5) {
                    Capsule().fill(Color.black).frame(width: 1.6, height: 5)
                    Capsule().fill(Color.black).frame(width: 1.6, height: 5)
                }
            }
        }
        .frame(width: 14, height: 14)
        .padding(1)

        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let img = renderer.nsImage ?? NSImage(systemSymbolName: "timer", accessibilityDescription: nil) ?? NSImage()
        img.isTemplate = true
        img.accessibilityDescription = paused ? "Minuteur en pause" : "Minuteur"
        return img
    }
}
