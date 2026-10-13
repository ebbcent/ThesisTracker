import Foundation

enum XLSXWriter {
    /// Valeur de cellule : texte (inlineStr) ou nombre (<v>).
    private enum Cell {
        case text(String)
        case number(Int)
    }

    static func workbookData(rows: [ExportRow]) -> Data {
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
          <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        </Types>
        """

        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """

        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="Export" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>
        """

        let workbookRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """

        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <fonts count="1"><font><sz val="11"/><name val="Aptos"/></font></fonts>
          <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
          <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
          <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
          <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
          <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
        </styleSheet>
        """

        let app = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
          <Application>Writing Process</Application>
        </Properties>
        """

        let now = ISO8601DateFormatter().string(from: Date())
        let core = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:creator>Writing Process</dc:creator>
          <cp:lastModifiedBy>Writing Process</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified>
        </cp:coreProperties>
        """

        let headers = ["Date", "Projet", "Chapitre", "Total caractères", "Caractères du jour", "Note", "Deadline"]
        let allRows: [[Cell]] = [headers.map { Cell.text($0) }] + rows.map { row -> [Cell] in
            [
                .text(row.date),
                .text(row.project),
                .text(row.chapter),
                .number(row.total),
                .number(row.increment),
                .text(row.note ?? ""),
                .text(row.deadline ?? "")
            ]
        }

        var sheetRows: [String] = []
        for (rowIndex, row) in allRows.enumerated() {
            let cells = row.enumerated().map { (columnIndex, value) -> String in
                let ref = cellReference(column: columnIndex, row: rowIndex + 1)
                switch value {
                case .text(let text):
                    return "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escapeXML(text))</t></is></c>"
                case .number(let number):
                    // Cellule numérique : Excel peut trier / additionner directement
                    return "<c r=\"\(ref)\"><v>\(number)</v></c>"
                }
            }.joined()
            sheetRows.append("<row r=\"\(rowIndex + 1)\">\(cells)</row>")
        }

        let sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            \(sheetRows.joined())
          </sheetData>
        </worksheet>
        """

        let files: [(String, Data)] = [
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(rels.utf8)),
            ("docProps/app.xml", Data(app.utf8)),
            ("docProps/core.xml", Data(core.utf8)),
            ("xl/workbook.xml", Data(workbook.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(workbookRels.utf8)),
            ("xl/styles.xml", Data(styles.utf8)),
            ("xl/worksheets/sheet1.xml", Data(sheet.utf8))
        ]
        return zipStored(files: files)
    }

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

    private static func cellReference(column: Int, row: Int) -> String {
        var column = column
        var letters = ""
        repeat {
            letters = String(UnicodeScalar(65 + (column % 26))!) + letters
            column = column / 26 - 1
        } while column >= 0
        return "\(letters)\(row)"
    }

    private static func escapeXML(_ value: String) -> String {
        stripInvalidXMLChars(value)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Supprime les caractères interdits en XML 1.0 (contrôles C0 sauf \t \n \r,
    /// U+FFFE, U+FFFF) : sinon Excel refuse d'ouvrir le fichier.
    private static func stripInvalidXMLChars(_ value: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            let v = scalar.value
            let valid = v == 0x9 || v == 0xA || v == 0xD
                || (0x20...0xD7FF).contains(v)
                || (0xE000...0xFFFD).contains(v)
                || (0x10000...0x10FFFF).contains(v)
            if valid { scalars.append(scalar) }
        }
        return String(scalars)
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
