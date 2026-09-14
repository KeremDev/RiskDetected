import Foundation
import UIKit

struct NovaPPEFormSnapshot: Decodable {
    let id: UUID
    let company: String?
    let employee: String?
    let item: String
    let date: String
    let version: Int
    var legacy: Bool?
}

@MainActor enum NovaPPEFormPDF {
    static func write(_ form: NovaPPEFormSnapshot, owner: UUID) throws -> URL {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            var y: CGFloat = 64
            var pageNumber = 0
            func start() {
                context.beginPage(); pageNumber += 1; y = 64
                let footer = "İSGADA · \(form.id.uuidString) · v\(form.version) · \(pageNumber)"
                (footer as NSString).draw(at: CGPoint(x: 36, y: 812), withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.darkGray])
            }
            func line(_ text: String, size: CGFloat = 12, bold: Bool = false) {
                let font = UIFont(name: bold ? "PlusJakartaSans-Bold" : "PlusJakartaSans-Regular", size: size) ?? UIFont.systemFont(ofSize: size)
                let style = NSMutableParagraphStyle(); style.lineSpacing = 5
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: style]
                // Word-level wrapping also permits long company/person names to continue safely.
                for paragraph in text.components(separatedBy: "\n") {
                    var buffer = ""
                    for word in paragraph.components(separatedBy: " ") {
                        let next = buffer.isEmpty ? word : buffer + " " + word
                        if (next as NSString).size(withAttributes: attrs).width > 515 && !buffer.isEmpty {
                            if y + size + 8 > 770 { start() }
                            (buffer as NSString).draw(in: CGRect(x: 40, y: y, width: 515, height: size + 10), withAttributes: attrs)
                            y += size + 8; buffer = word
                        } else { buffer = next }
                    }
                    if y + size + 8 > 770 { start() }
                    (buffer as NSString).draw(in: CGRect(x: 40, y: y, width: 515, height: size + 10), withAttributes: attrs)
                    y += size + 18
                }
            }
            start()
            line("KKD ZİMMET FORMU", size: 22, bold: true)
            y += 14
            line("Firma: \(form.company ?? "Belirtilmemiş")")
            line("Personel: \(form.employee ?? "Belirtilmemiş")")
            line("Teslim tarihi: \(form.date)")
            y += 12
            line("ZİMMET VERİLEN KİŞİSEL KORUYUCU DONANIM", size: 12, bold: true)
            line(form.item)
            y += 20
            line("Yukarıda belirtilen kişisel koruyucu donanımın teslimine ilişkin zimmet kaydıdır.")
            if y > 620 { start() }
            y += 30
            line("Teslim eden                                      Teslim alan", bold: true)
            line("Adı soyadı / İmza                              Adı soyadı / İmza", size: 10)
            y += 75
            line("İmza alanları taraflarca doldurulur.", size: 9)
            if form.legacy == true { line("Eski kayıt: firma ve personel bilgileri ilk form hazırlama tarihinde alınmıştır.", size: 9) }
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ppe-\(owner.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("KKD-\(form.id.uuidString)-v\(form.version).pdf")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
