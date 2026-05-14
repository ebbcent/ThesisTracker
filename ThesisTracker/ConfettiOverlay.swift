import SwiftUI

// MARK: - Confetti (V5 — amélioration #9)
// Overlay de particules déclenché quand l'objectif journalier est atteint.

private struct Particle: Identifiable {
    let id = UUID()
    let x: CGFloat          // position initiale X (0…1 relative à la largeur)
    let color: Color
    let size: CGFloat
    let rotation: Double
    let rotationSpeed: Double
    let xDrift: CGFloat     // dérive horizontale pendant la chute
    let delay: Double       // délai avant apparition
}

struct ConfettiOverlay: View {

    // Lazy: particles are generated once on first appear, not on every View
    // struct construction (was 60 random allocations per parent re-render).
    @State private var particles: [Particle] = []
    @State private var animating = false

    private static func makeParticles() -> [Particle] {
        (0..<60).map { _ in
            Particle(
                x: CGFloat.random(in: 0.05...0.95),
                color: [Color.accentGreen, Color.accent, Color.accentWarm, Color.yellow, Color.blue, Color.purple]
                    .randomElement()!,
                size: CGFloat.random(in: 5...10),
                rotation: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: 120...360) * (Bool.random() ? 1 : -1),
                xDrift: CGFloat.random(in: -60...60),
                delay: Double.random(in: 0...0.8)
            )
        }
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(particles) { p in
                RoundedRectangle(cornerRadius: 2)
                    .fill(p.color)
                    .frame(width: p.size, height: p.size * 1.6)
                    .rotationEffect(.degrees(animating
                        ? p.rotation + p.rotationSpeed
                        : p.rotation))
                    .offset(
                        x: geo.size.width * p.x + (animating ? p.xDrift : 0),
                        y: animating ? geo.size.height + 40 : -20
                    )
                    .opacity(animating ? 0 : 1)
                    .animation(
                        .easeIn(duration: Double.random(in: 1.8...2.8))
                        .delay(p.delay),
                        value: animating
                    )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if particles.isEmpty { particles = Self.makeParticles() }
            animating = true
        }
    }
}
