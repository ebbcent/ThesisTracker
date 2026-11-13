import SwiftUI

// MARK: - Feature #6 : Historique d'édition d'une entrée journalière

struct EntryEditHistoryPopover: View {
    let entry: DailyEntry
    let useWords: Bool

    private func fmt(_ v: Int) -> String {
        useWords ? "\(DataStore.formatNumber(v / 5)) mots" : "\(DataStore.formatNumber(v)) car."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accent)
                Text("Historique des modifications")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text(entry.date)
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            Divider()

            if entry.editHistory.isEmpty {
                Text("Aucune modification enregistrée")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
                    .padding(14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(entry.editHistory.reversed(), id: \.timestamp) { rec in
                            editRow(rec)
                            if rec.timestamp != entry.editHistory.first?.timestamp {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .frame(width: 280)
        .background(AppBackdrop())
    }

    private func editRow(_ rec: EntryEditRecord) -> some View {
        HStack(spacing: 10) {
            // Delta indicator
            let isUp = rec.delta > 0
            ZStack {
                Circle()
                    .fill(isUp ? Color.accentGreen.opacity(0.12) : Color.accentWarm.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: isUp ? "arrow.up" : "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isUp ? .accentGreen : .accentWarm)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(fmt(rec.oldValue))
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                        .strikethrough()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted)
                    Text(fmt(rec.newValue))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }
                HStack(spacing: 4) {
                    let sign = rec.delta > 0 ? "+" : ""
                    Text("\(sign)\(fmt(abs(rec.delta)))")
                        .font(.system(size: 10))
                        .foregroundColor(isUp ? .accentGreen : .accentWarm)
                    Text("·")
                        .font(.system(size: 10)).foregroundColor(.labelMuted)
                    Text(rec.timestamp)
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}
