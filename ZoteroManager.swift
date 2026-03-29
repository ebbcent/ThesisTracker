import Foundation
import SQLite3

// MARK: - ZoteroManager
// Lit la base SQLite de Zotero en mode lecture seule.
// Zotero stocke sa base dans ~/Zotero/zotero.sqlite.

final class ZoteroManager: ObservableObject {
    static let shared = ZoteroManager()

    @Published var items: [ZoteroItem] = []
    @Published var isAvailable: Bool = false

    private var dbPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Zotero/zotero.sqlite").path
    }

    /// Charge les items Zotero depuis la base SQLite (thread-safe, publie sur le main).
    func load() {
        guard FileManager.default.fileExists(atPath: dbPath) else {
            DispatchQueue.main.async { self.isAvailable = false }
            return
        }
        DispatchQueue.main.async { self.isAvailable = true }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var results: [ZoteroItem] = []

            var db: OpaquePointer?
            guard sqlite3_open_v2(self.dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return }
            defer { sqlite3_close(db) }

            // Requête : titres des items (hors pièces jointes et notes)
            let query = """
                SELECT i.key, idv.value, it.typeName
                FROM items i
                JOIN itemTypes it ON i.itemTypeID = it.itemTypeID
                JOIN itemData id2 ON i.itemID = id2.itemID
                JOIN itemDataValues idv ON id2.valueID = idv.valueID
                JOIN fields f ON id2.fieldID = f.fieldID
                WHERE f.fieldName = 'title'
                  AND it.typeName NOT IN ('attachment', 'note')
                  AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
                ORDER BY idv.value
                LIMIT 500
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                let key      = String(cString: sqlite3_column_text(stmt, 0))
                let title    = String(cString: sqlite3_column_text(stmt, 1))
                let typeName = String(cString: sqlite3_column_text(stmt, 2))
                results.append(ZoteroItem(id: key, title: title, authors: "", year: "", itemType: typeName))
            }

            DispatchQueue.main.async { self.items = results }
        }
    }
}
