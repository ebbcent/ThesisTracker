import SwiftUI
import AppKit

// MARK: - Quick Entry Panel Manager

final class QuickEntryPanelManager {
    static let shared = QuickEntryPanelManager()
    private var panel: NSPanel?
    private var hostingView: NSView?

    private init() {}

    func show(store: DataStore) {
        if let existing = panel, existing.isVisible {
            existing.orderOut(nil)
            return
        }

        let contentView = QuickEntryView(store: store) {
            self.panel?.orderOut(nil)
        }

        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 320)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.title = ""
        p.isFloatingPanel = true
        p.level = .floating
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.hasShadow = true
        p.contentView = hosting
        p.center()

        // Position slightly above center
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelFrame = p.frame
            p.setFrameOrigin(NSPoint(
                x: screenFrame.midX - panelFrame.width / 2,
                y: screenFrame.midY - panelFrame.height / 2 + 60
            ))
        }

        self.panel = p
        self.hostingView = hosting
        p.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Quick Entry View

struct QuickEntryView: View {
    @ObservedObject var store: DataStore
    let onDismiss: () -> Void

    @State private var inputText: String = ""
    @State private var savedConfirmation = false
    @State private var selectedProjectId: UUID? = nil
    @State private var selectedChapterId: UUID? = nil
    @State private var targetIsYesterday: Bool = false
    @FocusState private var inputFocused: Bool

    private var targetDate: String {
        guard targetIsYesterday else { return DataStore.today }
        let cal = Calendar(identifier: .gregorian)
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return DataStore.dateString(from: yesterday)
    }

    private var selectedProject: Project? {
        let id = selectedProjectId ?? store.data.activeProjectId
        return store.data.projects.first(where: { $0.id == id })
    }

    private var selectedChapter: Chapter? {
        let id = selectedChapterId ?? selectedProject?.activeChapterId
        return selectedProject?.chapters.first(where: { $0.id == id })
    }

