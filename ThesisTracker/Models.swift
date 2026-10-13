import Foundation
import SwiftUI

// MARK: - Type de projet (V5)

enum ProjectType: String, Codable, CaseIterable {
    case these    = "these"
    case article  = "article"
    case livre    = "livre"
    case memoire  = "memoire"
    case rapport  = "rapport"
    case autre    = "autre"

    var label: String {
        switch self {
        case .these:   return "Thèse"
        case .article: return "Article"
        case .livre:   return "Livre"
        case .memoire: return "Mémoire"
        case .rapport: return "Rapport"
        case .autre:   return "Autre"
        }
    }

    var icon: String {
        switch self {
        case .these:   return "graduationcap.fill"
        case .article: return "doc.text.fill"
        case .livre:   return "book.fill"
        case .memoire: return "note.text"
        case .rapport: return "chart.bar.doc.horizontal"
        case .autre:   return "doc.fill"
        }
    }
}

// MARK: - Jalon de projet (V5)

/// #28 — Récurrence d'un jalon
enum MilestoneRecurrence: String, Codable, CaseIterable {
    case weekly  = "weekly"
    case monthly = "monthly"

    var label: String {
        switch self {
        case .weekly:  return "Hebdomadaire"
        case .monthly: return "Mensuel"
        }
    }

    var icon: String {
        switch self {
        case .weekly:  return "arrow.clockwise"
        case .monthly: return "calendar.badge.clock"
        }
    }
}

// MARK: - #44 Statut enrichi des jalons

// MARK: - Point de sauvegarde du chapitre (#3)

/// Photographie de l'état narratif d'un chapitre à un moment donné :
/// plan, idées, blockers, prochaine action, compteur actuel, draft.
/// Utile pour figer un état avant une grosse refonte ou une relecture.
struct ChapterCheckpoint: Codable, Identifiable {
    var id: UUID = UUID()
    var timestamp: String          // "yyyy-MM-dd HH:mm"
    var draftVersion: Int          // version du draft figée
    var label: String              // titre court fourni par l'utilisateur
    var notes: String?             // copie de chapter.notes
    var notesPlan: String?         // copie de chapter.notesPlan
    var notesIdeas: String?        // copie de chapter.notesIdeas
    var notesBlockers: String?     // copie de chapter.notesBlockers
    var nextStep: String?          // copie de chapter.nextStep
    var latestTotal: Int           // total cumulé à la date du checkpoint
    var trigger: Trigger           // raison de création (manuel / auto)

    enum Trigger: String, Codable {
        case manual         // créé par l'utilisateur via le bouton
        case beforeReview   // créé automatiquement avant un envoi en relecture
        case afterAddressed // créé automatiquement après intégration d'un feedback
    }

    init(id: UUID = UUID(), timestamp: String, draftVersion: Int, label: String,
         notes: String? = nil, notesPlan: String? = nil, notesIdeas: String? = nil,
         notesBlockers: String? = nil, nextStep: String? = nil,
         latestTotal: Int, trigger: Trigger = .manual) {
        self.id = id
        self.timestamp = timestamp
        self.draftVersion = draftVersion
        self.label = label
        self.notes = notes
        self.notesPlan = notesPlan
        self.notesIdeas = notesIdeas
        self.notesBlockers = notesBlockers
        self.nextStep = nextStep
        self.latestTotal = latestTotal
        self.trigger = trigger
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = (try? c.decodeIfPresent(UUID.self,    forKey: .id))            ?? UUID()
        timestamp     = try  c.decode(String.self,            forKey: .timestamp)
        draftVersion  = (try? c.decodeIfPresent(Int.self,     forKey: .draftVersion))  ?? 1
        label         = (try? c.decodeIfPresent(String.self,  forKey: .label))         ?? ""
        notes         = try? c.decodeIfPresent(String.self,   forKey: .notes)
        notesPlan     = try? c.decodeIfPresent(String.self,   forKey: .notesPlan)
        notesIdeas    = try? c.decodeIfPresent(String.self,   forKey: .notesIdeas)
        notesBlockers = try? c.decodeIfPresent(String.self,   forKey: .notesBlockers)
        nextStep      = try? c.decodeIfPresent(String.self,   forKey: .nextStep)
        latestTotal   = (try? c.decodeIfPresent(Int.self,     forKey: .latestTotal))   ?? 0
        trigger       = (try? c.decodeIfPresent(Trigger.self, forKey: .trigger))       ?? .manual
    }
}

// MARK: - Suivi des relectures directeur (#1)

enum SupervisorReviewState: String, Codable, CaseIterable, Identifiable {
    case notSent    = "notSent"     // pas envoyé pour relecture
    case sent       = "sent"        // envoyé, en attente de retour
    case received   = "received"    // feedback reçu, à intégrer
    case addressed  = "addressed"   // feedback intégré

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notSent:   return "Non envoyé"
        case .sent:      return "Envoyé"
        case .received:  return "Retour reçu"
        case .addressed: return "Intégré"
        }
    }

    var icon: String {
        switch self {
        case .notSent:   return "tray"
        case .sent:      return "paperplane.fill"
        case .received:  return "envelope.open.fill"
        case .addressed: return "checkmark.seal.fill"
        }
    }

    var color: Color {
        switch self {
        case .notSent:   return Color(red: 0.5, green: 0.5, blue: 0.55)
        case .sent:      return Color(red: 0.95, green: 0.60, blue: 0.15)
        case .received:  return Color(red: 0.25, green: 0.55, blue: 0.95)
        case .addressed: return Color(red: 0.22, green: 0.75, blue: 0.44)
        }
    }
}

