import Foundation
import AppKit

// MARK: - DOCXWriter (mini-writer .docx + helpers RTF / presse-papier)

/// Mini écrivain DOCX produisant un fichier Word valide à partir de blocs simples.
/// Un .docx est un ZIP contenant des XML : on réutilise le ZIP `stored` (sans compression)
/// déjà implémenté pour `XLSXWriter`.
enum DOCXWriter {

    /// Bloc de contenu pour la génération.
    enum Block {
        case heading(level: Int, text: String)   // 1-3
        case paragraph(String)
        case bullet(String)
        case spacer
    }

    /// Génère un Data .docx valide.
    static func make(title: String, blocks: [Block]) -> Data {
        let documentXML = buildDocumentXML(blocks: blocks)
        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """
        let relsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
        let files: [(String, Data)] = [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels",         Data(relsXML.utf8)),
            ("word/document.xml",   Data(documentXML.utf8))
        ]
        return zipStored(files: files)
    }

    // MARK: - XML builders

    private static func buildDocumentXML(blocks: [Block]) -> String {
        var body = ""
        for block in blocks {
            switch block {
            case .heading(let lvl, let text):
                body += headingXML(level: lvl, text: text)
            case .paragraph(let text):
                body += paragraphXML(text: text)
            case .bullet(let text):
                body += bulletXML(text: text)
            case .spacer:
                body += "<w:p/>"
            }
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:body>
                \(body)
            </w:body>
        </w:document>
        """
    }

    private static func headingXML(level: Int, text: String) -> String {
        let size: Int
        switch level {
        case 1: size = 36
        case 2: size = 28
        default: size = 24
        }
        return """
        <w:p>
            <w:pPr>
                <w:spacing w:before="240" w:after="120"/>
            </w:pPr>
            <w:r>
                <w:rPr>
                    <w:b/>
                    <w:sz w:val="\(size)"/>
                </w:rPr>
                <w:t xml:space="preserve">\(escapeXML(text))</w:t>
            </w:r>
        </w:p>
        """
    }

    private static func paragraphXML(text: String) -> String {
        // Convertir les \n en sauts de ligne
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var runs = ""
        for (i, line) in lines.enumerated() {
            if i > 0 { runs += "<w:r><w:br/></w:r>" }
            runs += "<w:r><w:rPr><w:sz w:val=\"22\"/></w:rPr><w:t xml:space=\"preserve\">\(escapeXML(String(line)))</w:t></w:r>"
        }
        return """
        <w:p>
            <w:pPr><w:spacing w:after="120"/></w:pPr>
            \(runs)
        </w:p>
        """
    }

    private static func bulletXML(text: String) -> String {
        return """
        <w:p>
            <w:pPr>
                <w:ind w:left="360"/>
                <w:spacing w:after="60"/>
            </w:pPr>
            <w:r><w:rPr><w:sz w:val="22"/></w:rPr><w:t xml:space="preserve">•  \(escapeXML(text))</w:t></w:r>
        </w:p>
        """
    }

    // MARK: - ZIP stored (réutilisé de XLSXWriter)

    private static func zipStored(files: [(String, Data)]) -> Data {
        var output = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for (path, data) in files {
            let pathData = Data(path.utf8)
            let crc = crc32(data)
            let compressedSize = UInt32(data.count)
            let uncompressedSize = UInt32(data.count)

            output.append(littleEndian(UInt32(0x04034b50)))
            output.append(littleEndian(UInt16(20)))
            output.append(littleEndian(UInt16(0)))
            output.append(littleEndian(UInt16(0)))
            output.append(littleEndian(UInt16(0)))
            output.append(littleEndian(UInt16(0)))
            output.append(littleEndian(crc))
            output.append(littleEndian(compressedSize))
            output.append(littleEndian(uncompressedSize))
            output.append(littleEndian(UInt16(pathData.count)))
            output.append(littleEndian(UInt16(0)))
            output.append(pathData)
            output.append(data)

            centralDirectory.append(littleEndian(UInt32(0x02014b50)))
            centralDirectory.append(littleEndian(UInt16(20)))
            centralDirectory.append(littleEndian(UInt16(20)))
            centralDirectory.append(littleEndian(UInt16(0)))
            centralDirectory.append(littleEndian(UInt16(0)))
            centralDirectory.append(littleEndian(UInt16(0)))
            centralDirectory.append(littleEndian(UInt16(0)))
            centralDirectory.append(littleEndian(crc))
            centralDirectory.append(littleEndian(compressedSize))
            centralDirectory.append(littleEndian(uncompressedSize))
            centralDirectory.append(littleEndian(UInt16(pathData.count)))
            centralDirectory.append(littleEndian(UInt16(0)))
            centralDirectory.append(littleEndian(UInt16(0)))
            centralDirectory.append(littleEndian(UInt16(0)))
            centralDirectory.append(littleEndian(UInt16(0)))
            centralDirectory.append(littleEndian(UInt32(0)))
            centralDirectory.append(littleEndian(offset))
            centralDirectory.append(pathData)

            offset = UInt32(output.count)
        }

        let centralOffset = UInt32(output.count)
        output.append(centralDirectory)
        output.append(littleEndian(UInt32(0x06054b50)))
        output.append(littleEndian(UInt16(0)))
        output.append(littleEndian(UInt16(0)))
        output.append(littleEndian(UInt16(files.count)))
        output.append(littleEndian(UInt16(files.count)))
        output.append(littleEndian(UInt32(centralDirectory.count)))
        output.append(littleEndian(centralOffset))
        output.append(littleEndian(UInt16(0)))
        return output
    }

