import SwiftUI

// MARK: - Feature #4 : Rapport directeur (rapport de période ciblé)

struct DirectorReportSheet: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) private var dismiss

    enum Period: String, CaseIterable, Identifiable {
        case oneWeek    = "1 semaine"
        case twoWeeks   = "2 semaines"
        case oneMonth   = "1 mois"
        case custom     = "Personnalisé"
        var id: String { rawValue }
    }

    @State private var period: Period = .twoWeeks
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()
    @State private var copied = false

    private var dateRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .oneWeek:   return (cal.date(byAdding: .day, value: -7, to: now)!, now)
        case .twoWeeks:  return (cal.date(byAdding: .day, value: -14, to: now)!, now)
        case .oneMonth:  return (cal.date(byAdding: .month, value: -1, to: now)!, now)
        case .custom:    return (customStart, customEnd)
        }
    }

    private var startStr: String { DataStore.dateString(from: dateRange.start) }
    private var endStr:   String { DataStore.dateString(from: dateRange.end) }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            periodSelector
            Divider()
            reportBody
        }
        .frame(width: 640, height: 720)
        .background(Color.cardBg)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(hex: "#0369A1").opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "#0369A1"))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Rapport pour le directeur")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Synthèse par chapitre · prêt à copier")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(generateReport(), forType: .string)
                withAnimation(.easeOut(duration: 0.15)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { copied = false } }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.clipboard")
                        .font(.system(size: 13))
                    Text(copied ? "Copié !" : "Copier")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(copied ? .accentGreen : .white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(copied ? Color.accentGreen.opacity(0.12) : Color(hex: "#0369A1"))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(copied ? Color.accentGreen.opacity(0.3) : Color.clear, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.labelMuted).padding(7)
                    .background(Circle().fill(Color.glassFill))
                    .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Fermer")
            .accessibilityLabel("Fermer")
        }
        .padding(20)
    }

    // MARK: - Period selector

    private var periodSelector: some View {
        HStack(spacing: 12) {
            ForEach(Period.allCases) { p in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { period = p }
                } label: {
                    Text(p.rawValue)
                        .font(.system(size: 12, weight: period == p ? .semibold : .regular))
                        .foregroundColor(period == p ? .white : .labelMuted)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(period == p ? Color(hex: "#0369A1") : Color.fieldBg)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            if period == .custom {
                DatePicker("", selection: $customStart, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                Text("→").foregroundColor(.labelMuted)
                DatePicker("", selection: $customEnd, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    // MARK: - Report body

    private var reportBody: some View {
        ScrollView {
            Text(generateReport())
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .textSelection(.enabled)
        }
        .background(Color.fieldBg.opacity(0.4))
    }

    // MARK: - Report generation

    private func generateReport() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMMM yyyy"
        let startLabel = fmt.string(from: dateRange.start)
        let endLabel   = fmt.string(from: dateRange.end)

        var lines: [String] = []
        lines.append("RAPPORT DE SUIVI — \(startLabel) au \(endLabel)")
        lines.append(String(repeating: "═", count: 60))
        lines.append("")

        // Stats globales sur la période
        let allEntries = store.data.projects
            .flatMap(\.chapters)
            .flatMap(\.entries)
            .filter { $0.date >= startStr && $0.date <= endStr }
        let totalChars = allEntries.reduce(0) { $0 + $1.totalCount }
        let activeDays = Set(allEntries.map(\.date)).count
        let totalWords = totalChars / 5

        lines.append("RÉSUMÉ DE LA PÉRIODE")
        lines.append(String(repeating: "─", count: 40))
        lines.append("• Total écrit   : \(DataStore.formatNumber(totalChars)) car. ≈ \(DataStore.formatNumber(totalWords)) mots")
        lines.append("• Jours actifs  : \(activeDays)")
        lines.append("• Streak actuel : \(store.currentStreak) jour\(store.currentStreak > 1 ? "s" : "")")

        // Recherche sur la période
        let researchEntries = store.data.researchEntries.filter { $0.date >= startStr && $0.date <= endStr }
        let totalResearchMins = researchEntries.reduce(0) { $0 + $1.durationMinutes }
        if totalResearchMins > 0 {
            let h = totalResearchMins / 60, m = totalResearchMins % 60
            let durationStr = m == 0 ? "\(h) h" : "\(h) h \(m) min"
            lines.append("• Temps recherche : \(durationStr)")
        }
        lines.append("")

        // Par projet actif
        let activeProjects = store.data.projects.filter { !$0.isArchived }
        for project in activeProjects {
            let projectEntries = project.chapters
                .flatMap(\.entries)
                .filter { $0.date >= startStr && $0.date <= endStr }
            guard !projectEntries.isEmpty else { continue }

            let projChars = projectEntries.reduce(0) { $0 + $1.totalCount }
            let projWords = projChars / 5
            lines.append("PROJET : \(project.name.uppercased())")
            lines.append(String(repeating: "─", count: 40))
            if let supervisor = project.supervisor, !supervisor.isEmpty {
                lines.append("  Directeur : \(supervisor)")
            }
            lines.append("  Total période : \(DataStore.formatNumber(projChars)) car. ≈ \(DataStore.formatNumber(projWords)) mots")
            lines.append("")

            for chapter in project.chapters {
                let chEntries = chapter.entries.filter { $0.date >= startStr && $0.date <= endStr }
                guard !chEntries.isEmpty else { continue }
                let chChars = chEntries.reduce(0) { $0 + $1.totalCount }
                let chWords = chChars / 5
                let latest  = store.latestTotal(for: chapter.id, in: project.id)
                let pct     = chapter.goal > 0 ? Int(Double(latest) / Double(chapter.goal) * 100) : 0

                lines.append("  § \(chapter.name)")
                lines.append("    Écrit cette période : +\(DataStore.formatNumber(chChars)) car. (+\(DataStore.formatNumber(chWords)) mots)")
                if chapter.goal > 0 {
                    lines.append("    Avancement global   : \(DataStore.formatNumber(latest)) / \(DataStore.formatNumber(chapter.goal)) car. (\(pct)%)")
                }
                if let status = chapter.status {
                    lines.append("    Statut              : \(status.label)")
                }
                if let nextStep = chapter.nextStep, !nextStep.isEmpty {
                    lines.append("    ➤ Prochaine étape   : \(nextStep)")
                }
                if let blocker = chapter.notesBlockers, !blocker.isEmpty {
                    lines.append("    ⚠ Blocage en cours  : \(blocker.prefix(120))")
                }
                if let dl = chapter.deadline {
                    lines.append("    Deadline            : \(dl)")
                }
                lines.append("")
            }

            // Jalons du projet sur la période
            let upcomingMilestones = project.milestones.filter {
                $0.date >= startStr && $0.date <= endStr && !$0.isCompleted
            }
            if !upcomingMilestones.isEmpty {
                lines.append("  Jalons à venir :")
                for m in upcomingMilestones {
                    lines.append("    · \(m.title) — \(m.date)")
                }
                lines.append("")
            }
        }

        // Séances de recherche
        if !researchEntries.isEmpty {
            lines.append("ACTIVITÉS DE RECHERCHE")
            lines.append(String(repeating: "─", count: 40))
            let byType = Dictionary(grouping: researchEntries) { $0.type }
            for type in ResearchType.allCases {
                guard let entries = byType[type] else { continue }
                let mins = entries.reduce(0) { $0 + $1.durationMinutes }
                let h = mins / 60, m = mins % 60
                let dur = m == 0 ? "\(h) h" : h > 0 ? "\(h) h \(m) min" : "\(m) min"
                lines.append("  \(type.label) : \(dur)")
                for e in entries {
                    if let note = e.note, !note.isEmpty {
                        lines.append("    · \(note)")
                    }
                }
            }
            lines.append("")
        }

        lines.append("Rapport généré le \(fmt.string(from: Date())) — Writing Process")

        return lines.joined(separator: "\n")
    }
}