/// Un cycle de relecture par le directeur de thèse.
struct SupervisorReview: Codable, Identifiable {
    var id: UUID = UUID()
    var state: SupervisorReviewState = .notSent
    var sentDate: String? = nil            // "yyyy-MM-dd"
    var receivedDate: String? = nil        // "yyyy-MM-dd"
    var addressedDate: String? = nil       // "yyyy-MM-dd"
    var expectedReturnDate: String? = nil  // date prévue du retour, pour alertes
    var feedbackNotes: String? = nil       // texte libre du retour
    var draftVersion: Int = 1              // numéro du draft envoyé

    init(id: UUID = UUID(), state: SupervisorReviewState = .notSent,
         sentDate: String? = nil, receivedDate: String? = nil,
         addressedDate: String? = nil, expectedReturnDate: String? = nil,
         feedbackNotes: String? = nil, draftVersion: Int = 1) {
        self.id = id
        self.state = state
        self.sentDate = sentDate
        self.receivedDate = receivedDate
        self.addressedDate = addressedDate
        self.expectedReturnDate = expectedReturnDate
        self.feedbackNotes = feedbackNotes
        self.draftVersion = draftVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                 = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        state              = (try? c.decodeIfPresent(SupervisorReviewState.self, forKey: .state)) ?? .notSent
        sentDate           = try? c.decodeIfPresent(String.self, forKey: .sentDate)
        receivedDate       = try? c.decodeIfPresent(String.self, forKey: .receivedDate)
        addressedDate      = try? c.decodeIfPresent(String.self, forKey: .addressedDate)
        expectedReturnDate = try? c.decodeIfPresent(String.self, forKey: .expectedReturnDate)
        feedbackNotes      = try? c.decodeIfPresent(String.self, forKey: .feedbackNotes)
        draftVersion       = (try? c.decodeIfPresent(Int.self, forKey: .draftVersion)) ?? 1
    }
}

enum MilestoneStatus: String, Codable, CaseIterable, Identifiable {
    case pending    = "pending"
    case submitted  = "submitted"
    case inReview   = "inReview"
    case validated  = "validated"
    case rejected   = "rejected"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pending:   return "En attente"
        case .submitted: return "Soumis"
        case .inReview:  return "En révision"
        case .validated: return "Validé"
        case .rejected:  return "Rejeté"
        }
    }

    var icon: String {
        switch self {
        case .pending:   return "clock"
        case .submitted: return "paperplane.fill"
        case .inReview:  return "eye.fill"
        case .validated: return "checkmark.seal.fill"
        case .rejected:  return "xmark.seal.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending:   return Color(red: 0.5, green: 0.5, blue: 0.55)
        case .submitted: return Color(red: 0.25, green: 0.55, blue: 0.95)
        case .inReview:  return Color(red: 0.95, green: 0.60, blue: 0.15)
        case .validated: return Color(red: 0.22, green: 0.75, blue: 0.44)
        case .rejected:  return Color(red: 0.93, green: 0.26, blue: 0.26)
        }
    }

    /// Returns true if this status means the milestone is effectively closed.
    var isTerminal: Bool { self == .validated || self == .rejected }
}

struct Milestone: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var date: String        // "yyyy-MM-dd"
    var isCompleted: Bool = false
    var notes: String? = nil
    var recurrence: MilestoneRecurrence? = nil      // #28
    // #42 — Rappels personnalisables
    var reminderDays: Int = 7                       // Days before to send notification
    var reminderHour: Int = 9                       // Hour (0–23) for notifications
    // #43 — Lien jalon ↔ chapitre
    var linkedChapterId: UUID? = nil
    // #44 — Statut enrichi
    var milestoneStatus: MilestoneStatus = .pending

    // Backwards-compatible decoder
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = (try? c.decodeIfPresent(UUID.self,                  forKey: .id))              ?? UUID()
        title           = try c.decode(String.self,                           forKey: .title)
        date            = try c.decode(String.self,                           forKey: .date)
        isCompleted     = (try? c.decodeIfPresent(Bool.self,                  forKey: .isCompleted))     ?? false
        notes           = try? c.decodeIfPresent(String.self,                 forKey: .notes)
        recurrence      = try? c.decodeIfPresent(MilestoneRecurrence.self,    forKey: .recurrence)
        reminderDays    = (try? c.decodeIfPresent(Int.self,                   forKey: .reminderDays))    ?? 7
        reminderHour    = (try? c.decodeIfPresent(Int.self,                   forKey: .reminderHour))    ?? 9
        linkedChapterId = try? c.decodeIfPresent(UUID.self,                   forKey: .linkedChapterId)
        milestoneStatus = (try? c.decodeIfPresent(MilestoneStatus.self,       forKey: .milestoneStatus)) ?? .pending
    }

    init(id: UUID = UUID(), title: String, date: String,
         isCompleted: Bool = false, notes: String? = nil,
         recurrence: MilestoneRecurrence? = nil,
         reminderDays: Int = 7, reminderHour: Int = 9,
         linkedChapterId: UUID? = nil,
         milestoneStatus: MilestoneStatus = .pending) {
        self.id              = id
        self.title           = title
        self.date            = date
        self.isCompleted     = isCompleted
        self.notes           = notes
        self.recurrence      = recurrence
        self.reminderDays    = reminderDays
        self.reminderHour    = reminderHour
        self.linkedChapterId = linkedChapterId
        self.milestoneStatus = milestoneStatus
    }
}

