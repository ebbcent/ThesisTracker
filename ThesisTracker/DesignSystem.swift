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
