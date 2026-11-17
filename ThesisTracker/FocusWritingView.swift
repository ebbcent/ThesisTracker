import SwiftUI

// MARK: - Mode Écriture Immersif (V5)
// Overlay plein écran minimaliste — ⌘⇧I pour l'ouvrir, Échap pour fermer.

struct FocusWritingView: View {
    @ObservedObject var store: DataStore
    let onClose: () -> Void

    @State private var inputText: String = ""
    @State private var noteText: String = ""
    @State private var savedConfirmation: Bool = false
    @FocusState private var fieldFocused: Bool
    @FocusState private var noteFocused: Bool
    @FocusState private var ideaFocused: Bool
    @State private var pulseAmount: CGFloat = 1.0
    @AppStorage("focusCounterSize") private var counterSize: Double = 72

    // #6 — Mode idée rapide
    @State private var showIdeaZone: Bool = false
    @State private var ideaText: String = ""

    private var activeChapter: Chapter? { store.activeChapter }
    private var activeProject: Project? { store.activeProject }
    private var todayStr: String { DataStore.today }

    private var currentTotal: Int {
        activeChapter?.entryForDate(todayStr)?.totalCount ?? 0
    }

    private var todayDelta: Int {
        guard let ch = activeChapter else { return 0 }
        return ch.increment(for: todayStr)
    }

    private var chapterProgress: Double {
        guard let ch = activeChapter, ch.goal > 0 else { return 0 }
        let total = ch.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
        return min(1.0, Double(total) / Double(ch.goal))
    }

