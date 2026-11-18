import SwiftUI

// MARK: - Journées sans écriture : archives, séminaire, repos (5.12)
// Le quota du jour passe à 0, la série n'est pas cassée et la journée ne
// compte pas dans les moyennes de vitesse (si rien n'y a été écrit).

/// Bouton du tableau de bord pour la date sélectionnée.
struct DayOffMenuButton: View {
    @ObservedObject var store: DataStore
    let date: String
    @State private var showManager = false

    var body: some View {
        let kind = store.dayOffKind(for: date)
        Menu {
            ForEach(DayOffKind.allCases) { option in
                Button {
                    store.toggleDayOff(date, kind: option)
                } label: {
                    Label(kind == option ? "\(option.label) (retirer)" : option.label, systemImage: option.symbol)
                }
            }
            if kind != nil {
                Divider()
                Button("Journée d'écriture normale") { store.setDayOff(date, kind: nil) }
            }
            Divider()
            Button("Gérer les journées sans écriture…") { showManager = true }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: kind?.symbol ?? "archivebox")
                    .font(.system(size: AppLook.fs(10)))
                Text(kind?.label ?? "Archives / Repos")
                    .font(.system(size: AppLook.fs(11), weight: .medium))
            }
            .foregroundColor(kind != nil ? .accentWarm : .labelMuted)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(kind != nil ? Color.accentWarm.opacity(0.12) : Color.clear)
                .overlay(Capsule().stroke(kind != nil ? Color.accentWarm.opacity(0.25) : Color.cardBorder, lineWidth: 1)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Journée d'archives, de séminaire ou de repos : pas d'objectif, la série continue")
        .sheet(isPresented: $showManager) {
            DaysOffManagerSheet(store: store)
        }
    }
}

/// Liste des journées sans écriture, ajout à l'avance et retrait.
struct DaysOffManagerSheet: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var newDate = Date()
    @State private var newKind: DayOffKind = .archives
    @State private var showPast = false

    private var today: String { DataStore.today }

    var body: some View {
        let all = store.daysOffSorted
        let upcoming = all.filter { $0.date >= today }
        let past = all.filter { $0.date < today }.reversed()
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Journées sans écriture")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Text("Archives, séminaires, repos : pas d'objectif ces jours-là, la série continue, et les moyennes de vitesse les ignorent si rien n'y est écrit.")
                .font(.system(size: AppLook.fs(11)))
                .foregroundColor(.labelMuted)
                .fixedSize(horizontal: false, vertical: true)

            // Ajout
            HStack(spacing: 8) {
                DatePicker("", selection: $newDate, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "fr_FR"))
                Picker("", selection: $newKind) {
                    ForEach(DayOffKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)
                Button("Ajouter") {
                    store.setDayOff(DataStore.dateString(from: newDate), kind: newKind)
                }
                .buttonStyle(AccentPillButtonStyle())
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if upcoming.isEmpty {
                        Text("Aucune journée prévue.")
                            .font(.system(size: 12))
                            .foregroundColor(.labelMuted)
                    }
                    ForEach(upcoming, id: \.date) { row($0.date, $0.kind) }
                    if !past.isEmpty {
                        DisclosureGroup(isExpanded: $showPast) {
                            ForEach(Array(past), id: \.date) { row($0.date, $0.kind) }
                        } label: {
                            Text("Journées passées (\(past.count))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.labelMuted)
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .frame(minHeight: 160)
        }
        .padding(20)
        .frame(width: 440, height: 420)
    }

    private func row(_ date: String, _ kind: DayOffKind) -> some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.system(size: AppLook.fs(11)))
                .foregroundColor(.accentWarm)
                .frame(width: 18)
            Text(DataStore.parseDate(date).map { DataStore.formatDate($0) } ?? date)
                .font(.system(size: 12))
            Picker("", selection: Binding(
                get: { kind },
                set: { store.setDayOff(date, kind: $0) }
            )) {
                ForEach(DayOffKind.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
            Spacer()
            Button {
                store.setDayOff(date, kind: nil)
            } label: {
                Image(systemName: "trash").font(.system(size: AppLook.fs(11)))
            }
            .buttonStyle(.pressable)
            .foregroundColor(.labelMuted)
            .help("Retirer cette journée")
            .accessibilityLabel("Retirer cette journée")
        }
        .padding(8)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
        .overlay(RoundedRectangle(cornerRadius: AppLook.r(8, 12)).stroke(Color.cardBorder, lineWidth: 1))
    }
}
