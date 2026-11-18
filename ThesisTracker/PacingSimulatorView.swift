import SwiftUI

// MARK: - Simulateur de rythme d'un chapitre (5.12)
// Courbe du profil sur la fenêtre du chapitre, quotas des jours ouvrés restants,
// repère « Aujourd'hui ». Les pastilles permettent de comparer les profils
// avant d'en appliquer un ; les jours ouvrés s'enregistrent tout de suite.

struct PacingSimulatorView: View {
    @ObservedObject var store: DataStore
    let chapter: Chapter
    let projectId: UUID

    @State private var preview: PacingProfile? = nil

    private var savedProfile: PacingProfile? { chapter.pacing?.profile }
    private var shownProfile: PacingProfile { preview ?? savedProfile ?? .steady }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            profilePills
            if let plan = store.pacingPlan(for: chapter, profile: shownProfile) {
                PacingCurveView(plan: plan)
                    .frame(height: 110)
                summary(plan)
            } else {
                Text("Indique un objectif et une date limite pour calculer un rythme.")
                    .font(.system(size: AppLook.fs(11)))
                    .foregroundColor(.labelMuted)
            }
            weekdayPicker
        }
        .padding(12)
        .background(Color.fieldBg)
        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppLook.r(10, 14), style: .continuous).stroke(Color.cardBorder, lineWidth: 1))
    }

    // MARK: Profils

    private var profilePills: some View {
        HStack(spacing: 6) {
            ForEach(PacingProfile.allCases) { profile in
                let selected = profile == shownProfile
                Button {
                    withAppAnimation(.easeInOut(duration: 0.2)) {
                        preview = profile == (savedProfile ?? .steady) ? nil : profile
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: profile.symbol).font(.system(size: AppLook.fs(10)))
                        Text(profile.label).font(.system(size: AppLook.fs(11), weight: selected ? .semibold : .regular))
                        if profile == savedProfile {
                            Circle().fill(Color.accentGreen).frame(width: 5, height: 5)
                        }
                    }
                    .foregroundColor(selected ? .black : .primary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(selected ? Color.accentWarm : Color.cardBg))
                    .overlay(Capsule().stroke(selected ? Color.clear : Color.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .help(profile.summary)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
            if preview != nil {
                Button("Appliquer") {
                    let chosen = shownProfile
                    store.updatePacing(chapterId: chapter.id, in: projectId) { $0.profile = chosen }
                    preview = nil
                }
                .buttonStyle(AccentPillButtonStyle())
                .help("Utiliser ce rythme pour les objectifs du chapitre")
            } else if savedProfile != nil {
                Button("Retirer") {
                    store.updatePacing(chapterId: chapter.id, in: projectId) { $0.profile = nil; $0.startDate = nil }
                }
                .buttonStyle(.pressable)
                .font(.system(size: AppLook.fs(11)))
                .foregroundColor(.labelMuted)
                .help("Revenir au calcul linéaire d'avant")
            }
        }
    }

    private func summary(_ plan: PacingPlan) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Aujourd'hui")
                    .font(.system(size: AppLook.fs(11)))
                    .foregroundColor(.labelMuted)
                Text(store.formatCount(plan.todayQuota))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentWarm)
                if let pages = store.formatPages(plan.todayQuota) {
                    Text("(\(pages))").font(.system(size: AppLook.fs(11))).foregroundColor(.labelMuted)
                }
                Spacer()
                Text("\(plan.workingDaysLeft) jour(s) ouvré(s) · reste \(store.formatCount(plan.remaining))")
                    .font(.system(size: AppLook.fs(11)))
                    .foregroundColor(.labelMuted)
            }
            Text(shownProfile.summary + (preview != nil ? " Aperçu : rien n'est enregistré." : ""))
                .font(.system(size: AppLook.fs(10)))
                .foregroundColor(.labelMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Jours ouvrés du chapitre

    private static let weekdays: [(value: Int, letter: String, name: String)] = [
        (2, "L", "lundi"), (3, "M", "mardi"), (4, "M", "mercredi"), (5, "J", "jeudi"),
        (6, "V", "vendredi"), (7, "S", "samedi"), (1, "D", "dimanche")
    ]

    private var weekdayPicker: some View {
        let selected = Set(chapter.pacing?.workWeekdays ?? [])
        return HStack(spacing: 4) {
            Text("Jours ouvrés")
                .font(.system(size: AppLook.fs(11)))
                .foregroundColor(.labelMuted)
            ForEach(Self.weekdays, id: \.value) { day in
                let on = selected.contains(day.value)
                Button {
                    store.updatePacing(chapterId: chapter.id, in: projectId) { pacing in
                        var days = Set(pacing.workWeekdays ?? [])
                        if on { days.remove(day.value) } else { days.insert(day.value) }
                        pacing.workWeekdays = days.sorted()
                    }
                } label: {
                    Text(day.letter)
                        .font(.system(size: AppLook.fs(10), weight: .semibold))
                        .frame(width: 20, height: 20)
                        .foregroundColor(on ? .black : .labelMuted)
                        .background(Circle().fill(on ? Color.accentWarm : Color.cardBg))
                        .overlay(Circle().stroke(on ? Color.clear : Color.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .help(day.name)
                .accessibilityLabel(day.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Text(selected.isEmpty ? "Calendrier général" : "Propres à ce chapitre")
                .font(.system(size: AppLook.fs(10)))
                .foregroundColor(.labelMuted)
                .padding(.leading, 4)
        }
    }
}

// MARK: - Courbe

struct PacingCurveView: View {
    let plan: PacingPlan

    private struct Geometry {
        let width: CGFloat, height: CGFloat, step: CGFloat, top: Double
        func x(_ t: Double) -> CGFloat { CGFloat(t) * (width - step) + step / 2 }
        func y(_ v: Double) -> CGFloat { height - CGFloat(v / top) * height }
        var barWidth: CGFloat { max(1.5, step * 0.6) }
        func bar(t: Double, value: Double) -> CGRect {
            CGRect(x: x(t) - barWidth / 2, y: y(value), width: barWidth, height: height - y(value))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let days = plan.days
            let maxBars = days.map { Double(max($0.quota, $0.written)) }.max() ?? 0
            let maxCurve = (0...50).map { plan.scaledWeight(at: Double($0) / 50) }.max() ?? 0
            let g = Geometry(width: proxy.size.width, height: proxy.size.height - 12,
                             step: proxy.size.width / CGFloat(max(1, days.count)),
                             top: max(1, maxBars, maxCurve) * 1.15)
            let today = days.first { $0.isToday }
            ZStack(alignment: .topLeading) {
                // Texte écrit les jours passés
                Path { p in
                    for day in days where (day.isPast || day.isToday) && day.written > 0 {
                        p.addRect(g.bar(t: day.t, value: Double(day.written)))
                    }
                }
                .fill(Color.accentGreen.opacity(0.5))
                // Quotas des jours à venir
                Path { p in
                    for day in days where !day.isPast && day.quota > 0 {
                        p.addRect(g.bar(t: day.t, value: Double(day.quota)))
                    }
                }
                .fill(Color.accentWarm.opacity(0.3))
                // Jours non ouvrés : points sous l'axe
                Path { p in
                    for day in days where !day.isWorkingDay {
                        p.addEllipse(in: CGRect(x: g.x(day.t) - 1.5, y: g.height + 3, width: 3, height: 3))
                    }
                }
                .fill(Color.labelMuted.opacity(0.6))
                // Courbe continue du profil
                Path { p in
                    for i in 0...100 {
                        let t = Double(i) / 100
                        let point = CGPoint(x: g.x(t), y: g.y(plan.scaledWeight(at: t)))
                        if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                    }
                }
                .stroke(Color.accentWarm, lineWidth: 1.8)
                // Repère « Aujourd'hui »
                if let today {
                    let tx = g.x(today.t)
                    let ty = g.y(plan.scaledWeight(at: today.t))
                    Path { p in
                        p.move(to: CGPoint(x: tx, y: 0))
                        p.addLine(to: CGPoint(x: tx, y: g.height))
                    }
                    .stroke(Color.primary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Circle()
                        .fill(Color.accentWarm)
                        .frame(width: 7, height: 7)
                        .shadow(color: Color.accentWarm.opacity(0.9), radius: 5)
                        .position(x: tx, y: ty)
                    Text("Aujourd'hui")
                        .font(.system(size: AppLook.fs(10), weight: .medium))
                        .foregroundColor(.labelMuted)
                        .fixedSize()
                        .position(x: min(max(tx, 30), g.width - 30), y: 6)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Courbe de rythme \(plan.profile.label) : \(plan.todayQuota) caractères aujourd'hui, \(plan.workingDaysLeft) jours ouvrés restants")
    }
}
