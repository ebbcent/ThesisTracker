import SwiftUI

// MARK: - Calculateur de soutenance (#7)

/// Affiche 3 projections de date de fin : rythme 60j / 30j / idéal.
/// Met en regard avec une date cible si l'utilisateur en a défini une.
struct DefenseDateWidget: View {
    @ObservedObject var store: DataStore
    @State private var showTargetEditor = false
    @State private var draftTarget: Date = Date()

    private var projections: (last60: DataStore.VelocityProjection, last30: DataStore.VelocityProjection, ideal: DataStore.VelocityProjection) {
        store.velocityProjections()
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                header
                projectionRow(label: "Rythme 60 jours",
                              subtitle: "Sur la durée — réaliste",
                              proj: projections.last60,
                              color: Color(red: 0.300, green: 0.650, blue: 0.900))
                projectionRow(label: "Rythme 30 jours",
                              subtitle: "Récent — momentum actuel",
                              proj: projections.last30,
                              color: Color(red: 0.961, green: 0.620, blue: 0.043))
                projectionRow(label: "Rythme idéal",
                              subtitle: "Si tu tiens ton objectif quotidien",
                              proj: projections.ideal,
                              color: .accentGreen)
                if let target = store.targetDefenseDate {
                    targetBanner(target)
                }
                Button {
                    draftTarget = store.targetDefenseDate ?? Date().addingTimeInterval(60*60*24*180)
                    showTargetEditor = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: store.targetDefenseDate == nil ? "flag" : "flag.fill")
                            .font(.system(size: 11))
                        Text(store.targetDefenseDate == nil ? "Définir une date cible" : "Modifier la cible")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.accent)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.accent.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .sheet(isPresented: $showTargetEditor) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Date cible de soutenance")
                    .font(.system(size: 15, weight: .semibold))
                DatePicker("", selection: $draftTarget, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                HStack {
                    if store.targetDefenseDate != nil {
                        Button("Effacer", role: .destructive) {
                            store.targetDefenseDate = nil
                            showTargetEditor = false
                        }
                        .buttonStyle(.pressable)
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.93, green: 0.26, blue: 0.26))
                    }
                    Spacer()
                    Button("Annuler") { showTargetEditor = false }
                        .buttonStyle(.pressable)
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                    Button {
                        store.targetDefenseDate = draftTarget
                        showTargetEditor = false
                    } label: {
                        Text("Enregistrer")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }

    // MARK: -

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.404, green: 0.224, blue: 0.718).opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: "graduationcap.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(red: 0.404, green: 0.224, blue: 0.718))
            }
            Text("Soutenance — projection")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
    }

    private func projectionRow(label: String, subtitle: String, proj: DataStore.VelocityProjection, color: Color) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted.opacity(0.8))
            }
            .frame(width: 140, alignment: .leading)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let date = proj.estimatedDate {
                    Text(DataStore.formatDate(date))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    let avg = Int(proj.avgPerDay)
                    Text(avg > 0 ? "~ \(avg) car./j" : "")
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted)
                } else {
                    Text("—")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.labelMuted.opacity(0.5))
                    Text("vitesse insuffisante")
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted.opacity(0.7))
                }
            }
        }
        .padding(8)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func targetBanner(_ target: Date) -> some View {
        let cal = DataStore.gregorianCal
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: target)).day ?? 0
        let realistic = projections.last60.estimatedDate
        let gap: Int? = realistic.map {
            cal.dateComponents([.day], from: target, to: $0).day ?? 0
        }
        let onTrack: Bool = gap.map { $0 <= 0 } ?? false

        return HStack(spacing: 8) {
            Image(systemName: onTrack ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(onTrack ? .accentGreen : Color(red: 0.929, green: 0.329, blue: 0.329))
            VStack(alignment: .leading, spacing: 2) {
                Text("Cible : \(DataStore.formatDate(target)) (\(days >= 0 ? "dans " : "il y a ")\(abs(days)) j)")
                    .font(.system(size: 11, weight: .semibold))
                if let g = gap {
                    Text(onTrack
                         ? "À ton rythme actuel, tu y arriverais avec \(abs(g)) j d'avance."
                         : "À ton rythme actuel, tu serais en retard de \(g) j.")
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted)
                }
            }
            Spacer()
        }
        .padding(10)
        .background((onTrack ? Color.accentGreen : Color(red: 0.929, green: 0.329, blue: 0.329)).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
