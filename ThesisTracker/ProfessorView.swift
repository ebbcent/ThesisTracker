import SwiftUI

// MARK: - 5.13 Vue « Professeur » : séance avec le directeur virtuel

struct ProfessorView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool
    /// 5.14 — version « note rapide » pour la fenêtre flottante.
    var compact: Bool = false
    @ObservedObject private var session = ProfessorSession.shared
    @ObservedObject private var settings = ProfessorSettings.shared
    @State private var showSources = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if compact { compactHeader } else { header }
            }
            .padding(.horizontal, compact ? 14 : 24).padding(.top, compact ? 8 : 20).padding(.bottom, compact ? 8 : 12)
            Divider().overlay(Color.cardBorder)
            if !settings.hasKey || !settings.folderExists {
                setupNotice
                    .padding(compact ? 14 : 24)
                Spacer()
            } else {
                conversation
                Divider().overlay(Color.cardBorder)
                composer
                    .padding(compact ? 12 : 16)
            }
        }
        .background(AppBackdrop())
        .sheet(isPresented: $showSources) { sourcesSheet }
        .onAppear {
            inputFocused = true
            session.unreadReply = false
            if !compact { session.tabVisible = true }
        }
        .onDisappear {
            if !compact { session.tabVisible = false }
        }
    }

    // MARK: En-tête compact (note rapide)

    private var compactHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "graduationcap.fill")
                .foregroundColor(.accentWarm)
            Text("Professeur")
                .font(.system(size: 13, weight: .semibold))
            Text(settings.model == .opus ? "Opus" : "Sonnet")
                .font(.system(size: 10))
                .foregroundColor(.labelMuted)
            Spacer()
            Button {
                if session.context == nil { session.refreshContext(store: store) }
                showSources = true
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .buttonStyle(.pressable)
            .foregroundColor(.accentWarm)
            .help("Fichiers lus par le professeur pour cette séance")
            .accessibilityLabel("Contexte de la séance")
            Button {
                session.newSession()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.pressable)
            .foregroundColor(.accentWarm)
            .disabled(session.isSending || session.turns.isEmpty)
            .help("Nouvelle séance")
            .accessibilityLabel("Nouvelle séance")
        }
        .font(.system(size: 12, weight: .medium))
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAppAnimation(.easeOut(duration: 0.15)) { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(showSidebar ? .accentWarm : .labelMuted)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: AppLook.r(7, 10), style: .continuous)
                            .fill(showSidebar ? Color.accentWarm.opacity(0.09) : Color.glassFill)
                            .overlay(RoundedRectangle(cornerRadius: AppLook.r(7, 10), style: .continuous)
                                .stroke(showSidebar ? Color.accentWarm.opacity(0.25) : Color.cardBorder, lineWidth: 1))
                    )
            }
            .buttonStyle(.pressable)
            .help("Afficher ou masquer la barre latérale")
            .accessibilityLabel("Afficher ou masquer la barre latérale")

            VStack(alignment: .leading, spacing: 3) {
                Text("Professeur")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("L. Vandenbossche · directeur virtuel · \(settings.model == .opus ? "Opus" : "Sonnet")")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
            }
            Spacer()
            Button {
                if session.context == nil { session.refreshContext(store: store) }
                showSources = true
            } label: {
                Label("Contexte", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(AccentPillButtonStyle())
            .help("Fichiers lus par le professeur pour cette séance")
            Button {
                session.newSession()
            } label: {
                Label("Nouvelle séance", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(AccentPillButtonStyle())
            .disabled(session.isSending || session.turns.isEmpty)
            .help("Recharge les fichiers du coffre et repart de zéro")
        }
    }

    private var setupNotice: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Configuration nécessaire", systemImage: "key.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentWarm)
                if !settings.hasKey {
                    Text("Ajoute ta clé API Anthropic dans Réglages › Professeur. Elle reste dans le Trousseau de ce Mac.")
                        .font(.system(size: 12)).foregroundColor(.labelMuted)
                }
                if !settings.folderExists {
                    Text("Le dossier du directeur est introuvable sur ce Mac :\n\(settings.folderPath)\nChoisis-le dans Réglages › Professeur.")
                        .font(.system(size: 12)).foregroundColor(.labelMuted)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if session.turns.isEmpty && compact {
                        Text("Note rapide : même séance que l'onglet Professeur. ⌘↩ pour envoyer.")
                            .font(.system(size: 12))
                            .foregroundColor(.labelMuted)
                            .padding(.top, 4)
                    } else if session.turns.isEmpty {
                        Text("Le professeur lit Suivi.md, ton profil, sa mémoire, les échanges du mois, tes échéances et les chiffres de l'app. Il n'écrit que dans « Échanges app/ ». Pour une relecture de fond, joins un export de « Dépôts ».")
                            .font(.system(size: 12))
                            .foregroundColor(.labelMuted)
                            .padding(.top, 8)
                    }
                    ForEach(session.turns) { turn in
                        bubble(turn).id(turn.id)
                    }
                    if session.isSending {
                        // 5.15 : la réponse s'affiche au fil de l'écriture
                        if session.streamingText.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Le professeur lit et réfléchit…")
                                    .font(.system(size: 12)).foregroundColor(.labelMuted)
                            }
                            .id("sending")
                        } else {
                            bubble(ProfessorTurn(role: .assistant, text: session.streamingText, date: Date()))
                                .id("sending")
                        }
                    }
                }
                .padding(compact ? 14 : 24)
            }
            .onChange(of: session.turns.count) { _, _ in
                withAppAnimation(Motion.panel) { proxy.scrollTo(session.isSending ? AnyHashable("sending") : AnyHashable(session.turns.last?.id), anchor: .bottom) }
            }
            .onChange(of: session.streamingText.count / 200) { _, _ in   // suit la réponse en cours sans animer chaque mot
                proxy.scrollTo(AnyHashable("sending"), anchor: .bottom)
            }
        }
    }

    private func bubble(_ turn: ProfessorTurn) -> some View {
        let isUser = turn.role == .user
        return HStack {
            if isUser { Spacer(minLength: compact ? 30 : 80) }
            VStack(alignment: .leading, spacing: 6) {
                Text(isUser ? "Toi" : "L. Vandenbossche")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isUser ? .accentWarm : .labelMuted)
                if let name = turn.attachmentName {
                    Label("\(name)\(turn.attachmentSigns.map { " · \(DataStore.formatNumber($0)) signes" } ?? "")",
                          systemImage: "paperclip")
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted)
                }
                Text(markdown(turn.text))
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AppLook.r(12, 18), style: .continuous)
                    .fill(isUser ? Color.accentWarm.opacity(0.08) : Color.cardBg)
            )
            .overlay(RoundedRectangle(cornerRadius: AppLook.r(12, 18), style: .continuous)
                .stroke(isUser ? Color.accentWarm.opacity(0.25) : Color.cardBorder, lineWidth: 1))
            if !isUser { Spacer(minLength: compact ? 30 : 80) }
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    // MARK: Saisie

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = session.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .textSelection(.enabled)
            }
            if let warning = session.journalWarning {
                Text(warning)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
            if let attachment = session.pendingAttachment {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip").font(.system(size: 11))
                    Text("\(attachment.fileName) · \(DataStore.formatNumber(attachment.signs)) signes\(attachment.truncated ? " (début seulement)" : "")")
                        .font(.system(size: 11))
                    Button {
                        session.pendingAttachment = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Retirer le texte joint")
                }
                .foregroundColor(.labelMuted)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    session.chooseAttachment()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.pressable)
                .foregroundColor(.accentWarm)
                .help("Joindre un texte à relire (dossier Dépôts)")
                .accessibilityLabel("Joindre un texte à relire")
                .disabled(session.isSending)

                TextEditor(text: $session.draft)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .focused($inputFocused)
                    .frame(minHeight: 44, maxHeight: 140)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: AppLook.r(10, 14)).fill(Color.fieldBg))
                    .overlay(RoundedRectangle(cornerRadius: AppLook.r(10, 14)).stroke(Color.cardBorder, lineWidth: 1))
                    .accessibilityLabel("Message au professeur")

                if session.isSending {
                    // 5.15 : « Arrêter » garde ce qui est déjà arrivé
                    Button("Arrêter") { session.stop() }
                        .buttonStyle(AccentPillButtonStyle())
                        .keyboardShortcut(".", modifiers: .command)
                        .help("Arrêter la réponse (⌘.)")
                } else {
                    Button("Envoyer") { session.start(store: store) }
                        .buttonStyle(AccentPillButtonStyle())
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Envoyer (⌘↩)")
                }
            }
            if let usage = session.lastUsage {
                Text("Dernier échange : \(usage.input + usage.cacheRead + usage.cacheWrite) jetons lus (dont \(usage.cacheRead) depuis le cache), \(usage.output) écrits.")
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted)
            }
        }
    }

    // MARK: Contexte de la séance

    private var sourcesSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Contexte de la séance")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Recharger") { session.refreshContext(store: store) }
                    .buttonStyle(AccentPillButtonStyle())
                    .disabled(session.isSending)
                Button("Fermer") { showSources = false }
                    .buttonStyle(AccentPillButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            if let context = session.context {
                Text("Consignes : \(context.personaFromVault ? "« Consignes app.md » du dossier" : "consignes intégrées à l'app")")
                    .font(.system(size: 11)).foregroundColor(.labelMuted)
                ForEach(context.sources) { source in
                    HStack {
                        Image(systemName: icon(source.status))
                            .foregroundColor(color(source.status))
                            .frame(width: 16)
                        Text(source.label).font(.system(size: 12))
                        Spacer()
                        Text(statusText(source.status))
                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                    }
                }
                Text("Le contexte est figé au début de la séance. « Recharger » ou « Nouvelle séance » relisent le coffre.")
                    .font(.system(size: 10)).foregroundColor(.labelMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(20)
        .frame(width: compact ? 380 : 520, height: compact ? 360 : 400)
        .background(Color.cardBg)
    }

    private func icon(_ status: ProfessorSourceFile.Status) -> String {
        switch status {
        case .loaded:      return "checkmark.circle.fill"
        case .missing:     return "minus.circle"
        case .downloading: return "icloud.and.arrow.down"
        case .unreadable:  return "exclamationmark.triangle.fill"
        }
    }

    private func color(_ status: ProfessorSourceFile.Status) -> Color {
        switch status {
        case .loaded:      return .green
        case .missing:     return .labelMuted
        case .downloading: return .blue
        case .unreadable:  return .orange
        }
    }

    private func statusText(_ status: ProfessorSourceFile.Status) -> String {
        switch status {
        case .loaded(let chars, let truncated):
            return "\(DataStore.formatNumber(chars)) car.\(truncated ? " · tronqué" : "")"
        case .missing:     return "absent"
        case .downloading: return "téléchargement iCloud en cours"
        case .unreadable:  return "illisible"
        }
    }
}
