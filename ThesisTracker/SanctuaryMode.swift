import SwiftUI
import AppKit
import Combine

// MARK: - Mode Sanctuaire

/// Mode focus ultra-strict : plein écran, masque la menu bar, decompte visible,
/// un seul chapitre accessible. Durée 60-240 min, sortie par esc (avec confirmation).
struct SanctuaryModeView: View {
    @ObservedObject var store: DataStore
    let onDismiss: () -> Void

    @State private var totalSeconds: Int = 90 * 60
    @State private var startedAt: Date? = nil
    @State private var now: Date = Date()
    @State private var showExitConfirm: Bool = false
    @State private var noteText: String = ""

    private var chapter: Chapter? { store.activeChapter }
    private var project: Project? { store.activeProject }

    private var isRunning: Bool { startedAt != nil }
    private var elapsed: TimeInterval {
        guard let s = startedAt else { return 0 }
        return now.timeIntervalSince(s)
    }
    private var remaining: TimeInterval {
        max(0, Double(totalSeconds) - elapsed)
    }
    private var ratio: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1.0, elapsed / Double(totalSeconds))
    }
    private var isFinished: Bool { isRunning && remaining <= 0 }

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.10)
                .ignoresSafeArea()
            content
        }
        .onAppear { hideMenuBar() }
        .onDisappear { restoreMenuBar() }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            now = Date()
        }
        .alert("Sortir du sanctuaire ?", isPresented: $showExitConfirm) {
            Button("Continuer", role: .cancel) { showExitConfirm = false }
            Button("Sortir", role: .destructive) {
                if isRunning { saveSessionNote(early: true) }
                onDismiss()
            }
        } message: {
            Text(isRunning ? "Tu n'as pas terminé. La session sera notée comme interrompue." : "Quitter le sanctuaire ?")
        }
        .onExitCommand { handleExit() }
    }

    @ViewBuilder
    private var content: some View {
        if isFinished {
            finishedView
        } else if isRunning {
            runningView
        } else {
            setupView
        }
    }

    // MARK: -

    private var setupView: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.85))
                Text("Sanctuaire")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Aucune distraction. Un chapitre. Une intention.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.65))
            }
            if let chapter, let project {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .kerning(1.2)
                    Text(chapter.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(16)
                .frame(maxWidth: 400)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text("Aucun chapitre sélectionné.")
                    .foregroundColor(.white.opacity(0.5))
            }
            VStack(spacing: 10) {
                Text("DURÉE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .kerning(1.2)
                HStack(spacing: 8) {
                    durationButton(minutes: 60)
                    durationButton(minutes: 90)
                    durationButton(minutes: 120)
                    durationButton(minutes: 180)
                    durationButton(minutes: 240)
                }
            }
            Button {
                startedAt = Date()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("Entrer dans le sanctuaire")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 22).padding(.vertical, 12)
                .background(Color.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(chapter == nil)
            Spacer()
            Button("Quitter") { onDismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(40)
    }

    private func durationButton(minutes: Int) -> some View {
        Button { totalSeconds = minutes * 60 } label: {
            Text("\(minutes) min")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(totalSeconds == minutes * 60 ? .black : .white.opacity(0.7))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(totalSeconds == minutes * 60 ? Color.white : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var runningView: some View {
        VStack(spacing: 24) {
            Spacer()
            if let chapter {
                VStack(spacing: 6) {
                    Text("FOCUS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .kerning(1.4)
                    Text(chapter.name)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 4)
                    .frame(width: 220, height: 220)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(
                        LinearGradient(colors: [Color.white.opacity(0.6), Color.white],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 220, height: 220)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(formatTime(remaining))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                    Text("restant")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("CAPTURE RAPIDE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .kerning(1.0)
                TextField("Une idée, une question, à reprendre…", text: $noteText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button {
                    let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        _ = store.addFragment(content: trimmed, tags: ["sanctuaire"])
                        noteText = ""
                    }
                } label: {
                    Text("Capter dans le carnet")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(maxWidth: 420)
            Spacer()
            Text("⎋ pour sortir")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(40)
    }

    private var finishedView: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundColor(.white)
            Text("Session terminée")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("\(totalSeconds / 60) minutes de focus profond.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
            Button {
                saveSessionNote(early: false)
                onDismiss()
            } label: {
                Text("Sortir")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func handleExit() {
        if isRunning && !isFinished {
            showExitConfirm = true
        } else {
            onDismiss()
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func saveSessionNote(early: Bool) {
        let duration = Int(elapsed / 60)
        let chapterName = chapter?.name ?? "—"
        let prefix = early ? "[Sanctuaire interrompu]" : "[Sanctuaire]"
        _ = store.addJournalEntry(
            content: "\(prefix) \(duration) min de focus profond sur « \(chapterName) ».",
            tags: ["sanctuaire"]
        )
    }

    private func hideMenuBar() {
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
    }
    private func restoreMenuBar() {
        NSApp.presentationOptions = []
    }
}
