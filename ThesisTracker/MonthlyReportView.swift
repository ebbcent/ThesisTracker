import SwiftUI

// MARK: - Bilan mensuel automatique

struct MonthlyReportWidget: View {
    @ObservedObject var store: DataStore
    @State private var showSheet = false

    private var reports: [MonthlyReport] {
        store.data.monthlyReports.sorted { $0.monthKey > $1.monthKey }
    }
    private var latest: MonthlyReport? { reports.first }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppLook.r(8, 12))
                            .fill(Color.semSky.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.semSky)
                    }
                    Text("Bilans mensuels")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(reports.count)")
                        .font(.system(size: AppLook.fs(10), weight: .semibold))
                        .foregroundColor(.labelMuted)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.labelMuted.opacity(0.1))
                        .clipShape(Capsule())
                }
                if let latest {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(monthLabel(latest.monthKey))
                            .font(.system(size: 12, weight: .semibold))
                        Text(latest.headline)
                            .font(.system(size: AppLook.fs(11)))
                            .foregroundColor(.labelMuted)
                            .lineLimit(2)
                    }
                } else {
                    Text("Le premier bilan sera généré automatiquement le 1er du mois suivant.")
                        .font(.system(size: AppLook.fs(11)))
                        .foregroundColor(.labelMuted)
                }
                Button { showSheet = true } label: {
                    Text(reports.isEmpty ? "Voir le détail" : "Lire les bilans")
                        .font(.system(size: AppLook.fs(11), weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.semSky)
                        .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .sheet(isPresented: $showSheet) {
            MonthlyReportSheet(store: store)
        }
    }

    private static let monthFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "MMMM yyyy"
        return f
    }()
    private func monthLabel(_ key: String) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM"
        guard let d = fmt.date(from: key) else { return key }
        let s = Self.monthFmt.string(from: d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

// MARK: - Sheet liste + détail

struct MonthlyReportSheet: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedKey: String? = nil
    @State private var notesDraft: String = ""

    private var reports: [MonthlyReport] {
        store.data.monthlyReports.sorted { $0.monthKey > $1.monthKey }
    }
    private var selected: MonthlyReport? {
        reports.first { $0.monthKey == selectedKey } ?? reports.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if reports.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    list
                    Divider()
                    detail
                }
            }
        }
        .sheetFrame(width: 720, height: 520)
        .onAppear {
            if selectedKey == nil, let first = reports.first {
                selectedKey = first.monthKey
                notesDraft = first.userNotes ?? ""
            }
        }
        .onChange(of: selectedKey) { _, new in
            notesDraft = reports.first { $0.monthKey == new }?.userNotes ?? ""
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bilans mensuels").font(.system(size: 16, weight: .semibold))
                Text("\(reports.count) bilan\(reports.count > 1 ? "s" : "")")
                    .font(.system(size: AppLook.fs(11))).foregroundColor(.labelMuted)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.labelMuted)
            }
            .buttonStyle(.pressable)
            .help("Fermer")
            .accessibilityLabel("Fermer")
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 32))
                .foregroundColor(.labelMuted.opacity(0.5))
            Text("Aucun bilan pour l'instant")
                .font(.system(size: 13))
                .foregroundColor(.labelMuted)
            Text("Le premier bilan apparaîtra le 1er du mois suivant le début d'utilisation.")
                .font(.system(size: AppLook.fs(11)))
                .foregroundColor(.labelMuted.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(reports) { report in
                    Button { selectedKey = report.monthKey } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(.system(size: AppLook.fs(11)))
                                .foregroundColor(.labelMuted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(monthLabel(report.monthKey))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("\(report.charsWritten.formatted()) car. · \(report.daysActive) j")
                                    .font(.system(size: AppLook.fs(10)))
                                    .foregroundColor(.labelMuted)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(selectedKey == report.monthKey ? Color.accent.opacity(0.10) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    Divider()
                }
            }
        }
        .frame(width: 240)
    }

    @ViewBuilder
    private var detail: some View {
        if let r = selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(monthLabel(r.monthKey))
                        .font(.system(size: 20, weight: .bold, design: AppLook.fontDesign))
                    Text(r.headline)
                        .font(.system(size: 13))
                        .foregroundColor(.labelMuted)
                    HStack(spacing: 10) {
                        statTile(label: "Caractères", value: r.charsWritten.formatted())
                        statTile(label: "Jours actifs", value: "\(r.daysActive)")
                        statTile(label: "Chap. finis", value: "\(r.chaptersFinished)")
                    }
                    HStack(spacing: 10) {
                        if let best = r.bestDay {
                            statTile(label: "Meilleur jour", value: best)
                        }
                        statTile(label: "Série en fin de mois", value: "\(r.streakAtMonthEnd) j")
                    }
                    Divider()
                    Text("RÉFLEXION LIBRE")
                        .font(.system(size: AppLook.fs(10), weight: .bold))
                        .foregroundColor(.labelMuted).kerning(0.8)
                    TextEditor(text: $notesDraft)
                        .font(.system(size: 12))
                        .frame(minHeight: 100)
                        .padding(6)
                        .background(Color.fieldBg)
                        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
                    Button {
                        store.updateMonthlyReportNotes(monthKey: r.monthKey, notes: notesDraft)
                    } label: {
                        Text("Enregistrer la réflexion")
                            .font(.system(size: AppLook.fs(11), weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Sélectionne un bilan")
                .foregroundColor(.labelMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: AppLook.fs(10), weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(0.6)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
        .overlay(RoundedRectangle(cornerRadius: AppLook.r(8, 12)).stroke(Color.cardBorder, lineWidth: 1))
    }

    private static let monthFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "MMMM yyyy"
        return f
    }()
    private func monthLabel(_ key: String) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM"
        guard let d = fmt.date(from: key) else { return key }
        let s = Self.monthFmt.string(from: d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
