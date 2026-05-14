import Foundation
import AppKit
import CoreSpotlight
import UniformTypeIdentifiers

// MARK: - Feature #51 : Intégration Spotlight
// Indexe tous les projets et chapitres dans CoreSpotlight so they appear
// when the user searches from macOS Spotlight (⌘Space).
// Triggered automatically via DataStore.save() and on first launch.

final class SpotlightIndexer {

    static let shared = SpotlightIndexer()

    private let index = CSSearchableIndex.default()
    private let domainId = "com.thesistracker"

    // Unique identifier prefixes
    static let projectPrefix = "com.thesistracker.project."
    static let chapterPrefix = "com.thesistracker.chapter."

    /// Throttle: re-index at most once every `minInterval` seconds. A full
    /// rebuild iterates every project + chapter and round-trips through
    /// CoreSpotlight's IPC; doing it on every save (which already debounces
    /// to 0.35s) was still wasteful for users who type continuously for
    /// minutes. We coalesce trailing-edge updates so the latest snapshot
    /// always wins.
    private let throttleQueue = DispatchQueue(label: "spotlight-throttle")
    private var lastReindexAt: Date = .distantPast
    private var pendingSnapshot: AppData?
    private var pendingWorkItem: DispatchWorkItem?
    private let minInterval: TimeInterval = 5

    private init() {}

    // MARK: - Public API

    /// Throttled re-index. Calls within `minInterval` are coalesced.
    func reindex(_ data: AppData) {
        throttleQueue.async { [weak self] in
            guard let self else { return }
            self.pendingSnapshot = data
            let elapsed = Date().timeIntervalSince(self.lastReindexAt)
            if elapsed >= self.minInterval {
                self.flushPending()
            } else {
                // Schedule a single trailing flush
                self.pendingWorkItem?.cancel()
                let item = DispatchWorkItem { [weak self] in self?.flushPending() }
                self.pendingWorkItem = item
                self.throttleQueue.asyncAfter(deadline: .now() + (self.minInterval - elapsed), execute: item)
            }
        }
    }

    private func flushPending() {
        guard let snapshot = pendingSnapshot else { return }
        pendingSnapshot = nil
        pendingWorkItem = nil
        lastReindexAt = Date()
        performReindex(snapshot)
    }

    private func performReindex(_ data: AppData) {
        var items: [CSSearchableItem] = []
        for project in data.projects where !project.isArchived {
            items.append(makeProjectItem(project))
            for chapter in project.chapters {
                items.append(makeChapterItem(chapter, in: project))
            }
        }
        index.deleteSearchableItems(withDomainIdentifiers: [domainId]) { [weak self] _ in
            guard let self else { return }
            self.index.indexSearchableItems(items) { error in
                if let error {
                    print("[Spotlight] Indexing error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Remove all ThesisTracker items from Spotlight (e.g. on sign-out / reset).
    func deleteAll() {
        index.deleteSearchableItems(withDomainIdentifiers: [domainId]) { _ in }
    }

    // MARK: - Item builders

    private func makeProjectItem(_ project: Project) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title           = project.name
        attrs.contentDescription = buildProjectDescription(project)
        attrs.keywords        = ["projet", "thèse", project.name]
        if let notes = project.notes, !notes.isEmpty {
            attrs.textContent = notes
        }
        attrs.thumbnailData   = iconImage(systemName: "folder.fill", color: .systemBlue)
        let id = Self.projectPrefix + project.id.uuidString
        return CSSearchableItem(uniqueIdentifier: id,
                                domainIdentifier: domainId,
                                attributeSet: attrs)
    }

    private func makeChapterItem(_ chapter: Chapter, in project: Project) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title           = chapter.name
        attrs.contentDescription = buildChapterDescription(chapter, projectName: project.name)
        var keywords = ["chapitre", "thèse", chapter.name, project.name]
        keywords += chapter.customTags
        if let next = chapter.nextStep { keywords.append(next) }
        attrs.keywords        = keywords

        // Full-text content for Spotlight indexing
        let textParts: [String?] = [
            chapter.notes, chapter.notesPlan,
            chapter.notesIdeas, chapter.notesBlockers, chapter.nextStep
        ]
        attrs.textContent = textParts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")

        if chapter.isCompleted {
            attrs.thumbnailData = iconImage(systemName: "checkmark.circle.fill", color: .systemGreen)
        } else {
            attrs.thumbnailData = iconImage(systemName: "book.closed.fill", color: .systemIndigo)
        }

        let id = Self.chapterPrefix + chapter.id.uuidString
        return CSSearchableItem(uniqueIdentifier: id,
                                domainIdentifier: domainId,
                                attributeSet: attrs)
    }

    // MARK: - Description helpers

    private func buildProjectDescription(_ project: Project) -> String {
        let chapterCount = project.chapters.count
        let completed    = project.chapters.filter(\.isCompleted).count
        var parts: [String] = ["\(chapterCount) chapitre\(chapterCount > 1 ? "s" : "")"]
        if completed > 0 {
            parts.append("\(completed) terminé\(completed > 1 ? "s" : "")")
        }
        if let notes = project.notes, !notes.isEmpty {
            parts.append(String(notes.prefix(80)))
        }
        return parts.joined(separator: " · ")
    }

    private func buildChapterDescription(_ chapter: Chapter, projectName: String) -> String {
        var parts: [String] = [projectName]
        if chapter.goal > 0 {
            let latest = chapter.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
            let pct    = Int(min(100, Double(latest) / Double(chapter.goal) * 100))
            parts.append("\(pct)% complété")
        }
        if let next = chapter.nextStep, !next.isEmpty {
            parts.append("→ \(next)")
        } else if let notes = chapter.notes, !notes.isEmpty {
            parts.append(String(notes.prefix(60)))
        }
        if !chapter.customTags.isEmpty {
            parts.append(chapter.customTags.prefix(3).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Icon helper (renders SF Symbol to PNG data)

    private func iconImage(systemName: String, color: NSColor) -> Data? {
        let size   = CGSize(width: 40, height: 40)
        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return nil }
        let img = NSImage(size: size)
        img.lockFocus()
        color.setFill()
        NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: 8, yRadius: 8).fill()
        let symRect = CGRect(
            x: (size.width  - 22) / 2,
            y: (size.height - 22) / 2,
            width: 22, height: 22
        )
        symbol.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        img.unlockFocus()
        return img.tiffRepresentation
    }
}

// MARK: - Navigation helper
// Decodes a Spotlight activity identifier back to a project/chapter reference.

struct SpotlightTarget {
    enum Destination {
        case project(UUID)
        case chapter(chapterId: UUID)
    }
    let destination: Destination

    static func from(activityIdentifier: String) -> SpotlightTarget? {
        if activityIdentifier.hasPrefix(SpotlightIndexer.chapterPrefix) {
            let uuidStr = String(activityIdentifier.dropFirst(SpotlightIndexer.chapterPrefix.count))
            guard let id = UUID(uuidString: uuidStr) else { return nil }
            return SpotlightTarget(destination: .chapter(chapterId: id))
        }
        if activityIdentifier.hasPrefix(SpotlightIndexer.projectPrefix) {
            let uuidStr = String(activityIdentifier.dropFirst(SpotlightIndexer.projectPrefix.count))
            guard let id = UUID(uuidString: uuidStr) else { return nil }
            return SpotlightTarget(destination: .project(id))
        }
        return nil
    }
}
