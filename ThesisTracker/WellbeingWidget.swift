import SwiftUI

// MARK: - Bien-être : énergie + jours de repos (#4 + #5)

/// Widget combinant le slider d'énergie du jour et le bouton "jour de repos".
struct WellbeingWidget: View {
    @ObservedObject var store: DataStore
    @State private var localEnergy: Int? = nil
    @State private var didLoad = false

    private var today: String { DataStore.today }
    private var isRest: Bool { store.isRestDay(today) }
    private var todayEnergy: Int? { store.energyLevel(for: today) }
    private var history: [(date: String, energy: Int)] { store.energyHistory(days: 14) }
    private var avgEnergy: Double? {
        let recent = history.suffix(7)
        guard !recent.isEmpty else { return nil }
        return Double(recent.reduce(0) { $0 + $1.energy }) / Double(recent.count)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppLook.r(8, 12))
                            .fill(Color(red: 0.961, green: 0.620, blue: 0.043).opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(red: 0.961, green: 0.620, blue: 0.043))
                    }
                    Text("Énergie & repos")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if let avg = avgEnergy {
                        Text("Moy. 7j · \(String(format: "%.1f", avg))/5")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.labelMuted)
                    }
                }

                if isRest {
                    restDayBanner
                } else {
                    energySection
                }

                if !history.isEmpty { miniHistory }   // 5.18 : pas de bloc vide

                actionsRow
            }
        }
        .onAppear {
            if !didLoad { localEnergy = todayEnergy; didLoad = true }
        }
        .onChange(of: store.dataVersion) { _ in
            localEnergy = todayEnergy
        }
    }

    // MARK: - Sections

    private var energySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Niveau d'énergie aujourd'hui")
                    .font(.system(size: 11)).foregroundColor(.labelMuted)
                Spacer()
                if let lvl = localEnergy {
                    Text(energyLabel(lvl))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(energyColor(lvl))
                }
            }
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { lvl in
                    Button {
                        if localEnergy == lvl {
                            localEnergy = nil
                            commitEnergy(nil)
                        } else {
                            localEnergy = lvl
                            commitEnergy(lvl)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(localEnergy ?? 0 >= lvl ? energyColor(lvl).opacity(0.85) : Color.labelMuted.opacity(0.12))
                                .frame(width: 26, height: 26)
                            Text("\(lvl)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(localEnergy ?? 0 >= lvl ? .white : .labelMuted)
                        }
                    }
                    .buttonStyle(.pressable)
                    .help(energyLabel(lvl))
                }
            }
        }
    }

    private var restDayBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.fill")
                .foregroundColor(Color.labelMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text("Jour de repos planifié")
                    .font(.system(size: 12, weight: .semibold))
                Text("Pas d'objectif. Tu reviens demain.")
                    .font(.system(size: 10)).foregroundColor(.labelMuted)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.labelMuted.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
    }

    private var miniHistory: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("14 DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.labelMuted.opacity(0.7))
                .kerning(0.6)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<14, id: \.self) { offset in
                    let dateStr = dateString(daysAgo: 13 - offset)
                    let rest = store.isRestDay(dateStr)
                    let energy = history.first { $0.date == dateStr }?.energy
                    barCell(energy: energy, isRest: rest)
                }
            }
            .frame(height: 26)
        }
    }

    private func barCell(energy: Int?, isRest: Bool) -> some View {
        let height: CGFloat = {
            guard let e = energy else { return 6 }
            return CGFloat(e) * 5.2
        }()
        return VStack(spacing: 1) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2)
                .fill(barColor(energy: energy, isRest: isRest))
                .frame(maxWidth: .infinity)
                .frame(height: max(4, height))
        }
        .frame(height: 26)
    }

    private func barColor(energy: Int?, isRest: Bool) -> Color {
        if isRest { return Color.labelMuted.opacity(0.55) }
        guard let e = energy else { return Color.labelMuted.opacity(0.15) }
        return energyColor(e)
    }

    private var actionsRow: some View {
        HStack(spacing: 6) {
            Button {
                store.toggleRestDay(today)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isRest ? "checkmark.circle.fill" : "moon")
                        .font(.system(size: 11))
                    Text(isRest ? "Annuler le repos" : "Jour de repos")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(isRest ? .white : Color.labelMuted)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(isRest ? Color.labelMuted : Color.labelMuted.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.pressable)
        }
    }

    // MARK: - Helpers

    private func commitEnergy(_ level: Int?) {
        guard let chapter = store.activeChapter, let project = store.activeProject else { return }
        // Vérifier que l'entrée du jour existe ; sinon, l'app va probablement la créer
        // au moment de la première saisie. On n'écrit que si l'entrée existe pour
        // éviter de créer un fantôme à 0 caractère.
        guard chapter.entries.contains(where: { $0.date == today }) else { return }
        store.setEnergyLevel(level, for: today, chapterId: chapter.id, in: project.id)
    }

    private func energyColor(_ level: Int) -> Color {
        switch level {
        case 1: return Color(red: 0.93, green: 0.26, blue: 0.26)
        case 2: return Color(red: 0.95, green: 0.50, blue: 0.20)
        case 3: return Color(red: 0.95, green: 0.75, blue: 0.20)
        case 4: return Color(red: 0.50, green: 0.75, blue: 0.30)
        case 5: return Color(red: 0.22, green: 0.75, blue: 0.44)
        default: return .labelMuted
        }
    }

    private func energyLabel(_ level: Int) -> String {
        switch level {
        case 1: return "Épuisé"
        case 2: return "Bas"
        case 3: return "Moyen"
        case 4: return "Bon"
        case 5: return "Excellent"
        default: return ""
        }
    }

    private func dateString(daysAgo: Int) -> String {
        let cal = DataStore.gregorianCal
        guard let d = cal.date(byAdding: .day, value: -daysAgo, to: Date()) else { return "" }
        return DataStore.dateString(from: d)
    }
}