// MARK: - Tag couleur (style macOS)

enum ProjectTag: String, Codable, CaseIterable {
    case red, orange, yellow, green, blue, purple, gray

    var label: String {
        switch self {
        case .red:    return "Rouge"
        case .orange: return "Orange"
        case .yellow: return "Jaune"
        case .green:  return "Vert"
        case .blue:   return "Bleu"
        case .purple: return "Violet"
        case .gray:   return "Gris"
        }
    }
}

// MARK: - Dossier de projets

struct ProjectFolder: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var projectIds: [UUID] = []
    var isExpanded: Bool = true
    /// nil = dossier racine. Sinon : id du dossier parent (imbrication).
    var parentId: UUID? = nil
}

// MARK: - Groupe de chapitres (dans un projet)

struct ChapterFolder: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var isExpanded: Bool = true
    /// nil = dossier racine (attaché directement au projet). Sinon : id du dossier parent.
    var parentId: UUID? = nil
}

// MARK: - Entrée d'historique de chapitre (V5 — amélioration #9)

struct ChapterLogEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var timestamp: String   // "yyyy-MM-dd HH:mm"
    var type: LogType
    var content: String

    enum LogType: String, Codable {
        case manual        // note manuelle saisie par l'utilisateur
        case wordUpdate    // mise à jour du compteur de mots/caractères
        case statusChange  // changement de statut du chapitre
        case draftBump     // incrément du numéro de brouillon
        case noteSession   // note de séance ajoutée via FocusWritingView
    }

    var icon: String {
        switch type {
        case .manual:       return "square.and.pencil"
        case .wordUpdate:   return "textformat.123"
        case .statusChange: return "tag.fill"
        case .draftBump:    return "doc.badge.plus"
        case .noteSession:  return "note.text"
        }
    }

    static func nowTimestamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return fmt.string(from: Date())
    }
}

// MARK: - Données quotidiennes

// MARK: - Historique d'édition d'une entrée (#6)

struct EntryEditRecord: Codable {
    var timestamp: String   // "yyyy-MM-dd HH:mm"
    var oldValue: Int
    var newValue: Int

    var delta: Int { newValue - oldValue }

    static func now() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }
}

struct DailyEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var date: String        // "yyyy-MM-dd"
    var totalCount: Int
    var note: String? = nil
    var savedAtHour: Int? = nil   // 0–23, recorded when the entry is saved
    var editHistory: [EntryEditRecord] = []  // #6 — historique éditions
    var energyLevel: Int? = nil   // #4 — niveau d'énergie 1-5, optionnel

    // Custom decoder for backwards compatibility
    init(date: String, totalCount: Int, note: String? = nil, savedAtHour: Int? = nil, energyLevel: Int? = nil) {
        self.date = date; self.totalCount = totalCount
        self.note = note; self.savedAtHour = savedAtHour
        self.energyLevel = energyLevel
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = (try? c.decodeIfPresent(UUID.self,   forKey: .id))          ?? UUID()
        date        =  try  c.decode(String.self,           forKey: .date)
        totalCount  =  try  c.decode(Int.self,              forKey: .totalCount)
        note        = try? c.decodeIfPresent(String.self,  forKey: .note)
        savedAtHour = try? c.decodeIfPresent(Int.self,     forKey: .savedAtHour)
        editHistory = (try? c.decodeIfPresent(LossyArray<EntryEditRecord>.self, forKey: .editHistory))?.elements ?? []
        energyLevel = try? c.decodeIfPresent(Int.self,     forKey: .energyLevel)
    }
}

// MARK: - Statut de chapitre (V3.2)

enum ChapterStatus: String, Codable, CaseIterable {
    case plan       = "plan"
    case redaction  = "redaction"
    case revision   = "revision"
    case termine    = "termine"

    var label: String {
        switch self {
        case .plan:      return "Plan"
        case .redaction: return "Rédaction"
        case .revision:  return "Révision"
        case .termine:   return "Terminé"
        }
    }

    var icon: String {
        switch self {
        case .plan:      return "list.bullet.rectangle"
        case .redaction: return "pencil.line"
        case .revision:  return "eye"
        case .termine:   return "checkmark.seal.fill"
        }
    }