    private var inputInt: Int? {
        Int(inputText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: ""))
    }

    // #3 — Suggestion "delta habituel" : dernier total + velocity
    private var suggestedTotal: Int? {
        guard let ch = activeChapter else { return nil }
        let vel = store.velocity14Days
        guard vel > 0 else { return nil }
        let prev = ch.previousTotal(before: todayStr)
        let suggested = prev + vel
        guard suggested != currentTotal, suggested > currentTotal else { return nil }
        return suggested
    }

    // #4 — 5 derniers totaux distincts (hors aujourd'hui), les plus récents d'abord
    private var recentTotals: [Int] {
        guard let ch = activeChapter else { return [] }
        var seen = Set<Int>()
        return ch.entries
            .filter { $0.date != todayStr }
            .sorted { $0.date > $1.date }
            .compactMap { entry -> Int? in
                guard !seen.contains(entry.totalCount) else { return nil }
                seen.insert(entry.totalCount)
                return entry.totalCount
            }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        ZStack {
            // Fond sombre
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture { /* Ne pas fermer au tap */ }

            VStack(spacing: 0) {
                // Barre de progression chapitre
                if chapterProgress > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Color.white.opacity(0.06).frame(height: 3)
                            Color.accentGreen.opacity(0.8)
                                .frame(width: geo.size.width * chapterProgress, height: 3)
                                .appAnimation(Motion.progress, value: chapterProgress)
                        }
                    }
                    .frame(height: 3)
                }

                Spacer()

                VStack(spacing: 36) {

                    // En-tête projet / chapitre
                    VStack(spacing: 6) {
                        if let project = activeProject {
                            HStack(spacing: 6) {
                                if let type = project.projectType {
                                    Image(systemName: type.icon)
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                Text(project.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.4))
                                if let ch = activeChapter {
                                    Text("›")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.25))
                                    Text(ch.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.55))
                                    // Version brouillon si > 1
                                    if ch.draftVersion > 1 {
                                        Text("v\(ch.draftVersion)")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(.accent.opacity(0.7))
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.accent.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }

                        // Horloge
                        Text(currentTimeString)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.25))
                    }

                    // Grand compteur du jour
                    VStack(spacing: 8) {
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            Text(DataStore.formatNumber(currentTotal))
                                .font(.system(size: counterSize, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .contentTransition(.numericText())
                                .appAnimation(Motion.progress, value: currentTotal)
                            Text(store.data.useWordCount ? "mots" : "car.")
                                .font(.system(size: 22, weight: .light))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.bottom, 10)
                        }

                        if todayDelta > 0 {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 11, weight: .bold))
                                Text("+\(store.formatCount(todayDelta)) aujourd'hui")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(.accentGreen)
                        }

                        // Barre objectif journalier
                        if store.data.dailyGoal > 0 {
                            let ratio = min(1.0, Double(todayDelta) / Double(store.data.dailyGoal))
                            VStack(spacing: 4) {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.white.opacity(0.08))
                                            .frame(height: 4)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(ratio >= 1.0 ? Color.accentGreen : Color.accent)
                                            .frame(width: max(0, geo.size.width * ratio), height: 4)
                                            .appAnimation(Motion.progress, value: ratio)
                                    }
                                }
                                .frame(width: 280, height: 4)
                                Text("Objectif journalier : \(Int(ratio * 100))%")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.3))
                                    .help("\(store.formatCount(todayDelta)) / \(store.formatCount(store.data.dailyGoal)) \(store.data.useWordCount ? "mots" : "car.") · \(Int(ratio * 100))% de l'objectif journalier")
                            }
                        }
                    }
                    .scaleEffect(pulseAmount)
                    .appAnimation(Motion.celebrate, value: pulseAmount)

                    // Champ de saisie + bouton
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "textformat.123")
                                .foregroundColor(.white.opacity(0.35))
                                .font(.system(size: 14))
                            TextField("Nouveau total…", text: $inputText)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .textFieldStyle(.plain)
                                .focused($fieldFocused)
                                .onSubmit { save() }
                            if !inputText.isEmpty {
                                Text(store.data.useWordCount ? "mots" : "car.")
                                    .foregroundColor(.white.opacity(0.35))
                                    .font(.system(size: 13))
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(12, 18)))
                        .overlay(RoundedRectangle(cornerRadius: AppLook.r(12, 18)).stroke(
                            fieldFocused ? Color.accent.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1))
                        .frame(maxWidth: 260)

                        Button(action: save) {
                            HStack(spacing: 6) {
                                Image(systemName: savedConfirmation ? "checkmark" : "arrow.down.circle.fill")
                                    .font(.system(size: 13))
                                Text(savedConfirmation ? "Enregistré !" : "Sauvegarder")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(savedConfirmation ? .white : .black)
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(
                                Group {
                                    if savedConfirmation {
                                        RoundedRectangle(cornerRadius: AppLook.r(12, 18)).fill(Color.accentGreen)
                                    } else {
                                        RoundedRectangle(cornerRadius: AppLook.r(12, 18))
                                            .fill(LinearGradient(colors: [.accent, .accentWarm],
                                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                                    }
                                }
                            )
                        }
                        .buttonStyle(.pressable)
                        .disabled(inputInt == nil)
                        .appAnimation(.easeInOut(duration: 0.2), value: savedConfirmation)
                    }

                    // #3 — Suggestion "+delta habituel"
                    if inputText.isEmpty, let suggested = suggestedTotal {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                                .foregroundColor(.accentWarm.opacity(0.8))
                            Text("Suggéré :")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.35))
                            Button {
                                inputText = "\(suggested)"
                                fieldFocused = true
                            } label: {
                                Text(DataStore.formatNumber(suggested))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.accentWarm)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.accentWarm.opacity(0.12))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.accentWarm.opacity(0.25), lineWidth: 1))
                            }
                            .buttonStyle(.pressable)
                            Text(store.data.useWordCount ? "mots" : "car.")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.25))
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                    }

                    // #4 — Historique de saisie rapide (5 dernières valeurs)
                    if !recentTotals.isEmpty {
                        HStack(spacing: 6) {
                            Text("Récent :")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.3))
                            ForEach(recentTotals, id: \.self) { val in
                                Button {
                                    inputText = "\(val)"
                                    fieldFocused = true
                                } label: {
                                    Text(DataStore.formatNumber(val))
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Color.white.opacity(0.07))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                                }
                                .buttonStyle(.pressable)
                                .help("Saisir \(DataStore.formatNumber(val)) \(store.data.useWordCount ? "mots" : "car.")")
                            }
                        }
                    }

                    // Note de séance
                    HStack(spacing: 10) {
                        Image(systemName: "note.text")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.3))
                        TextField("Note de séance (optionnel)…", text: $noteText)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.75))
                            .textFieldStyle(.plain)
                            .focused($noteFocused)
                            .onSubmit { saveNote() }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
                    .overlay(RoundedRectangle(cornerRadius: AppLook.r(10, 14)).stroke(
                        noteFocused ? Color.white.opacity(0.2) : Color.white.opacity(0.07), lineWidth: 1))
                    .frame(maxWidth: 480)

                    // #6 — Mode idée rapide
                    if showIdeaZone {
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.yellow.opacity(0.8))
                                TextField("Capture une idée…", text: $ideaText)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.85))
                                    .textFieldStyle(.plain)
                                    .focused($ideaFocused)
                                    .onSubmit { saveIdea() }
                                if !ideaText.isEmpty {
                                    Button(action: saveIdea) {
                                        Text("Capturer")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.yellow)
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(Color.yellow.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.pressable)
                                }
                                Button {
                                    withAppAnimation(.easeOut(duration: 0.15)) { showIdeaZone = false }
                                    ideaText = ""
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.3))
                                }
                                .buttonStyle(.pressable)
                                .help("Fermer la zone d’idées")
                                .accessibilityLabel("Fermer la zone d’idées")
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Color.yellow.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
                            .overlay(RoundedRectangle(cornerRadius: AppLook.r(10, 14)).stroke(
                                Color.yellow.opacity(ideaFocused ? 0.3 : 0.12), lineWidth: 1))
                        }
                        .frame(maxWidth: 480)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { ideaFocused = true } }
                    }

                    // Raccourcis hint + bouton idée rapide
                    HStack(spacing: 20) {
                        shortcutHint("↵", "Sauvegarder")
                        shortcutHint("⎋", "Fermer")
                        if store.data.dailyGoal > 0 {
                            let vel = store.velocity14Days
                            if vel > 0 {
                                shortcutHint("⚡", "Vitesse : \(store.formatCount(vel))/j")
                            }
                        }
                        Spacer()
                        // #6 — Toggle idée rapide
                        Button {
                            withAppAnimation(.easeOut(duration: 0.15)) { showIdeaZone.toggle() }
                            if !showIdeaZone { ideaText = "" }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showIdeaZone ? "lightbulb.fill" : "lightbulb")
                                    .font(.system(size: 10))
                                Text("Idée rapide")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(showIdeaZone ? .yellow : .white.opacity(0.3))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(showIdeaZone ? Color.yellow.opacity(0.12) : Color.white.opacity(0.05))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(
                                showIdeaZone ? Color.yellow.opacity(0.25) : Color.white.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.pressable)
                        .help("Capturer une idée sans affecter le compteur")
                    }
                }
                .padding(.horizontal, 48)

                Spacer()
            }

            // Bouton fermer
            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    .padding(20)
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Fermer")
                    .accessibilityLabel("Fermer")
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { fieldFocused = true }
            if let entry = activeChapter?.entryForDate(todayStr) {
                inputText = "\(entry.totalCount)"
                noteText  = entry.note ?? ""
            }
        }
    }

    // MARK: - Helpers

    private func save() {
        guard let count = inputInt,
              let ch = activeChapter,
              let proj = activeProject else { return }
        store.setTotalForDate(count, for: ch.id, in: proj.id, date: todayStr)
        saveNote()
        withAppAnimation(.easeOut(duration: 0.15)) { savedConfirmation = true }
        pulseAmount = 1.04
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { pulseAmount = 1.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAppAnimation { savedConfirmation = false }
        }
    }

    private func saveNote() {
        guard let ch = activeChapter, let proj = activeProject,
              activeChapter?.entryForDate(todayStr) != nil else { return }
        store.setNoteForDate(noteText, for: ch.id, in: proj.id, date: todayStr)
    }

    // #6 — Sauvegarder l'idée rapide comme entrée de journal
    private func saveIdea() {
        let trimmed = ideaText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let ch = activeChapter, let proj = activeProject else { return }
        let entry = ChapterLogEntry(
            timestamp: ChapterLogEntry.nowTimestamp(),
            type: .manual,
            content: "💡 \(trimmed)"
        )
        store.addLogEntry(entry, for: ch.id, in: proj.id)
        ideaText = ""
        withAppAnimation(.easeOut(duration: 0.15)) { showIdeaZone = false }
    }

    private var currentTimeString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM · HH:mm"
        let s = f.string(from: Date())
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private func shortcutHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
        }
    }
}
