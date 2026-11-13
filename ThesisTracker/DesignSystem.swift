import AppKit
import SwiftUI

// MARK: - 5.15 Système de design : mouvement, boutons, tailles des feuilles
// (état vide commun : EmptyStateView, dans SharedComponents.swift)
//
// Principes (Apple, « Designing Fluid Interfaces » ; E. Kowalski) :
// - Mouvement : trois réglages partagés. Ressorts sans rebond par défaut ; le
//   rebond est réservé aux rares célébrations. Rien d'animé au clavier.
// - « Réduire les animations » (macOS) : plus de déplacement ni de ressort,
//   changement immédiat. « Réduire la transparence » : fonds pleins.
// - Retour à l'appui : un bouton réagit dès qu'on le presse.

enum Motion {
    /// Réglage système « Réduire les animations » (lu à chaque appel : suit les changements à chaud).
    static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Réglage système « Réduire la transparence ».
    static var reduceTransparency: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }

    /// Retour rapide : survol, appui, petits changements d'état (≈ 150 ms, décélération franche).
    static let quick = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.15)
    /// Panneaux, cartes, réorganisation : ressort amorti, sans rebond.
    static let panel = Animation.spring(response: 0.3, dampingFraction: 1)
    /// Jauges et compteurs qui progressent : ressort amorti, un peu plus lent.
    static let progress = Animation.spring(response: 0.45, dampingFraction: 1)
    /// Célébrations rares (objectif atteint, série) : léger rebond permis.
    static let celebrate = Animation.spring(response: 0.35, dampingFraction: 0.7)

    /// Animation effective : aucune si « Réduire les animations » est activé.
    static func resolve(_ animation: Animation?) -> Animation? { reduce ? nil : animation }
}

/// `withAnimation` qui respecte « Réduire les animations ».
@discardableResult
func withAppAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.resolve(animation), body)
}

/// Changement d'état sans aucune animation (raccourcis clavier : répétés cent fois par jour).
func withoutAnimation(_ body: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, body)
}

extension View {
    /// `.animation(_:value:)` qui respecte « Réduire les animations ».
    func appAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        self.animation(Motion.resolve(animation), value: value)
    }
}

// MARK: - Bouton : retour à l'appui

/// Remplace `.plain` : même apparence, mais le bouton se resserre légèrement à l'appui.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration)
    }

    private struct PressableBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !Motion.reduce ? 0.97 : 1)
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
                .animation(Motion.reduce ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - Feuilles à la taille de l'écran

extension View {
    /// Taille d'une feuille, réduite si l'écran est plus petit (MacBook) : la feuille reste entière à l'écran.
    func sheetFrame(width: CGFloat, height: CGFloat) -> some View {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return self.frame(width: min(width, visible.width - 80), height: min(height, visible.height - 100))
    }
}

// MARK: - Matériaux système (translucidité)

/// Matériau AppKit (barre latérale, fenêtre…) : translucidité et vibrance du système.
/// macOS rend lui-même le matériau opaque quand « Réduire la transparence » est activé.
struct SystemMaterial: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .followsWindowActiveState
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

// MARK: - 5.16 Verre (Liquid Glass, macOS 26)
//
// Demande de Clem : le verre clair d'Apple partout, par cohérence. Réglage « Verre »
// (Réglages) : clair (défaut), standard, sans verre. Avant macOS 26 : matériaux de la 5.15.
// Le verre a besoin d'un fond à réfracter : AppBackdrop (deux halos très doux, immobiles).
// Exception : les surfaces flottantes chargées de texte (palette, note rapide) restent en
// verre standard, plus dépoli, pour rester lisibles au-dessus du contenu.

enum GlassStyle: String, CaseIterable, Identifiable {
    case clear, regular, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .clear:   return "Verre clair"
        case .regular: return "Verre standard"
        case .off:     return "Sans verre"
        }
    }
    static let storageKey = "glassStyle"
}

private struct AppGlassModifier<S: Shape>: ViewModifier {
    @AppStorage(GlassStyle.storageKey) private var styleRaw: String = GlassStyle.clear.rawValue
    let shape: S
    let tint: Color?
    /// Surface flottante chargée de texte : jamais plus transparente que le verre standard.
    let legible: Bool
    let fallback: Color

    @ViewBuilder func body(content: Content) -> some View {
        let style = GlassStyle(rawValue: styleRaw) ?? .clear
        if #available(macOS 26.0, *), style != .off {
            let base: Glass = (style == .clear && !legible) ? .clear : .regular
            content.glassEffect(tint.map { base.tint($0) } ?? base, in: shape)
        } else if style == .off {
            content.background(fallback, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

extension View {
    /// Verre de l'app (clair, standard ou fond plein selon le réglage « Verre »).
    func appGlass<S: Shape>(in shape: S, tint: Color? = nil, legible: Bool = false, fallback: Color = .cardBg) -> some View {
        modifier(AppGlassModifier(shape: shape, tint: tint, legible: legible, fallback: fallback))
    }

    /// Regroupe les surfaces de verre d'une page (rendu commun, moins coûteux ; fusion des formes proches).
    @ViewBuilder func appGlassContainer() -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer { self }
        } else {
            self
        }
    }
}

/// Vrai si le verre est actif (pour retirer les bordures fines devenues inutiles).
struct GlassIsOn {
    static var value: Bool {
        guard #available(macOS 26.0, *) else { return false }
        return (UserDefaults.standard.string(forKey: GlassStyle.storageKey) ?? GlassStyle.clear.rawValue) != GlassStyle.off.rawValue
    }
}

/// Fond de la fenêtre : couleur de l'app et, avec le verre, deux halos très doux (immobiles)
/// pour que le verre ait quelque chose à réfracter.
struct AppBackdrop: View {
    @AppStorage(GlassStyle.storageKey) private var styleRaw: String = GlassStyle.clear.rawValue
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color.appBg
            if (GlassStyle(rawValue: styleRaw) ?? .clear) != .off {
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    let k: Double = scheme == .dark ? 0.10 : 0.14
                    ZStack {
                        Circle()
                            .fill(Color.accentWarm.opacity(k))
                            .frame(width: max(w, h) * 0.7)
                            .position(x: w * 0.15, y: h * 0.1)
                        Circle()
                            .fill(Color(red: 0.376, green: 0.647, blue: 0.980).opacity(k * 0.8))
                            .frame(width: max(w, h) * 0.6)
                            .position(x: w * 0.9, y: h * 0.85)
                    }
                    .blur(radius: 120)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Réglage « Verre »

struct GlassSettingsSection: View {
    @AppStorage(GlassStyle.storageKey) private var styleRaw: String = GlassStyle.clear.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VERRE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(1.2)
            VStack(alignment: .leading, spacing: 8) {
                Picker("Verre", selection: $styleRaw) {
                    ForEach(GlassStyle.allCases) { s in Text(s.label).tag(s.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(verreNote)
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .appGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var verreNote: String {
        if #available(macOS 26.0, *) {
            return "Verre d'Apple (Liquid Glass) sur la barre latérale, la barre du haut, les cartes et les boutons. La palette de commandes et la note rapide restent en verre standard pour la lisibilité. « Réduire la transparence » le rend dépoli."
        }
        return "Le verre d'Apple demande macOS 26 ; sur cette version, matériaux translucides à la place."
    }
}