    var color: String {
        switch self {
        case .plan:      return "#8E8E93"
        case .redaction: return "#FF9500"
        case .revision:  return "#007AFF"
        case .termine:   return "#34C759"
        }
    }
}

// MARK: - Chapitre

struct Chapter: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var goal: Int
    var entries: [DailyEntry] = []
    var tag: ProjectTag? = nil
    var isCompleted: Bool = false
    var deadline: String? = nil
    var notes: String? = nil            // Notes générales
    var notesPlan: String? = nil        // Plan / outline du chapitre
    var notesIdeas: String? = nil       // Idées & fragments
    var notesBlockers: String? = nil    // Blocages en cours
    var nextStep: String? = nil         // Prochaine action concrète
    var chapterFolderId: UUID? = nil
    var status: ChapterStatus? = nil   // V3.2 — nil = non défini
    var draftVersion: Int = 1          // V5 — numéro de brouillon (1 = premier draft)
    var logEntries: [ChapterLogEntry] = []  // V5 — historique de contexte (#9)
    var priority: ChapterPriority = .normal  // #35 — priorité
    var customTags: [String] = []            // #36 — tags libres
    var subchapters: [Chapter] = []         // #34 — sous-chapitres (max 1 niveau)
    var supervisorReviews: [SupervisorReview] = []  // historique des relectures directeur
    var checkpoints: [ChapterCheckpoint] = []       // points de sauvegarde figés
    var defenseNotes: [DefenseNote] = []            // #2 — préparation de soutenance
    var selfReviews: [SelfReview] = []              // self-évaluations qualité
    var hiddenWidgets: [String] = []                // widgets masqués sur le tableau de bord de ce chapitre
    var isArchived: Bool = false                    // chapitre mis à l'écart (toujours dans le projet, masqué par défaut)
    var isPinned: Bool = false                      // épinglé en haut de la sidebar

    // Initializer de commodité (remplace le memberwise init supprimé par le custom decoder)
    init(name: String, goal: Int, deadline: String? = nil, notes: String? = nil,
         draftVersion: Int = 1, chapterFolderId: UUID? = nil) {
        self.name           = name
        self.goal           = goal
        self.deadline       = deadline
        self.notes          = notes
        self.draftVersion   = draftVersion
        self.chapterFolderId = chapterFolderId
    }

    // Custom decoder: les champs ajoutés en V5 (draftVersion) peuvent être absents
    // des fichiers JSON créés avant la V5 — on utilise decodeIfPresent + valeur par défaut.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = (try? c.decodeIfPresent(UUID.self,           forKey: .id))             ?? UUID()
        name           = try  c.decode(String.self,                    forKey: .name)
        goal           = try  c.decode(Int.self,                       forKey: .goal)
        entries        = (try? c.decodeIfPresent(LossyArray<DailyEntry>.self,   forKey: .entries))?.elements        ?? []
        tag            = try? c.decodeIfPresent(ProjectTag.self,      forKey: .tag)
        isCompleted    = (try? c.decodeIfPresent(Bool.self,           forKey: .isCompleted))    ?? false
        deadline       = try? c.decodeIfPresent(String.self,          forKey: .deadline)
        notes           = try? c.decodeIfPresent(String.self,          forKey: .notes)
        notesPlan       = try? c.decodeIfPresent(String.self,          forKey: .notesPlan)
        notesIdeas      = try? c.decodeIfPresent(String.self,          forKey: .notesIdeas)
        notesBlockers   = try? c.decodeIfPresent(String.self,          forKey: .notesBlockers)
        nextStep        = try? c.decodeIfPresent(String.self,          forKey: .nextStep)
        chapterFolderId = try? c.decodeIfPresent(UUID.self,            forKey: .chapterFolderId)
        status          = try? c.decodeIfPresent(ChapterStatus.self,   forKey: .status)
        draftVersion    = (try? c.decodeIfPresent(Int.self,            forKey: .draftVersion))   ?? 1
        logEntries      = (try? c.decodeIfPresent(LossyArray<ChapterLogEntry>.self, forKey: .logEntries))?.elements  ?? []
        priority        = (try? c.decodeIfPresent(ChapterPriority.self,   forKey: .priority))    ?? .normal
        customTags      = (try? c.decodeIfPresent(LossyArray<String>.self,          forKey: .customTags))?.elements  ?? []
        subchapters     = (try? c.decodeIfPresent(LossyArray<Chapter>.self,         forKey: .subchapters))?.elements ?? []
        supervisorReviews = (try? c.decodeIfPresent(LossyArray<SupervisorReview>.self, forKey: .supervisorReviews))?.elements ?? []
        checkpoints     = (try? c.decodeIfPresent(LossyArray<ChapterCheckpoint>.self,  forKey: .checkpoints))?.elements ?? []
        defenseNotes    = (try? c.decodeIfPresent(LossyArray<DefenseNote>.self,        forKey: .defenseNotes))?.elements ?? []
        selfReviews     = (try? c.decodeIfPresent(LossyArray<SelfReview>.self,         forKey: .selfReviews))?.elements ?? []
        hiddenWidgets   = (try? c.decodeIfPresent(LossyArray<String>.self,             forKey: .hiddenWidgets))?.elements ?? []
        isArchived      = (try? c.decodeIfPresent(Bool.self,                 forKey: .isArchived))   ?? false
        isPinned        = (try? c.decodeIfPresent(Bool.self,                 forKey: .isPinned))     ?? false
    }

    /// La relecture en cours (la plus récente).
    var currentReview: SupervisorReview? {
        supervisorReviews.last
    }

    /// État de relecture actuel (notSent par défaut si aucun cycle ouvert).
    var reviewState: SupervisorReviewState {
        currentReview?.state ?? .notSent
    }

    /// Nombre de jours depuis l'envoi (si en attente).
    func daysSinceSent(today: Date = Date()) -> Int? {
        guard let review = currentReview,
              review.state == .sent,
              let sentStr = review.sentDate,
              let sentDate = DataStore.parseDate(sentStr) else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: sentDate, to: today).day
    }

    func entryForDate(_ date: String) -> DailyEntry? {
        entries.first(where: { $0.date == date })
    }

    func previousTotal(before date: String) -> Int {
        entries
            .filter { $0.date < date }
            .max(by: { $0.date < $1.date })?
            .totalCount ?? 0
    }

    func increment(for date: String) -> Int {
        guard let entry = entryForDate(date) else { return 0 }
        let prev = previousTotal(before: date)
        return max(0, entry.totalCount - prev)
    }
}