    private var inputInt: Int? {
        Int(inputText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: ""))
    }

    private var currentTotal: Int {
        selectedChapter?.entryForDate(targetDate)?.totalCount ?? 0
    }

    /// Différence entre l'input et le total actuel : combien sera ajouté/retiré au save.
    private var pendingDelta: Int? {
        guard let n = inputInt else { return nil }
        let delta = n - currentTotal
        return delta == 0 ? nil : delta
    }

    private func deltaLabel(_ delta: Int) -> String {
        if delta >= 0 {
            return "+\(store.formatCountShort(delta)) à ajouter"
        } else {
            return "−\(store.formatCountShort(abs(delta))) à retirer"
        }
    }

    private func goalContextLabel(total: Int, goal: Int) -> String {
        if total >= goal {
            return "Objectif atteint · +\(store.formatCountShort(total - goal)) au-delà"
        }
        let remaining = goal - total
        let pct = Int(Double(total) / Double(goal) * 100)
        return "\(pct)% · encore \(store.formatCountShort(remaining)) pour l'objectif"
    }

    var body: some View {
        ZStack {
            FloatingSurface(radius: 16)   // 5.27 : verre en Tuiles
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: AppLook.r(16, 22), style: .continuous)
                        .stroke(Color.cardBorder, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accent)
                    Text("Saisie rapide")
                        .font(.system(size: 14, weight: .bold, design: AppLook.fontDesign))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("⎋ Fermer")
                        .font(.system(size: AppLook.fs(10)))
                        .foregroundColor(.labelMuted)
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: AppLook.fs(10), weight: .semibold))
                            .foregroundColor(.labelMuted)
                            .padding(5)
                            .background(Color.glassFill)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.pressable)
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityLabel("Fermer la saisie rapide")
                }

                Divider()

                // Toggle Aujourd'hui / Hier — pour rattraper une saisie oubliée (⌘Y)
                HStack(spacing: 6) {
                    quickEntryDateChip("Aujourd'hui", selected: !targetIsYesterday) {
                        targetIsYesterday = false
                        refreshInput()
                    }
                    quickEntryDateChip("Hier", selected: targetIsYesterday) {
                        targetIsYesterday = true
                        refreshInput()
                    }
                    Spacer()
                    if targetIsYesterday {
                        Label("Saisie passée", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: AppLook.fs(10), weight: .medium))
                            .foregroundColor(.semOrange)
                    }
                    // Raccourci invisible ⌘Y → bascule la cible
                    Button("") {
                        targetIsYesterday.toggle()
                        refreshInput()
                    }
                    .keyboardShortcut("y", modifiers: [.command])
                    .opacity(0)
                    .frame(width: 0, height: 0)
                }
                .help("⌘Y : bascule Aujourd'hui / Hier")

                // Sélecteurs compacts
                if store.data.projects.count > 1 {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: AppLook.fs(10)))
                            .foregroundColor(.accent.opacity(0.8))
                        Picker("", selection: Binding(
                            get: { selectedProjectId ?? store.data.activeProjectId ?? store.data.projects.first?.id },
                            set: { newId in
                                selectedProjectId = newId
                                selectedChapterId = store.data.projects.first(where: { $0.id == newId })?.activeChapterId
                                refreshInput()
                            }
                        )) {
                            ForEach(store.data.projects) { project in
                                Text(project.name).tag(Optional(project.id))
                            }
                        }
                        .labelsHidden()
                        .font(.system(size: 12))
                    }
                }

                Group {
                    if let project = selectedProject, project.chapters.count > 1 {
                        HStack(spacing: 8) {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: AppLook.fs(10)))
                                .foregroundColor(.accentWarm.opacity(0.8))
                            Picker("", selection: Binding(
                                get: { selectedChapterId ?? project.activeChapterId ?? project.chapters.first?.id },
                                set: { newId in
                                    selectedChapterId = newId
                                    refreshInput()
                                }
                            )) {
                                ForEach(project.chapters) { chapter in
                                    Text(chapter.name).tag(Optional(chapter.id))
                                }
                            }
                            .labelsHidden()
                            .font(.system(size: 12))
                        }
                    } else if let chapter = selectedChapter {
                        HStack(spacing: 6) {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: AppLook.fs(10)))
                                .foregroundColor(.accentWarm.opacity(0.8))
                            Text(chapter.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                // Drop d'un chapitre depuis la sidebar → pré-sélection
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first, raw.hasPrefix("ch:"),
                          let id = UUID(uuidString: String(raw.dropFirst(3))),
                          let projId = store.projectId(containingChapter: id) else { return false }
                    store.data.activeProjectId = projId
                    selectedChapterId = id
                    refreshInput()
                    return true
                }

                // Champ de saisie principal
                HStack(spacing: 10) {
                    TextField(
                        "\(currentTotal)",
                        text: $inputText
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 28, weight: .bold, design: AppLook.fontDesign))
                    .foregroundColor(.primary)
                    .focused($inputFocused)
                    .onSubmit { saveEntry() }
                    .accessibilityLabel(store.data.useWordCount ? "Total de mots pour \(selectedChapter?.name ?? "ce chapitre")" : "Total de caractères pour \(selectedChapter?.name ?? "ce chapitre")")
                    .accessibilityValue("Actuel \(currentTotal)")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.data.useWordCount ? "mots" : "car.")
                            .font(.system(size: 12))
                            .foregroundColor(.labelMuted)
                        if currentTotal > 0 {
                            Text("actuel : \(store.formatCountShort(currentTotal))")
                                .font(.system(size: AppLook.fs(10)))
                                .foregroundColor(.labelMuted.opacity(0.7))
                        }
                        if let delta = pendingDelta {
                            Text(deltaLabel(delta))
                                .font(.system(size: AppLook.fs(10), weight: .semibold))
                                .foregroundColor(delta >= 0 ? .accentGreen : .accentWarm)
                        }
                    }

                    Spacer()

                    Button(action: saveEntry) {
                        Image(systemName: savedConfirmation ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(savedConfirmation ? .accentGreen : .accent)
                    }
                    .buttonStyle(.pressable)
                    .disabled(inputInt == nil)
                    .help("Enregistrer (↩)")
                    .accessibilityLabel(savedConfirmation ? "Saisie enregistrée" : "Enregistrer la saisie")
                    .accessibilityHint("Appuyez pour enregistrer la nouvelle valeur du chapitre")
                }
                .padding(.vertical, 4)

                // Progress bar si objectif défini
                if store.effectiveDailyGoal > 0 {
                    let total = store.dailyProgress
                    let ratio = min(1.0, Double(total) / Double(store.effectiveDailyGoal))
                    let color: Color = ratio >= 1 ? .accentGreen : .accent
                    VStack(alignment: .leading, spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.15)).frame(height: 4)
                                RoundedRectangle(cornerRadius: 3).fill(color)
                                    .frame(width: geo.size.width * ratio, height: 4)
                                    .appAnimation(Motion.progress, value: ratio)
                            }
                        }
                        .frame(height: 4)
                        Text(goalContextLabel(total: total, goal: store.effectiveDailyGoal))
                            .font(.system(size: AppLook.fs(10)))
                            .foregroundColor(.labelMuted.opacity(0.75))
                    }
                }

                // Contexte : moyenne 7 jours
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: AppLook.fs(10)))
                    Text("Moy. 7j : \(store.formatCountShort(store.sevenDayAverage)) / jour")
                        .font(.system(size: AppLook.fs(10)))
                }
                .foregroundColor(.labelMuted.opacity(0.7))
            }
            .padding(18)
        }
        .frame(width: 360)
        .onAppear {
            selectedProjectId = store.data.activeProjectId
            selectedChapterId = store.activeProject?.activeChapterId
            refreshInput()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                inputFocused = true
            }
        }
    }

    private func saveEntry() {
        guard let count = inputInt,
              let chapter = selectedChapter,
              let project = selectedProject else { return }
        store.setTotalForDate(count, for: chapter.id, in: project.id, date: targetDate)
        // Sync active project/chapter
        store.data.activeProjectId = project.id
        if let idx = store.data.projects.firstIndex(where: { $0.id == project.id }) {
            store.data.projects[idx].activeChapterId = chapter.id
        }
        store.save()
        withAppAnimation { savedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onDismiss()
        }
    }

    private func refreshInput() {
        inputText = selectedChapter?.entryForDate(targetDate).map { "\($0.totalCount)" } ?? ""
    }

    @ViewBuilder
    private func quickEntryDateChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: AppLook.fs(10), weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .white : .labelMuted)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(selected ? Color.accent.opacity(0.85) : Color.white.opacity(0.05))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? Color.accent : Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Cible : \(label)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
