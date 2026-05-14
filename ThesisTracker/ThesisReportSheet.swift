import SwiftUI
import AppKit

// MARK: - V3.4 · Rapport de suivi pour directeur de thèse
// Fichier isolé. Déclenché depuis le bouton "Rapport" dans OverviewView.
// Génère un rapport texte structuré, lisible, copiable en un clic.

struct ThesisReportSheet: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var report: String { generateReport() }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            reportBody
        }
        .frame(width: 620, height: 700)
        .background(Color.cardBg)
    }

    // ── Header ─────────────────────────────────────

    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accent.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Rapport de suivi")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Prêt à partager avec ton directeur de thèse")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
            }

            Spacer()

            // Bouton copier
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report, forType: .string)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { copied = false }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.clipboard")
                        .font(.system(size: 13))
                    Text(copied ? "Copié !" : "Copier le rapport")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(copied ? .accentGreen : .white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(copied ? Color.accentGreen.opacity(0.15) : Color.accent)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(copied ? Color.accentGreen.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // Bouton fermer
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.labelMuted)
                    .padding(7)
                    .background(Circle().fill(Color.glassFill))
                    .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    // ── Preview du rapport ─────────────────────────

    private var reportBody: some View {
        ScrollView {
            Text(report)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .textSelection(.enabled)
        }
        .background(Color.fieldBg.opacity(0.5))
    }

    // ── Générateur ────────────────────────────────

    private func generateReport() -> String {
        let cal    = Calendar(identifier: .gregorian)
        let totals = store.dailyTotals()

        // ── Stats 30 jours ──────────────────────
        var monthChars      = 0
        var monthActiveDays = 0
        var monthGoalDays   = 0
        var monthBestDay    = 0
        for i in 0..<30 {
            guard let date = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let val = totals[DataStore.dateString(from: date)] ?? 0
            monthChars += val
            if val > 0 { monthActiveDays += 1 }
            if store.data.dailyGoal > 0 && val >= store.data.dailyGoal { monthGoalDays += 1 }
            if val > monthBestDay { monthBestDay = val }
        }

        // ── Format date ─────────────────────────
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "fr_FR")
        dateFmt.dateFormat = "d MMMM yyyy"
        let today = dateFmt.string(from: Date()).capitalized

        // ── Défis ────────────────────────────────
        let completedChallenges = store.data.weeklyChallenges.filter { $0.isCompleted }.count
        let totalChallenges     = store.data.weeklyChallenges.count

        // ── Build ────────────────────────────────
        var lines: [String] = []

        // En-tête
        lines += [
            "╔══════════════════════════════════════════════╗",
            "║     RAPPORT DE SUIVI — THÈSE                 ║",
            "╚══════════════════════════════════════════════╝",
            "",
            "Date      : \(today)",
            "Généré par : Writing Process · ThesisTracker V3.4",
            "",
        ]

        // Section production
        lines += [
            "══════════════════════════════════════════════",
            "  PRODUCTION — 30 DERNIERS JOURS",
            "══════════════════════════════════════════════",
            "",
            "  Caractères écrits   : \(store.formatCount(monthChars))",
            "  Jours d'écriture    : \(monthActiveDays) / 30",
        ]
        if store.data.dailyGoal > 0 {
            lines.append("  Objectif quotidien  : atteint \(monthGoalDays) fois / 30 jours")
        }
        lines += [
            "  Meilleure journée   : \(store.formatCount(monthBestDay))",
            "  Série actuelle      : \(store.currentStreak) jour(s) consécutif(s)",
        ]
        if let bw = store.bestWeekStat {
            lines.append("  Meilleure semaine   : \(store.formatCount(bw.chars)) (\(bw.label))")
        }
        lines.append("")

        // Section chapitres
        lines += [
            "══════════════════════════════════════════════",
            "  CHAPITRES",
            "══════════════════════════════════════════════",
            "",
        ]

        for project in store.data.projects.filter({ !$0.isArchived }) {
            lines.append("  Projet : \(project.name)")
            if let supervisor = project.supervisor, !supervisor.isEmpty {
                lines.append("  Directeur : \(supervisor)")
            }
            lines.append("")

            for chapter in project.chapters {
                let latest      = chapter.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
                let statusLabel = chapter.isCompleted ? "Terminé"
                    : (chapter.status?.label ?? "En cours")
                let name        = padRight(chapter.name, 22)
                let status      = padRight(statusLabel, 12)

                if chapter.goal > 0 {
                    let pct = Int(min(100, Double(latest) / Double(chapter.goal) * 100))
                    let bar = progressBar(ratio: Double(latest) / Double(chapter.goal))
                    lines.append("  • \(name) [\(status)]  \(padLeft(store.formatCount(latest), 8)) / \(padLeft(store.formatCount(chapter.goal), 8))  (\(padLeft("\(pct)%", 4)))  \(bar)")
                } else {
                    lines.append("  • \(name) [\(status)]  \(store.formatCount(latest)) (sans objectif)")
                }
            }
            lines.append("")
        }

        // Section avancement global
        let allChapters    = store.data.projects.flatMap { $0.chapters }
        let completedCount = allChapters.filter { $0.isCompleted }.count
        let remaining      = store.thesisRemainingChars
        let velocity       = store.velocity14Days

        lines += [
            "══════════════════════════════════════════════",
            "  AVANCEMENT GLOBAL",
            "══════════════════════════════════════════════",
            "",
            "  Chapitres terminés  : \(completedCount) / \(allChapters.count)",
        ]

        if remaining > 0 {
            lines.append("  Restant à écrire    : \(store.formatCount(remaining)) (chapitres avec objectif)")
        } else if !allChapters.filter({ $0.goal > 0 }).isEmpty {
            lines.append("  Restant à écrire    : Tous les objectifs atteints ✓")
        }

        if velocity > 0 {
            lines.append("  Cadence actuelle    : \(store.formatCount(velocity))/j (moy. 14 jours)")
        }

        if let projDays = store.thesisProjectedDays, projDays > 0 {
            if let target = cal.date(byAdding: .day, value: projDays, to: Date()) {
                let projFmt = DateFormatter()
                projFmt.locale = Locale(identifier: "fr_FR")
                projFmt.dateFormat = "MMMM yyyy"
                let dateStr = projFmt.string(from: target).capitalized
                lines.append("  Fin estimée         : \(dateStr) (dans ~\(projDays) jours)")
            }
        }

        // Section défis
        if totalChallenges > 0 {
            lines += [
                "",
                "══════════════════════════════════════════════",
                "  DÉFIS HEBDOMADAIRES",
                "══════════════════════════════════════════════",
                "",
                "  Défis relevés       : \(completedChallenges) / \(totalChallenges)",
            ]
        }

        // Pied
        lines += [
            "",
            "══════════════════════════════════════════════",
            "",
            "— Rapport généré automatiquement",
            "  Writing Process · ThesisTracker · \(today)",
        ]

        return lines.joined(separator: "\n")
    }

    // ── Helpers ───────────────────────────────────

    private func progressBar(ratio: Double) -> String {
        let filled = min(10, Int(ratio * 10))
        return "[" + String(repeating: "█", count: filled)
                   + String(repeating: "░", count: 10 - filled) + "]"
    }

    private func padRight(_ s: String, _ length: Int) -> String {
        s.count >= length ? String(s.prefix(length)) : s + String(repeating: " ", count: length - s.count)
    }

    private func padLeft(_ s: String, _ length: Int) -> String {
        s.count >= length ? s : String(repeating: " ", count: length - s.count) + s
    }
}