// MARK: - Priorité de chapitre (#35)

enum ChapterPriority: String, Codable, CaseIterable {
    case high   = "high"
    case normal = "normal"
    case low    = "low"

    var label: String {
        switch self { case .high: return "Haute"; case .normal: return "Normale"; case .low: return "Basse" }
    }
    var icon: String {
        switch self { case .high: return "exclamationmark.2"; case .normal: return "equal"; case .low: return "arrow.down" }
    }
    var color: String {
        switch self { case .high: return "#DC2626"; case .normal: return "#6B7280"; case .low: return "#9CA3AF" }
    }
}

// MARK: - Projet

struct Project: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var activeChapterId: UUID? = nil
    var chapters: [Chapter] = []
    var tag: ProjectTag? = nil
    var folderId: UUID? = nil        // nil = projet à la racine
    var chapterFolders: [ChapterFolder] = []
    var projectType: ProjectType? = nil  // V5 — type de document
    var supervisor: String? = nil        // V5 — directeur / co-auteur
    var milestones: [Milestone] = []     // V5 — jalons intermédiaires
    var notes: String? = nil             // #16 — notes libres de projet
    var isArchived: Bool = false         // #17 — projet archivé
    var isPinned: Bool = false           // épinglé en haut de la sidebar

    // Initializer de commodité (remplace le memberwise init supprimé par le custom decoder)
    init(name: String, tag: ProjectTag? = nil, projectType: ProjectType? = nil,
         supervisor: String? = nil) {
        self.name        = name
        self.tag         = tag
        self.projectType = projectType
        self.supervisor  = supervisor
    }

    // Custom decoder: milestones, projectType, supervisor absents des JSON pré-V5.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = (try? c.decodeIfPresent(UUID.self,             forKey: .id))              ?? UUID()
        name            = try  c.decode(String.self,                      forKey: .name)
        activeChapterId = try? c.decodeIfPresent(UUID.self,              forKey: .activeChapterId)
        chapters        = (try? c.decodeIfPresent(LossyArray<Chapter>.self,        forKey: .chapters))?.elements        ?? []
        tag             = try? c.decodeIfPresent(ProjectTag.self,        forKey: .tag)
        folderId        = try? c.decodeIfPresent(UUID.self,              forKey: .folderId)
        chapterFolders  = (try? c.decodeIfPresent(LossyArray<ChapterFolder>.self,  forKey: .chapterFolders))?.elements  ?? []
        projectType     = try? c.decodeIfPresent(ProjectType.self,       forKey: .projectType)
        supervisor      = try? c.decodeIfPresent(String.self,            forKey: .supervisor)
        milestones      = (try? c.decodeIfPresent(LossyArray<Milestone>.self,      forKey: .milestones))?.elements      ?? []
        notes           = try? c.decodeIfPresent(String.self,            forKey: .notes)
        isArchived      = (try? c.decodeIfPresent(Bool.self,             forKey: .isArchived))      ?? false
        isPinned        = (try? c.decodeIfPresent(Bool.self,             forKey: .isPinned))        ?? false
    }
}

// MARK: - Dates épinglées (Calendrier)

struct PinnedDate: Codable, Identifiable {
    var id: UUID = UUID()
    var date: String       // "yyyy-MM-dd"
    var label: String = ""
}

// MARK: - Défi hebdomadaire

struct WeeklyChallenge: Codable, Identifiable {
    var id: UUID = UUID()
    var weekKey: String      // "yyyy-Www" e.g. "2026-W12"
    var kind: ChallengeKind
    var target: Int
    var completedAt: String? = nil  // date string when completed

    enum ChallengeKind: String, Codable {
        case words              // write N words/chars this week
        case streak             // maintain streak of N days
        case sessions           // complete N Pomodoro sessions
        case daysWritten        // write on N distinct days this week
        case chapterCompletion  // complete N chapters this week
        case chaptersAdvanced   // advance N chapters in status (any forward move)