    private static func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        var value = value.littleEndian
        return Data(bytes: &value, count: MemoryLayout<T>.size)
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func crc32(_ data: Data) -> UInt32 {
        let table: [UInt32] = (0..<256).map { index in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? 0xEDB88320 ^ (value >> 1) : (value >> 1)
            }
            return value
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - Helpers d'export pour le journal de bord

enum JournalExport {
    /// Construit les blocs DOCX pour un ensemble d'entrées de journal.
    static func docxBlocks(entries: [JournalEntry], title: String = "Journal de bord") -> [DOCXWriter.Block] {
        var blocks: [DOCXWriter.Block] = []
        blocks.append(.heading(level: 1, text: title))
        let exportFmt = DateFormatter()
        exportFmt.locale = Locale(identifier: "fr_FR")
        exportFmt.dateFormat = "EEEE d MMMM yyyy"

        let grouped = Dictionary(grouping: entries) { $0.date }
        let sortedDates = grouped.keys.sorted(by: >)
        for date in sortedDates {
            let dateLabel: String = {
                if let d = DataStore.parseDate(date) {
                    let s = exportFmt.string(from: d)
                    return s.prefix(1).uppercased() + s.dropFirst()
                }
                return date
            }()
            blocks.append(.heading(level: 2, text: dateLabel))
            for entry in grouped[date]!.sorted(by: { $0.createdAt < $1.createdAt }) {
                if !entry.tags.isEmpty {
                    blocks.append(.paragraph("Tags : " + entry.tags.map { "#\($0)" }.joined(separator: " ")))
                }
                if let mood = entry.mood {
                    blocks.append(.paragraph("Humeur : \(mood)/5"))
                }
                blocks.append(.paragraph(entry.content))
                blocks.append(.spacer)
            }
        }
        return blocks
    }

    /// Génère un texte Markdown équivalent (utilisé pour le presse-papier vers Apple Notes).
    static func markdown(entries: [JournalEntry], title: String = "Journal de bord") -> String {
        var lines: [String] = ["# \(title)", ""]
        let exportFmt = DateFormatter()
        exportFmt.locale = Locale(identifier: "fr_FR")
        exportFmt.dateFormat = "EEEE d MMMM yyyy"

        let grouped = Dictionary(grouping: entries) { $0.date }
        let sortedDates = grouped.keys.sorted(by: >)
        for date in sortedDates {
            let dateLabel: String = {
                if let d = DataStore.parseDate(date) {
                    let s = exportFmt.string(from: d)
                    return s.prefix(1).uppercased() + s.dropFirst()
                }
                return date
            }()
            lines.append("## \(dateLabel)")
            lines.append("")
            for entry in grouped[date]!.sorted(by: { $0.createdAt < $1.createdAt }) {
                if !entry.tags.isEmpty {
                    lines.append("*Tags :* " + entry.tags.map { "#\($0)" }.joined(separator: " "))
                }
                if let mood = entry.mood {
                    lines.append("*Humeur :* \(mood)/5")
                }
                lines.append(entry.content)
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Copie le journal dans le presse-papier en format RTF (collable dans Apple Notes
    /// avec mise en forme) et en texte brut (fallback).
    static func copyToPasteboard(entries: [JournalEntry], title: String = "Journal de bord") {
        let markdownText = markdown(entries: entries, title: title)
        // Construit un NSAttributedString basique avec gras pour les titres
        let attributed = NSMutableAttributedString()
        for line in markdownText.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            let attrs: [NSAttributedString.Key: Any]
            if s.hasPrefix("# ") {
                attrs = [.font: NSFont.boldSystemFont(ofSize: 18)]
                attributed.append(NSAttributedString(string: String(s.dropFirst(2)) + "\n\n", attributes: attrs))
            } else if s.hasPrefix("## ") {
                attrs = [.font: NSFont.boldSystemFont(ofSize: 14)]
                attributed.append(NSAttributedString(string: String(s.dropFirst(3)) + "\n", attributes: attrs))
            } else if s.hasPrefix("*") && s.hasSuffix("*") && s.count > 2 {
                let trimmed = String(s.dropFirst().dropLast())
                attrs = [.font: NSFont.systemFont(ofSize: 11, weight: .light)]
                attributed.append(NSAttributedString(string: trimmed + "\n", attributes: attrs))
            } else {
                attrs = [.font: NSFont.systemFont(ofSize: 12)]
                attributed.append(NSAttributedString(string: s + "\n", attributes: attrs))
            }
        }
        let rtfData = try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let pb = NSPasteboard.general
        pb.clearContents()
        if let rtfData {
            pb.setData(rtfData, forType: .rtf)
        }
        pb.setString(markdownText, forType: .string)
    }
}
