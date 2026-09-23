import Foundation
import UIKit
import CoreText

/// Local, deterministic exports. User-controlled values are text in both
/// formats; XLSX cells are inline strings so they can never become formulas.
enum NovaChecklistExport {
    @MainActor static func pdf(run: NovaChecklistRun) throws -> URL {
        try pdf(title: run.templateTitle ?? run.templateCode,
            subtitle: [run.companyName, run.workplaceName, run.startedOn,
                "Uygun \(run.conform)", "Uygun değil \(run.nonconform)", "Uygulanamaz \(run.notApplicable)",
                run.scorePercent.map { "Uygunluk %\(Int($0.rounded()))" },
                run.applicableCoveragePercent.map { "Kapsam %\(Int($0.rounded()))" }]
                .compactMap { $0 }.joined(separator: " · "),
            version: run.templateVersion,
            rows: run.answers.map { ($0.position, $0.prompt, $0.result?.title ?? "Yanıtsız", $0.note ?? "") },
            identifier: run.id.uuidString)
    }

    @MainActor static func pdf(template: NovaChecklistTemplateDetail) throws -> URL {
        try pdf(title: template.title,
            subtitle: RDLocalization.format("localizable.nova.checklist.export.bos.kontrol.listesi.1.4544ed7e", table: .localizable, fallback: "Boş kontrol listesi · %1$@", arguments: [String(describing: template.catalogTemplateCode ?? template.templateCode)]),
            version: template.version,
            rows: template.items.map { ($0.position, $0.prompt, "", "") },
            identifier: template.templateCode)
    }