        var displayName: String {
            switch self {
            case .words:              return "Mots écrits"
            case .streak:             return "Série d'écriture"
            case .sessions:           return "Sessions Pomodoro"
            case .daysWritten:        return "Jours d'écriture"
            case .chapterCompletion:  return "Chapitres terminés"
            case .chaptersAdvanced:   return "Chapitres avancés"
            }
        }

        var icon: String {
            switch self {
            case .words:              return "text.cursor"
            case .streak:             return "flame.fill"
            case .sessions:           return "timer"
            case .daysWritten:        return "calendar"
            case .chapterCompletion:  return "checkmark.seal.fill"
            case .chaptersAdvanced:   return "arrow.up.right.circle.fill"
            }
        }

        var unit: String {
            switch self {
            case .words:              return "car."
            case .streak:             return "jours"
            case .sessions:           return "sessions"
            case .daysWritten:        return "jours"
            case .chapterCompletion:  return "chap."
            case .chaptersAdvanced:   return "chap."
            }
        }
    }

    var isCompleted: Bool { completedAt != nil }
}

// MARK: - Journal de bord doctoral

struct JournalEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var date: String              // "yyyy-MM-dd"
    var content: String
    var mood: Int? = nil          // 1-5 optionnel
    var tags: [String] = []
    var createdAt: String         // "yyyy-MM-dd HH:mm"
    var updatedAt: String         // "yyyy-MM-dd HH:mm"

    init(id: UUID = UUID(), date: String, content: String, mood: Int? = nil,
         tags: [String] = [], createdAt: String, updatedAt: String) {
        self.id = id
        self.date = date
        self.content = content
        self.mood = mood
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = (try? c.decodeIfPresent(UUID.self,    forKey: .id))        ?? UUID()
        date      =  try  c.decode(String.self,           forKey: .date)
        content   =  try  c.decode(String.self,           forKey: .content)
        mood      = try? c.decodeIfPresent(Int.self,      forKey: .mood)
        tags      = (try? c.decodeIfPresent(LossyArray<String>.self,forKey: .tags))?.elements      ?? []
        createdAt = (try? c.decodeIfPresent(String.self,  forKey: .createdAt)) ?? date
        updatedAt = (try? c.decodeIfPresent(String.self,  forKey: .updatedAt)) ?? createdAt
    }
}

// MARK: - Carnet de fragments

struct Fragment: Codable, Identifiable {
    var id: UUID = UUID()
    var content: String
    var createdAt: String         // "yyyy-MM-dd HH:mm"
    var tags: [String] = []
    var archivedAt: String? = nil
    var movedToChapterId: UUID? = nil
    var movedAt: String? = nil

    init(id: UUID = UUID(), content: String, createdAt: String,
         tags: [String] = [], archivedAt: String? = nil,
         movedToChapterId: UUID? = nil, movedAt: String? = nil) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.tags = tags
        self.archivedAt = archivedAt
        self.movedToChapterId = movedToChapterId
        self.movedAt = movedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = (try? c.decodeIfPresent(UUID.self,    forKey: .id))            ?? UUID()
        content          =  try  c.decode(String.self,           forKey: .content)
        createdAt        =  try  c.decode(String.self,           forKey: .createdAt)
        tags             = (try? c.decodeIfPresent(LossyArray<String>.self, forKey: .tags))?.elements         ?? []
        archivedAt       = try? c.decodeIfPresent(String.self,    forKey: .archivedAt)
        movedToChapterId = try? c.decodeIfPresent(UUID.self,      forKey: .movedToChapterId)
        movedAt          = try? c.decodeIfPresent(String.self,    forKey: .movedAt)
    }

    var isActive: Bool { archivedAt == nil && movedToChapterId == nil }
}

// MARK: - Bilan mensuel automatique

struct MonthlyReport: Codable, Identifiable {
    var id: UUID = UUID()
    var monthKey: String            // "yyyy-MM"
    var generatedAt: String         // "yyyy-MM-dd HH:mm"
    var charsWritten: Int
    var daysActive: Int
    var chaptersFinished: Int
    var bestDay: String?
    var bestDayCount: Int
    var streakAtMonthEnd: Int
    var headline: String            // résumé d'une ligne
    var userNotes: String? = nil    // place pour réflexion libre
}

// MARK: - Self-review d'un chapitre

struct SelfReview: Codable, Identifiable {
    var id: UUID = UUID()
    var date: String                // "yyyy-MM-dd"
    var draftVersion: Int
    var clarity: Int                // 1-5
    var argumentation: Int
    var citations: Int
    var transitions: Int
    var originality: Int
    var notes: String? = nil

    var average: Double {
        Double(clarity + argumentation + citations + transitions + originality) / 5.0
    }
}

// MARK: - Tâche administrative

