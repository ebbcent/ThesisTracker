import XCTest
@testable import Writing_Process

/// 5.13 — Professeur : contexte du coffre, requête API, journal « Échanges app ».
@MainActor
final class ProfessorTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ProfessorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testTruncateKeepsStartOrEnd() {
        let text = "abcdefghij"
        XCTAssertEqual(ProfessorContext.truncate(text, limit: 20, keepEnd: false).truncated, false)
        let start = ProfessorContext.truncate(text, limit: 4, keepEnd: false)
        XCTAssertTrue(start.truncated)
        XCTAssertTrue(start.text.hasPrefix("abcd"))
        let end = ProfessorContext.truncate(text, limit: 4, keepEnd: true)
        XCTAssertTrue(end.text.hasSuffix("ghij"))
    }

    func testExtractDeadlinesSection() {
        let md = """
        # Tâches
        - [ ] autre
        ## Deadlines
        - [ ] 15/06/27 Dépôt de la thèse
        ### Détail
        - sous-point
        ## Plus tard
        - [ ] rien
        """
        let section = ProfessorContext.extractSection(md, heading: "deadlines")
        XCTAssertNotNil(section)
        XCTAssertTrue(section!.contains("Dépôt de la thèse"))
        XCTAssertTrue(section!.contains("sous-point"))
        XCTAssertFalse(section!.contains("rien"))
        XCTAssertNil(ProfessorContext.extractSection(md, heading: "Absent"))
    }

    func testReadTextMissingFile() {
        let (text, status) = ProfessorContext.readText(tmp.appendingPathComponent("absent.md"))
        XCTAssertNil(text)
        XCTAssertEqual(status, .missing)
    }

    func testContextReadsVaultFilesAndNeverWrites() throws {
        let folder = tmp.appendingPathComponent("Thèse/10.1 Autres/Directeur de thèse")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "Engagement : plan du ch. 5".write(to: folder.appendingPathComponent("Suivi.md"), atomically: true, encoding: .utf8)
        try "## À reprendre\n- volume ch. 4".write(to: folder.appendingPathComponent("Mémoire du professeur.md"), atomically: true, encoding: .utf8)
        try "## Deadlines\n- 15/06/27 Dépôt".write(to: tmp.appendingPathComponent("Thèse/Taches.md"), atomically: true, encoding: .utf8)
        let before = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()

        let context = ProfessorContext.build(store: DataStore.preview, folder: folder)

        XCTAssertTrue(context.body.contains("plan du ch. 5"))
        XCTAssertTrue(context.body.contains("volume ch. 4"))
        XCTAssertTrue(context.body.contains("15/06/27 Dépôt"))
        XCTAssertFalse(context.personaFromVault)
        XCTAssertEqual(context.sources.first(where: { $0.label == "Profil de Clément.md" })?.status, .missing)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(), before)
    }

    func testCustomPersonaFromVault() throws {
        try "Consignes perso".write(to: tmp.appendingPathComponent("Consignes app.md"), atomically: true, encoding: .utf8)
        let context = ProfessorContext.build(store: DataStore.preview, folder: tmp)
        XCTAssertTrue(context.personaFromVault)
        XCTAssertEqual(context.persona, "Consignes perso")
    }

    func testRequestBodyCachesContextAndAttachment() {
        let messages = [
            AnthropicClient.Message(role: .user, text: "Question", attachment: "<texte_joint>…</texte_joint>"),
            AnthropicClient.Message(role: .assistant, text: "Réponse")
        ]
        let body = AnthropicClient.requestBody(model: "claude-opus-5-5", maxTokens: 100,
                                               persona: "P", context: "C", messages: messages)
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        let system = body["system"] as? [[String: Any]]
        XCTAssertEqual(system?.count, 2)
        XCTAssertNil(system?[0]["cache_control"])
        XCTAssertNotNil(system?[1]["cache_control"])
        let msgs = body["messages"] as? [[String: Any]]
        let firstBlocks = msgs?[0]["content"] as? [[String: Any]]
        XCTAssertEqual(firstBlocks?.count, 2)
        XCTAssertNotNil(firstBlocks?[0]["cache_control"])
        XCTAssertEqual(firstBlocks?[1]["text"] as? String, "Question")
        XCTAssertEqual(msgs?[1]["role"] as? String, "assistant")
    }

    func testParseReply() throws {
        let json = """
        {"content":[{"type":"text","text":"Bonjour Clem."}],"stop_reason":"end_turn",
         "usage":{"input_tokens":10,"cache_read_input_tokens":900,"cache_creation_input_tokens":0,"output_tokens":5}}
        """
        let reply = try AnthropicClient.parseReply(Data(json.utf8))
        XCTAssertEqual(reply.text, "Bonjour Clem.")
        XCTAssertEqual(reply.usage.cacheRead, 900)
        XCTAssertFalse(reply.stoppedAtLimit)
    }

    func testJournalAppendsWithoutOverwriting() throws {
        let url = tmp.appendingPathComponent("Échanges app/2026-11.md")
        let q = ProfessorTurn(role: .user, text: "Où en est le ch. 4 ?", date: Date())
        let a = ProfessorTurn(role: .assistant, text: "Qu'est-ce qui a bloqué ?", date: Date())
        let first = ProfessorSession.journalBlock(question: q, answer: a, model: "claude-opus-5-5", sessionStart: q.date, isFirstOfSession: true)
        let second = ProfessorSession.journalBlock(question: q, answer: a, model: "claude-opus-5-5", sessionStart: q.date, isFirstOfSession: false)
        try ProfessorSession.append(first, to: url, monthTitle: "2026-11")
        try ProfessorSession.append(second, to: url, monthTitle: "2026-11")
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("# Échanges app — 2026-11"))
        XCTAssertEqual(content.components(separatedBy: "— séance app").count - 1, 1)
        XCTAssertEqual(content.components(separatedBy: "**L. Vandenbossche**").count - 1, 2)
    }

    func testNotificationPreviewFlattensAndShortens() {
        XCTAssertEqual(ProfessorSession.notificationPreview("**Clem**,\n\nqu'est-ce qui a bloqué ?"), "Clem, qu'est-ce qui a bloqué ?")
        let long = String(repeating: "a", count: 300)
        let preview = ProfessorSession.notificationPreview(long)
        XCTAssertEqual(preview.count, 181)
        XCTAssertTrue(preview.hasSuffix("…"))
    }

    func testTextAttachmentCountsSigns() throws {
        let url = tmp.appendingPathComponent("2026-11-13 — ch4.txt")
        try "Rex et le Parlement.".write(to: url, atomically: true, encoding: .utf8)
        let attachment = try ProfessorContext.loadAttachment(url)
        XCTAssertEqual(attachment.signs, 20)
        XCTAssertFalse(attachment.truncated)
        XCTAssertThrowsError(try ProfessorContext.loadAttachment(tmp.appendingPathComponent("x.pages")))
    }
}