    @MainActor private static func pdf(title: String, subtitle: String, version: Int,
                                       rows: [(Int, String, String, String)], identifier: String) throws -> URL {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            var y: CGFloat = 42
            var page = 0
            func pageStart() {
                context.beginPage(); page += 1; y = 42
                draw("İSGADA · \(title)", x: 36, y: 20, size: 8, weight: .semibold, color: .darkGray)
                draw("İSGADA · Kontrol Listesi · v\(version) · Sayfa \(page)", x: 36, y: 812,
                     size: 8, weight: .regular, color: .darkGray)
            }
            func drawParagraph(_ text: String, size: CGFloat = 10, bold: Bool = false) {
                let style = NSMutableParagraphStyle(); style.lineSpacing = 3
                let font = UIFont(name: bold ? "PlusJakartaSans-Bold" : "PlusJakartaSans-Regular", size: size)
                    ?? UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
                let attributed = NSAttributedString(string: text, attributes: [
                    .font: font, .foregroundColor: UIColor.black, .paragraphStyle: style])
                let height = attributed.boundingRect(with: CGSize(width: 523, height: 2_000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height
                if y + height > 785 { pageStart() }
                attributed.draw(with: CGRect(x: 36, y: y, width: 523, height: height + 2),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                y += ceil(height) + 8
            }
            func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat,
                      weight: UIFont.Weight, color: UIColor) {
                (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
                    .font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
            }
            pageStart()
            drawParagraph(title, size: 18, bold: true)
            drawParagraph(subtitle)
            drawParagraph("Bu çıktı bir uzman çalışma kaydıdır; tek başına mevzuata uygunluk kararı değildir.", size: 8)
            for row in rows {
                drawParagraph("\(row.0). \(row.1)", size: 10, bold: true)
                if !row.2.isEmpty { drawParagraph("Yanıt: \(row.2)") }
                if !row.3.isEmpty { drawParagraph("Açıklama: \(row.3)") }
                if row.2.isEmpty { drawParagraph("☐ Uygun    ☐ Uygun Değil    ☐ Gerekli Değil    Açıklama: ____________________") }
                y += 4
            }
            if y > 710 { pageStart() }
            drawParagraph("Uzman / İmza                                      Firma yetkilisi / İmza", bold: true)
        }
        return try write(data, name: "kontrol-listesi-\(safe(identifier)).pdf")
    }

    static func xlsx(run: NovaChecklistRun) throws -> URL {
        try workbook(title: run.templateTitle ?? run.templateCode,
            metadata: [["Firma", run.companyName ?? ""], ["İşyeri", run.workplaceName ?? ""],
                       ["Tarih", run.startedOn], ["Sürüm", String(run.templateVersion)],
                       ["Belge no", run.documentNumber ?? ""], ["Alan", run.areaLabel ?? ""],
                       ["Ekipman", run.equipmentLabel ?? ""],
                       ["Kaynak kayıtları", run.sourceIDs.joined(separator: ", ")],
                       ["İlerleme", run.progressPercent.map { "%\(Int($0.rounded()))" } ?? ""],
                       ["Kontrol kapsamı", run.applicableCoveragePercent.map { "%\(Int($0.rounded()))" } ?? ""],
                       ["Uygunluk puanı", run.scorePercent.map { "%\(Int($0.rounded()))" } ?? ""],
                       ["Uygun", String(run.conform)], ["Uygun değil", String(run.nonconform)],
                       ["Uygulanamaz", String(run.notApplicable)]],
            rows: run.answers.map { [String($0.position), $0.itemCode, $0.sectionTitle ?? "",
                $0.scopeKey ?? "", $0.prompt, $0.verificationMethod ?? "",
                $0.result?.title ?? "Yanıtsız", $0.note ?? "",
                $0.evidenceAssetID?.uuidString.lowercased() ?? "",
                $0.nonconformityID?.uuidString.lowercased() ?? "", "", ""] },
            sources: run.sourceIDs,
            identifier: run.id.uuidString)
    }

    static func xlsx(template: NovaChecklistTemplateDetail) throws -> URL {
        try workbook(title: template.title,
            metadata: [["Katalog kodu", template.catalogTemplateCode ?? template.templateCode],
                       ["Sürüm", String(template.version)], ["Durum", "Boş şablon"],
                       ["Kaynak kayıtları", template.sourceIDs.joined(separator: ", ")]],
            rows: template.items.map { [String($0.position), $0.itemCode, $0.sectionTitle ?? "",
                $0.scopeKey ?? "", $0.prompt, $0.verificationMethod ?? "", "", "", "", "", "", ""] },
            sources: template.sourceIDs,
            identifier: template.templateCode)
    }

    private static func workbook(title: String, metadata: [[String]], rows: [[String]], sources: [String],
                                 identifier: String) throws -> URL {
        let summaryRows = [["Kontrol listesi", title],
            ["Uyarı", "Uzman çalışma aracıdır; tek başına mevzuata uygunluk kararı değildir."]] + metadata
        let itemRows = [["Sıra", "Madde kodu", "Bölüm", "Alan / ekipman kapsamı", "Soru",
            "Doğrulama", "Yanıt", "Açıklama", "Kanıt referansı", "Uygunsuzluk referansı",
            "Sorumlu", "Termin"]] + rows
        let sourceRows = [["Kaynak kimliği", "Not"]] + (sources.isEmpty
            ? [["", "Bu listeye bağlı kaynak kaydı yok."]]
            : sources.sorted().map { [$0, "Katalog sürümünde sabitlenmiş kaynak kaydı"] })
        func xml(_ value: String) -> String {
            value.unicodeScalars.filter { $0.value == 9 || $0.value == 10 || $0.value == 13 || $0.value >= 32 }
                .map(String.init).joined().replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
        func column(_ index: Int) -> String {
            var value = index + 1; var answer = ""
            while value > 0 { value -= 1; answer = String(UnicodeScalar(65 + value % 26)!) + answer; value /= 26 }
            return answer
        }
        func sheet(_ rows: [[String]], widths: [Int], freeze: Bool, filter: Bool) -> String {
            let sheetRows = rows.enumerated().map { rowIndex, cells in
                "<row r=\"\(rowIndex + 1)\">" + cells.enumerated().map { columnIndex, value in
                    "<c r=\"\(column(columnIndex))\(rowIndex + 1)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xml(value))</t></is></c>"
                }.joined() + "</row>"
            }.joined()
            let columns = widths.enumerated().map { "<col min=\"\($0.offset + 1)\" max=\"\($0.offset + 1)\" width=\"\($0.element)\" customWidth=\"1\"/>" }.joined()
            let views = freeze ? "<sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>" : ""
            let filterXML = filter && !rows.isEmpty ? "<autoFilter ref=\"A1:\(column(max((rows.first?.count ?? 1) - 1,0)))\(rows.count)\"/>" : ""
            return "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">\(views)<cols>\(columns)</cols><sheetData>\(sheetRows)</sheetData>\(filterXML)</worksheet>"
        }
        let entries: [(String, String)] = [
            ("[Content_Types].xml", "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/><Override PartName=\"/xl/worksheets/sheet2.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/><Override PartName=\"/xl/worksheets/sheet3.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>"),
            ("_rels/.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"),
            ("xl/workbook.xml", "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Özet\" sheetId=\"1\" r:id=\"rId1\"/><sheet name=\"Maddeler\" sheetId=\"2\" r:id=\"rId2\"/><sheet name=\"Kaynaklar\" sheetId=\"3\" r:id=\"rId3\"/></sheets></workbook>"),
            ("xl/_rels/workbook.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet2.xml\"/><Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet3.xml\"/></Relationships>"),
            ("xl/worksheets/sheet1.xml", sheet(summaryRows, widths: [26,90], freeze: false, filter: false)),
            ("xl/worksheets/sheet2.xml", sheet(itemRows, widths: [8,18,24,24,85,16,18,45,38,38,24,16], freeze: true, filter: true)),
            ("xl/worksheets/sheet3.xml", sheet(sourceRows, widths: [28,80], freeze: true, filter: true))]
        var zip = Data(); var central = Data()
        func u16(_ value: Int) -> Data { var n = UInt16(value).littleEndian; return withUnsafeBytes(of: &n) { Data($0) } }
        func u32(_ value: UInt32) -> Data { var n = value.littleEndian; return withUnsafeBytes(of: &n) { Data($0) } }
        for (name, text) in entries {
            let nameData = Data(name.utf8), bytes = Data(text.utf8), offset = UInt32(zip.count)
            var crc: UInt32 = 0xffffffff
            for byte in bytes { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) } }
            crc ^= 0xffffffff
            for chunk in [u32(0x04034b50),u16(20),u16(0),u16(0),u16(0),u16(33),u32(crc),u32(UInt32(bytes.count)),u32(UInt32(bytes.count)),u16(nameData.count),u16(0),nameData,bytes] { zip.append(chunk) }
            for chunk in [u32(0x02014b50),u16(20),u16(20),u16(0),u16(0),u16(0),u16(33),u32(crc),u32(UInt32(bytes.count)),u32(UInt32(bytes.count)),u16(nameData.count),u16(0),u16(0),u16(0),u16(0),u32(0),u32(offset),nameData] { central.append(chunk) }
        }
        let start = UInt32(zip.count); zip += central
        for chunk in [u32(0x06054b50),u16(0),u16(0),u16(entries.count),u16(entries.count),u32(UInt32(central.count)),u32(start),u16(0)] { zip.append(chunk) }
        return try write(zip, name: "kontrol-listesi-\(safe(identifier)).xlsx")
    }

    private static func safe(_ value: String) -> String {
        String(value.lowercased().map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" }).prefix(80).description
    }
    private static func write(_ data: Data, name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("isgada-checklists")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
