import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: DataStore
    let chapter: Chapter
    let projectId: UUID
    @Environment(\.dismiss) var dismiss
    @State private var entryToDelete: DailyEntry? = nil

    private var currentChapter: Chapter? {
        store.data.projects.first(where: { $0.id == projectId })?.chapters.first(where: { $0.id == chapter.id })
    }

    private var sortedEntries: [DailyEntry] {
        (currentChapter?.entries ?? []).sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Historique")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text(chapter.name)
                            .font(.system(size: 13))
                            .foregroundColor(.labelMuted)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.labelMuted)
                            .padding(8)
                            .background(Color.cardBg)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Fermer")
                    .accessibilityLabel("Fermer")
                }
                .padding(20)

                Divider()

                if sortedEntries.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(.labelMuted.opacity(0.6))
                        Text("Aucune entrée pour ce chapitre")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.labelMuted)
                        Text("Les saisies quotidiennes apparaîtront ici dès que tu en enregistreras une.")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 40)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(sortedEntries) { entry in
                                HistoryRow(
                                    entry: entry,
                                    chapter: currentChapter,
                                    onDelete: { entryToDelete = entry }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 360)
        .alert("Supprimer cette entrée ?", isPresented: Binding(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }
        )) {
            Button("Supprimer", role: .destructive) {
                if let entry = entryToDelete {
                    store.deleteEntry(for: chapter.id, in: projectId, date: entry.date)
                    entryToDelete = nil
                }
            }
            Button("Annuler", role: .cancel) { entryToDelete = nil }
        } message: {
            if let entry = entryToDelete {
                Text("L'entrée du \(formattedDate(entry.date)) sera supprimée définitivement.")
            }
        }
    }

    private func formattedDate(_ dateStr: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dateStr) else { return dateStr }
        let out = DateFormatter()
        out.locale = Locale(identifier: "fr_FR")
        out.dateFormat = "d MMMM yyyy"
        return out.string(from: date)
    }
}

struct HistoryRow: View {
    let entry: DailyEntry
    let chapter: Chapter?
    let onDelete: () -> Void

    private var increment: Int {
        guard let chapter = chapter else { return 0 }
        return chapter.increment(for: entry.date)
    }

    private var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: entry.date) else { return entry.date }
        let out = DateFormatter()
        out.locale = Locale(identifier: "fr_FR")
        out.dateFormat = "EEEE d MMMM yyyy"
        let str = out.string(from: date)
        return str.prefix(1).uppercased() + str.dropFirst()
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Text(formatNumber(entry.totalCount) + " car. total")
                        .font(.system(size: 12))
                        .foregroundColor(.labelMuted)

                    if increment > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 9))
                            Text("+\(formatNumber(increment))")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Color.accentGreen)
                    }
                }

                // V5 — #7 : Note de séance
                if let note = entry.note, !note.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.system(size: 9))
                            .foregroundColor(.labelMuted.opacity(0.6))
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                            .italic()
                            .lineLimit(2)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.95, green: 0.35, blue: 0.35))
                    .padding(8)
                    .background(Color(red: 0.95, green: 0.35, blue: 0.35).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Supprimer")
            .accessibilityLabel("Supprimer")
        }
        .padding(14)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
    }

    private func formatNumber(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{202F}"
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