struct AdminTask: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var kind: Kind
    var dueDate: String? = nil      // "yyyy-MM-dd"
    var isCompleted: Bool = false
    var completedAt: String? = nil
    var notes: String? = nil
    var createdAt: String

    enum Kind: String, Codable, CaseIterable {
        case form           // formulaires administratifs
        case meeting        // rendez-vous directeur, comité
        case milestone      // jalon académique (rapport, comité de suivi)
        case authorization  // autorisations
        case other

        var label: String {
            switch self {
            case .form:           return "Formulaire"
            case .meeting:        return "Rendez-vous"
            case .milestone:      return "Jalon académique"
            case .authorization:  return "Autorisation"
            case .other:          return "Autre"
            }
        }
        var icon: String {
            switch self {
            case .form:          return "doc.text.fill"
            case .meeting:       return "person.2.fill"
            case .milestone:     return "flag.fill"
            case .authorization: return "checkmark.shield.fill"
            case .other:         return "tag.fill"
            }
        }
        var color: Color {
            switch self {
            case .form:          return Color(red: 0.25, green: 0.55, blue: 0.95)
            case .meeting:       return Color(red: 0.404, green: 0.224, blue: 0.718)
            case .milestone:     return Color(red: 0.929, green: 0.329, blue: 0.329)
            case .authorization: return Color(red: 0.22, green: 0.75, blue: 0.44)
            case .other:         return .labelMuted
            }
        }
    }

    init(id: UUID = UUID(), title: String, kind: Kind, dueDate: String? = nil,
         isCompleted: Bool = false, completedAt: String? = nil,
         notes: String? = nil, createdAt: String) {
        self.id = id
        self.title = title
        self.kind = kind
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.notes = notes
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = (try? c.decodeIfPresent(UUID.self,   forKey: .id))           ?? UUID()
        title       =  try  c.decode(String.self,           forKey: .title)
        kind        = (try? c.decodeIfPresent(Kind.self,   forKey: .kind))         ?? .other
        dueDate     = try? c.decodeIfPresent(String.self,  forKey: .dueDate)
        isCompleted = (try? c.decodeIfPresent(Bool.self,   forKey: .isCompleted))  ?? false
        completedAt = try? c.decodeIfPresent(String.self,  forKey: .completedAt)
        notes       = try? c.decodeIfPresent(String.self,  forKey: .notes)
        createdAt   = (try? c.decodeIfPresent(String.self, forKey: .createdAt))    ?? title
    }
}

// MARK: - Plan de bataille hebdomadaire (#1 / nouveau)

struct WeeklyPlanItem: Codable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var isDone: Bool = false
    var chapterId: UUID? = nil       // chapitre lié (optionnel)
    var doneDate: String? = nil      // "yyyy-MM-dd" si done
}

struct WeeklyPlan: Codable, Identifiable {
    var id: UUID = UUID()
    var weekKey: String              // "yyyy-Www"
    var items: [WeeklyPlanItem] = []
    var createdAt: String            // "yyyy-MM-dd"

    var doneCount: Int { items.filter { $0.isDone }.count }
    var totalCount: Int { items.count }
    var completionRatio: Double {
        guard !items.isEmpty else { return 0 }
        return Double(doneCount) / Double(items.count)
    }
}

// MARK: - Notes de soutenance (#2)

struct DefenseNote: Codable, Identifiable {
    var id: UUID = UUID()
    var kind: Kind
    var text: String
    var createdAt: String            // "yyyy-MM-dd"

    enum Kind: String, Codable, CaseIterable {
        case point        // point à défendre
        case question     // question probable
        case counter      // contre-argument / réfutation

        var label: String {
            switch self {
            case .point:    return "À défendre"
            case .question: return "Question probable"
            case .counter:  return "Contre-argument"
            }
        }
        var icon: String {
            switch self {
            case .point:    return "checkmark.shield.fill"
            case .question: return "questionmark.circle.fill"
            case .counter:  return "exclamationmark.shield.fill"
            }
        }
        var color: Color {
            switch self {
            case .point:    return Color(red: 0.22, green: 0.75, blue: 0.44)
            case .question: return Color(red: 0.25, green: 0.55, blue: 0.95)
            case .counter:  return Color(red: 0.93, green: 0.40, blue: 0.20)
            }
        }
    }
}

// MARK: - Entrée de recherche (feature #2)

enum ResearchType: String, Codable, CaseIterable, Identifiable {
    case lecture      = "lecture"
    case analyse      = "analyse"
    case reunion      = "reunion"
    case terrain      = "terrain"
    case enseignement = "enseignement"
    case autre        = "autre"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lecture:      return "Lecture"
        case .analyse:      return "Analyse"
        case .reunion:      return "Réunion"
        case .terrain:      return "Terrain"
        case .enseignement: return "Enseignement"
        case .autre:        return "Autre"
        }
    }

    var icon: String {
        switch self {
        case .lecture:      return "book.fill"
        case .analyse:      return "magnifyingglass"
        case .reunion:      return "person.2.fill"
        case .terrain:      return "map.fill"
        case .enseignement: return "graduationcap.fill"
        case .autre:        return "ellipsis.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .lecture:      return "#0F766E"
        case .analyse:      return "#7C3AED"
        case .reunion:      return "#0369A1"
        case .terrain:      return "#16A34A"
        case .enseignement: return "#B45309"
        case .autre:        return "#6B7280"
        }
    }
}

