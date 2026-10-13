import SwiftUI

// MARK: - Plan de bataille hebdomadaire (#1)

struct WeeklyPlanWidget: View {
    @ObservedObject var store: DataStore
    @State private var showSheet = false

    private var plan: WeeklyPlan? { store.currentWeeklyPlan }
    private var ratio: Double { plan?.completionRatio ?? 0 }
    private var color: Color {
        if ratio >= 1.0 { return .accentGreen }
        if ratio >= 0.6 { return .accentWarm }
        return .accent
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(color.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "checklist")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(color)
                    }
                    Text("Plan de bataille")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if let plan, !plan.items.isEmpty {
                        Text("\(plan.doneCount)/\(plan.totalCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(color)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(color.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }

                if let plan, !plan.items.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(plan.items.prefix(4)) { item in
                            HStack(spacing: 6) {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(item.isDone ? .accentGreen : .labelMuted.opacity(0.5))
                                Text(item.text)
                                    .font(.system(size: 11))
                                    .foregroundColor(item.isDone ? .labelMuted : .primary)
                                    .strikethrough(item.isDone, color: .labelMuted)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        if plan.items.count > 4 {
                            Text("+ \(plan.items.count - 4) autre\(plan.items.count - 4 > 1 ? "s" : "")…")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted.opacity(0.7))
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.12)).frame(height: 5)
                            RoundedRectangle(cornerRadius: 3).fill(color)
                                .frame(width: geo.size.width * ratio, height: 5)
                        }
                    }
                    .frame(height: 5)
                } else {
                    Text("Aucune action prévue pour la semaine.")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                }

                Button { showSheet = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: plan?.items.isEmpty ?? true ? "plus.circle.fill" : "list.bullet")
                            .font(.system(size: 11))
                        Text(plan?.items.isEmpty ?? true ? "Définir le plan" : "Ouvrir le plan")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(color)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showSheet) {
            WeeklyPlanSheet(store: store)
        }
    }
}

// MARK: - Sheet du plan hebdo

struct WeeklyPlanSheet: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var newItemText: String = ""
    @State private var editingId: UUID? = nil
    @State private var editingText: String = ""

    private var plan: WeeklyPlan { store.currentWeeklyPlan ?? store.ensureCurrentWeeklyPlan() }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if plan.items.isEmpty {
                        emptyState
                    } else {
                        ForEach(plan.items) { item in
                            itemRow(item)
                            if item.id != plan.items.last?.id {
                                Divider().padding(.leading, 38)
                            }
                        }
                    }
                    if let lastPlan = store.lastWeekPlan, !lastPlan.items.isEmpty {
                        retrospectiveSection(lastPlan)
                    }
                }
            }
            Divider()
            addBar
        }
        .frame(width: 540, height: 580)
    }

    // MARK: -

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Plan de bataille").font(.system(size: 16, weight: .semibold))
                Text("Semaine \(plan.weekKey.suffix(3)) · \(plan.doneCount)/\(plan.totalCount) actions accomplies")
                    .font(.system(size: 11)).foregroundColor(.labelMuted)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.labelMuted)
            }
            .buttonStyle(.plain)
            .help("Fermer")
            .accessibilityLabel("Fermer")
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 32))
                .foregroundColor(.labelMuted.opacity(0.5))
            Text("Pas d'actions prévues")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.labelMuted)
            Text("Ajoute 3-5 actions concrètes pour la semaine (rédiger l'intro, relire le chapitre 2, etc).")
                .font(.system(size: 11))
                .foregroundColor(.labelMuted.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func itemRow(_ item: WeeklyPlanItem) -> some View {
        HStack(spacing: 10) {
            Button {
                store.toggleWeeklyPlanItem(itemId: item.id)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(item.isDone ? .accentGreen : .labelMuted.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help(item.isDone ? "Marquer comme non fait" : "Marquer comme fait")
            .accessibilityLabel(item.isDone ? "Marquer comme non fait" : "Marquer comme fait")

            if editingId == item.id {
                TextField("Action", text: $editingText, onCommit: {
                    store.updateWeeklyPlanItemText(itemId: item.id, text: editingText)
                    editingId = nil
                })
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            } else {
                Text(item.text)
                    .font(.system(size: 12, weight: item.isDone ? .regular : .medium))
                    .foregroundColor(item.isDone ? .labelMuted : .primary)
                    .strikethrough(item.isDone, color: .labelMuted)
                    .onTapGesture(count: 2) {
                        editingId = item.id
                        editingText = item.text
                    }
            }
            Spacer()
            if let doneDate = item.doneDate {
                Text(doneDate.suffix(5))
                    .font(.system(size: 9))
                    .foregroundColor(.labelMuted.opacity(0.7))
            }
            Button { store.deleteWeeklyPlanItem(itemId: item.id) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Supprimer")
            .accessibilityLabel("Supprimer")
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    private func retrospectiveSection(_ lastPlan: WeeklyPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
                Text("RÉTROSPECTIVE — SEMAINE PRÉCÉDENTE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.labelMuted)
                    .kerning(0.8)
                Spacer()
                Text("\(lastPlan.doneCount)/\(lastPlan.totalCount)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.labelMuted)
            }
            .padding(.horizontal, 18).padding(.top, 18)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(lastPlan.items.prefix(8)) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.isDone ? "checkmark" : "minus")
                            .font(.system(size: 10))
                            .foregroundColor(item.isDone ? .accentGreen : .labelMuted.opacity(0.4))
                            .frame(width: 12)
                        Text(item.text)
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                            .lineLimit(1)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 14)
        }
    }

    private var addBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 11))
                .foregroundColor(.labelMuted)
            TextField("Nouvelle action pour la semaine…", text: $newItemText, onCommit: addItem)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            Button(action: addItem) {
                Text("Ajouter")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func addItem() {
        store.addWeeklyPlanItem(text: newItemText)
        newItemText = ""
    }
}
