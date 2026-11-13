import Combine
import AppKit
import Foundation

extension Notification.Name {
    static let navigateToProfessor = Notification.Name("navigateToProfessor")   // 5.13
}

// MARK: - 5.13 Professeur : séance en cours
//
// La séance vit en mémoire tant que l'app est ouverte (elle survit aux
// changements d'onglet). Chaque échange est ajouté au journal du mois,
// « Échanges app/AAAA-MM.md », dans le dossier du directeur. L'app n'écrit
// nulle part ailleurs dans le coffre : Mémoire du professeur.md et Suivi.md
// restent au bot et à Clem.

struct ProfessorTurn: Identifiable, Equatable {
    let id = UUID()
    let role: AnthropicClient.Message.Role
    let text: String
    var attachmentName: String? = nil
    var attachmentSigns: Int? = nil
    let date: Date
}

@MainActor
final class ProfessorSession: ObservableObject {
    static let shared = ProfessorSession()

    @Published private(set) var turns: [ProfessorTurn] = []
    @Published private(set) var context: ProfessorContext?
    @Published private(set) var isSending = false
    @Published var errorMessage: String?
    @Published var draft: String = ""
    @Published var pendingAttachment: ProfessorContext.Attachment?
    @Published private(set) var lastUsage: AnthropicClient.Usage?
    @Published private(set) var journalWarning: String?

    private var apiMessages: [AnthropicClient.Message] = []
    private var sessionStarted: Date?

    private init() {}

    func newSession() {
        turns = []
        apiMessages = []
        context = nil
        errorMessage = nil
        lastUsage = nil
        pendingAttachment = nil
        sessionStarted = nil
        journalWarning = nil
    }

    /// Préremplit la question et ouvre l'onglet Professeur.
    func prepare(question: String) {
        draft = question
        NotificationCenter.default.post(name: .navigateToProfessor, object: nil)
    }

    func refreshContext(store: DataStore) {
        context = ProfessorContext.build(store: store, folder: ProfessorSettings.shared.folderURL)
    }

    func chooseAttachment() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let deposits = ProfessorSettings.shared.folderURL.appendingPathComponent("Dépôts")
        if FileManager.default.fileExists(atPath: deposits.path) { panel.directoryURL = deposits }
        panel.message = "Texte à relire (.docx, .pdf, .odt, .rtf, .txt, .md)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            pendingAttachment = try ProfessorContext.loadAttachment(url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func send(store: DataStore) async {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        let settings = ProfessorSettings.shared
        guard let key = settings.readKey() else {
            errorMessage = AnthropicClient.ClientError.noKey.localizedDescription
            return
        }
        guard settings.folderExists else {
            errorMessage = "Dossier du directeur introuvable : vérifie-le dans Réglages › Professeur."
            return
        }
        if context == nil { refreshContext(store: store) }
        guard let context = self.context else { return }

        let attachment = pendingAttachment
        var message = AnthropicClient.Message(role: .user, text: question)
        if let attachment {
            let note = attachment.truncated ? " (tronqué : seul le début est joint)" : ""
            message.attachment = "<texte_joint fichier=\"\(attachment.fileName)\" signes=\"\(attachment.signs)\"\(note.isEmpty ? "" : " remarque=\"\(note.trimmingCharacters(in: .whitespaces))\"")>\n\(attachment.text)\n</texte_joint>"
        }
        let now = Date()
        turns.append(ProfessorTurn(role: .user, text: question,
                                   attachmentName: attachment?.fileName, attachmentSigns: attachment?.signs, date: now))
        apiMessages.append(message)
        draft = ""
        pendingAttachment = nil
        errorMessage = nil
        isSending = true

        let client = AnthropicClient(apiKey: key, model: settings.model.rawValue)
        do {
            let reply = try await client.send(persona: context.persona, context: context.body, messages: apiMessages)
            var text = reply.text
            if reply.stoppedAtLimit { text += "\n\n[réponse coupée : limite de longueur atteinte]" }
            apiMessages.append(.init(role: .assistant, text: text))
            let answer = ProfessorTurn(role: .assistant, text: text, date: Date())
            turns.append(answer)
            lastUsage = reply.usage
            appendToJournal(question: turns[turns.count - 2], answer: answer, model: settings.model.rawValue)
        } catch {
            // L'échange raté est retiré pour pouvoir renvoyer la question.
            apiMessages.removeLast()
            turns.removeLast()
            draft = question
            pendingAttachment = attachment
            errorMessage = error.localizedDescription
        }
        isSending = false
    }

    // MARK: Journal « Échanges app/AAAA-MM.md »

    static func journalBlock(question: ProfessorTurn, answer: ProfessorTurn, model: String, sessionStart: Date?, isFirstOfSession: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        var out = ""
        if isFirstOfSession {
            out += "\n## \(f.string(from: sessionStart ?? question.date)) — séance app\n"
        }
        out += "\n**Clem** (\(f.string(from: question.date)))"
        if let name = question.attachmentName {
            out += " — texte joint : « \(name) »"
            if let signs = question.attachmentSigns { out += ", \(signs) signes" }
        }
        out += " :\n\n\(question.text)\n\n**L. Vandenbossche** (\(model)) :\n\n\(answer.text)\n"
        return out
    }

    private func appendToJournal(question: ProfessorTurn, answer: ProfessorTurn, model: String) {
        let isFirst = sessionStarted == nil
        if isFirst { sessionStarted = question.date }
        let block = Self.journalBlock(question: question, answer: answer, model: model,
                                      sessionStart: sessionStarted, isFirstOfSession: isFirst)
        let url = ProfessorContext.journalURL(folder: ProfessorSettings.shared.folderURL, date: question.date)
        do {
            try Self.append(block, to: url, monthTitle: ProfessorContext.monthString(question.date))
            journalWarning = nil
        } catch {
            journalWarning = "Échange non consigné dans « Échanges app » : \(error.localizedDescription)"
        }
    }

    static func append(_ text: String, to url: URL, monthTitle: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordError) { target in
            do {
                if fm.fileExists(atPath: target.path) {
                    let handle = try FileHandle(forWritingTo: target)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data(text.utf8))
                } else {
                    let header = "# Échanges app — \(monthTitle)\n\nÉchanges avec le professeur depuis Writing Process. Écrit par l'app, ajouts seulement.\n"
                    try Data((header + text).utf8).write(to: target, options: .atomic)
                }
            } catch {
                writeError = error
            }
        }
        if let error = coordError ?? writeError { throw error }
    }
}