struct ResearchEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var date: String           // "yyyy-MM-dd"
    var durationMinutes: Int
    var type: ResearchType
    var note: String? = nil
    var projectId: UUID? = nil
    var chapterId: UUID? = nil
}

// MARK: - Données globales

struct AppData: Codable {
    var dailyGoal: Int = 500
    var weeklyGoal: Int = 3000
    var monthlyGoal: Int = 15000
    var projects: [Project] = []
    var activeProjectId: UUID? = nil
    var folders: [ProjectFolder] = []
    var sortProjectsAlphabetically: Bool = false
    var sortChaptersAlphabetically: Bool = false
    var useWordCount: Bool = false
    var pinnedDates: [PinnedDate] = []
    var weeklyChallenges: [WeeklyChallenge] = []
    var researchEntries: [ResearchEntry] = []   // feature #2
    var weeklyPlans: [WeeklyPlan] = []          // #1 — plan de bataille hebdo
    var restDays: [String] = []                 // #5 — jours de repos planifiés ("yyyy-MM-dd")
    var targetDefenseDate: String? = nil        // #7 — date de soutenance cible
    var journalEntries: [JournalEntry] = []     // Journal de bord doctoral
    var fragments: [Fragment] = []              // Carnet de fragments
    var monthlyReports: [MonthlyReport] = []    // Bilans mensuels auto-générés
    var adminTasks: [AdminTask] = []            // Checklist administrative

    // Legacy migration fields (old format had chapters at top level)
    var legacyChapters: [Chapter]?
    var legacyActiveChapterId: UUID?

    enum CodingKeys: String, CodingKey {
        case dailyGoal, weeklyGoal, monthlyGoal, projects, activeProjectId
        case folders, sortProjectsAlphabetically, sortChaptersAlphabetically, useWordCount
        case pinnedDates, weeklyChallenges, researchEntries
        case weeklyPlans, restDays, targetDefenseDate
        case journalEntries, fragments, monthlyReports, adminTasks
        case legacyChapters = "chapters"
        case legacyActiveChapterId = "activeChapterId"
    }
}

extension AppData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyGoal                  = (try? c.decodeIfPresent(Int.self,                  forKey: .dailyGoal))                  ?? 500
        weeklyGoal                 = (try? c.decodeIfPresent(Int.self,                  forKey: .weeklyGoal))                 ?? 3000
        monthlyGoal                = (try? c.decodeIfPresent(Int.self,                  forKey: .monthlyGoal))                ?? 15000
        projects                   = (try? c.decodeIfPresent(LossyArray<Project>.self,            forKey: .projects))?.elements                   ?? []
        activeProjectId            = try? c.decodeIfPresent(UUID.self,                  forKey: .activeProjectId)
        folders                    = (try? c.decodeIfPresent(LossyArray<ProjectFolder>.self,      forKey: .folders))?.elements                    ?? []
        sortProjectsAlphabetically = (try? c.decodeIfPresent(Bool.self,                forKey: .sortProjectsAlphabetically)) ?? false
        sortChaptersAlphabetically = (try? c.decodeIfPresent(Bool.self,                forKey: .sortChaptersAlphabetically)) ?? false
        useWordCount               = (try? c.decodeIfPresent(Bool.self,                forKey: .useWordCount))               ?? false
        pinnedDates                = (try? c.decodeIfPresent(LossyArray<PinnedDate>.self,         forKey: .pinnedDates))?.elements                ?? []
        weeklyChallenges           = (try? c.decodeIfPresent(LossyArray<WeeklyChallenge>.self,    forKey: .weeklyChallenges))?.elements           ?? []
        researchEntries            = (try? c.decodeIfPresent(LossyArray<ResearchEntry>.self,      forKey: .researchEntries))?.elements            ?? []
        weeklyPlans                = (try? c.decodeIfPresent(LossyArray<WeeklyPlan>.self,          forKey: .weeklyPlans))?.elements                ?? []
        restDays                   = (try? c.decodeIfPresent(LossyArray<String>.self,              forKey: .restDays))?.elements                   ?? []
        targetDefenseDate          = try? c.decodeIfPresent(String.self,                 forKey: .targetDefenseDate)
        journalEntries             = (try? c.decodeIfPresent(LossyArray<JournalEntry>.self,        forKey: .journalEntries))?.elements             ?? []
        fragments                  = (try? c.decodeIfPresent(LossyArray<Fragment>.self,            forKey: .fragments))?.elements                  ?? []
        monthlyReports             = (try? c.decodeIfPresent(LossyArray<MonthlyReport>.self,       forKey: .monthlyReports))?.elements             ?? []
        adminTasks                 = (try? c.decodeIfPresent(LossyArray<AdminTask>.self,           forKey: .adminTasks))?.elements                 ?? []
        legacyChapters             = (try? c.decodeIfPresent(LossyArray<Chapter>.self,             forKey: .legacyChapters))?.elements
        legacyActiveChapterId      = try? c.decodeIfPresent(UUID.self,                  forKey: .legacyActiveChapterId)
    }
}
