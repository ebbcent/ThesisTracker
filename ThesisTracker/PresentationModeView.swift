import SwiftUI

// MARK: - Feature #58 : Mode présentation amélioré
// Vue plein écran conçue pour les réunions avec le directeur de thèse.
// Affiche : progression globale, chapitres, stats clés et projection de soutenance.

struct PresentationModeView: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) private var dismiss

    // Auto-advance timer for slideshow (optional)
    @State private var currentSlide: Int = 0
    @State private var showExitConfirm = false

    private let slides: [PresentationSlide] = [.progress, .chapters, .stats, .projection]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Slide content
                Group {
                    switch slides[currentSlide] {
                    case .progress:   progressSlide
                    case .chapters:   chaptersSlide
                    case .stats:      statsSlide
                    case .projection: projectionSlide
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                .animation(.easeInOut(duration: 0.4), value: currentSlide)

                // Navigation dots + buttons
                slideNavBar
            }

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(20)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Quitter la présentation (Échap)")
            .accessibilityLabel("Quitter la présentation (Échap)")
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    // MARK: - Slide navigation bar

    private var slideNavBar: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation { currentSlide = max(0, currentSlide - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(currentSlide > 0 ? 0.8 : 0.2))
            }
            .buttonStyle(.plain)
            .disabled(currentSlide == 0)
            .keyboardShortcut(.leftArrow, modifiers: [])
            .help("Diapositive précédente")
            .accessibilityLabel("Diapositive précédente")

            HStack(spacing: 8) {
                ForEach(slides.indices, id: \.self) { idx in
                    Circle()
                        .fill(idx == currentSlide ? Color.white : Color.white.opacity(0.3))
                        .frame(width: idx == currentSlide ? 8 : 6, height: idx == currentSlide ? 8 : 6)
                        .onTapGesture { withAnimation { currentSlide = idx } }
                }
            }

            Button {
                withAnimation { currentSlide = min(slides.count - 1, currentSlide + 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(currentSlide < slides.count - 1 ? 0.8 : 0.2))
            }
            .buttonStyle(.plain)
            .disabled(currentSlide == slides.count - 1)
            .keyboardShortcut(.rightArrow, modifiers: [])
            .help("Diapositive suivante")
            .accessibilityLabel("Diapositive suivante")
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
    }

    // MARK: - Slide 1 : Progression globale

    private var progressSlide: some View {
        let proj  = store.activeProject
        let dp    = store.defenseProjection
        let total = dp.totalWritten
        let goal  = dp.totalGoal
        let pct   = goal > 0 ? min(1.0, Double(total) / Double(goal)) : 0

        return VStack(spacing: 40) {
            Spacer()

            // Titre
            VStack(spacing: 10) {
                Text("Progression globale")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .kerning(2)
                if let p = proj {
                    Text(p.name)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
            }

            // Big progress ring / bar
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 14)
                        .frame(width: 180, height: 180)
                    Circle()
                        .trim(from: 0, to: CGFloat(pct))
                        .stroke(
                            LinearGradient(colors: [Color.accent, Color.accentGreen], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .frame(width: 180, height: 180)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 1.2), value: pct)
                    VStack(spacing: 4) {
                        Text("\(Int(pct * 100))%")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("complété")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                HStack(spacing: 32) {
                    presentationStat(value: store.formatCount(total), label: "écrits")
                    if goal > 0 {
                        presentationStat(value: store.formatCount(goal), label: "objectif")
                        presentationStat(value: store.formatCount(max(0, goal - total)), label: "restants")
                    }
                }
            }

            Spacer()
        }
        .padding(40)
    }

    // MARK: - Slide 2 : Chapitres

    private var chaptersSlide: some View {
        guard let proj = store.activeProject else {
            return AnyView(emptySlide("Aucun projet actif"))
        }
        return AnyView(
            VStack(spacing: 32) {
                Spacer()
                Text("Chapitres")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .kerning(2)

                VStack(spacing: 16) {
                    ForEach(proj.chapters) { ch in
                        let total = store.latestTotal(for: ch.id, in: proj.id)
                        let pct   = ch.goal > 0 ? min(1.0, Double(total) / Double(ch.goal)) : 0
                        let done  = ch.goal > 0 && total >= ch.goal
                        HStack(spacing: 16) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(done ? Color.accentGreen : Color.white.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                Text(ch.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.white.opacity(done ? 1 : 0.8))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(pct * 100))%")
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(done ? Color.accentGreen : .white.opacity(0.6))
                            }
                            .frame(maxWidth: .infinity)

                            // Progress bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white.opacity(0.08))
                                        .frame(height: 6)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(done ? Color.accentGreen : Color.accent)
                                        .frame(width: geo.size.width * CGFloat(pct), height: 6)
                                        .animation(.easeOut(duration: 0.8), value: pct)
                                }
                            }
                            .frame(width: 160, height: 6)
                        }
                    }
                }
                .padding(.horizontal, 60)

                Spacer()
            }
            .padding(40)
        )
    }

    // MARK: - Slide 3 : Statistiques clés

    private var statsSlide: some View {
        let streak   = store.currentStreak
        let vel      = store.velocity14Days
        let monthly  = store.currentMonthReview.totalChars
        let best     = store.top10Days.first?.total ?? 0

        return VStack(spacing: 40) {
            Spacer()
            Text("Indicateurs clés")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .kerning(2)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 24) {
                presentationStatCard(
                    icon: "flame.fill", color: .accentWarm,
                    value: "\(streak) jour\(streak > 1 ? "s" : "")",
                    label: "série active",
                    subtitle: streak == 0 ? "Lancez votre série !" : streak >= 7 ? "🔥 Impressionnant !" : "Continuez !"
                )
                presentationStatCard(
                    icon: "bolt.fill", color: .accent,
                    value: store.formatCount(vel) + "/j",
                    label: "vitesse 14j",
                    subtitle: "moyenne glissante"
                )
                presentationStatCard(
                    icon: "calendar", color: .accentGreen,
                    value: store.formatCount(monthly),
                    label: "ce mois-ci",
                    subtitle: "total cumulé"
                )
                presentationStatCard(
                    icon: "crown.fill", color: Color(red: 1, green: 0.84, blue: 0),
                    value: store.formatCount(best),
                    label: "meilleure session",
                    subtitle: "record personnel"
                )
            }
            .padding(.horizontal, 60)

            Spacer()
        }
        .padding(40)
    }

    // MARK: - Slide 4 : Projection de soutenance

    private var projectionSlide: some View {
        let dp      = store.defenseProjection
        let hasProj = dp.realisticDate != nil

        return VStack(spacing: 40) {
            Spacer()
            Text("Projection de fin")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .kerning(2)

            if hasProj, let date = dp.realisticDate {
                let pct = dp.totalGoal > 0 ? Int(Double(dp.totalWritten) / Double(dp.totalGoal) * 100) : 0
                let daysLeft = dp.daysRemainingRealistic ?? 0
                VStack(spacing: 28) {
                    // Date prévue
                    VStack(spacing: 8) {
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.accentGreen)
                        Text(formattedProjDate(date))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("date de fin estimée (rythme médian)")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    HStack(spacing: 40) {
                        presentationStat(value: "\(daysLeft)", label: "jours restants")
                        presentationStat(value: store.formatCount(dp.avgDailyChars) + "/j", label: "cadence actuelle")
                        presentationStat(value: "\(pct)%", label: "avancement")
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Données insuffisantes pour la projection")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Configurez un objectif global et une date cible dans les réglages.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()
        }
        .padding(40)
    }

    // MARK: - Helpers

    private func emptySlide(_ msg: String) -> some View {
        VStack {
            Spacer()
            Text(msg)
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
        }
    }

    private func presentationStat(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func presentationStatCard(icon: String, color: Color, value: String, label: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .kerning(1.2)
            }
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func formattedProjDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date).capitalized
    }
}

// MARK: - Slides enum

private enum PresentationSlide {
    case progress, chapters, stats, projection
}
