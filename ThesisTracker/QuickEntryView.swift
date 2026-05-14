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
        hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 230)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 230),
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
    @FocusState private var inputFocused: Bool

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
        selectedChapter?.entryForDate(DataStore.today)?.totalCount ?? 0
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.cardBg)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.cardBorder, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accent)
                    Text("Saisie rapide")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("⎋ Fermer")
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted)
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.labelMuted)
                            .padding(5)
                            .background(Color.glassFill)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }

                Divider()

                // Sélecteurs compacts
                if store.data.projects.count > 1 {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
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

                if let project = selectedProject, project.chapters.count > 1 {
                    HStack(spacing: 8) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 10))
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
                            .font(.system(size: 10))
                            .foregroundColor(.accentWarm.opacity(0.8))
                        Text(chapter.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                // Champ de saisie principal
                HStack(spacing: 10) {
                    TextField(
                        "\(currentTotal)",
                        text: $inputText
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .focused($inputFocused)
                    .onSubmit { saveEntry() }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.data.useWordCount ? "mots" : "car.")
                            .font(.system(size: 12))
                            .foregroundColor(.labelMuted)
                        if currentTotal > 0 {
                            Text("actuel : \(store.formatCountShort(currentTotal))")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted.opacity(0.7))
                        }
                    }

                    Spacer()

                    Button(action: saveEntry) {
                        Image(systemName: savedConfirmation ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(savedConfirmation ? .accentGreen : .accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputInt == nil)
                    .help("Enregistrer (↩)")
                }
                .padding(.vertical, 4)

                // Progress bar si objectif défini
                if store.data.dailyGoal > 0 {
                    let total = store.dailyProgress
                    let ratio = min(1.0, Double(total) / Double(store.data.dailyGoal))
                    let color: Color = ratio >= 1 ? .accentGreen : .accent
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.15)).frame(height: 4)
                            RoundedRectangle(cornerRadius: 3).fill(color)
                                .frame(width: geo.size.width * ratio, height: 4)
                                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: ratio)
                        }
                    }
                    .frame(height: 4)
                }
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
        store.setTotalForDate(count, for: chapter.id, in: project.id, date: DataStore.today)
        // Sync active project/chapter
        store.data.activeProjectId = project.id
        if let idx = store.data.projects.firstIndex(where: { $0.id == project.id }) {
            store.data.projects[idx].activeChapterId = chapter.id
        }
        store.save()
        withAnimation { savedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onDismiss()
        }
    }

    private func refreshInput() {
        inputText = selectedChapter?.entryForDate(DataStore.today).map { "\($0.totalCount)" } ?? ""
    }
}
