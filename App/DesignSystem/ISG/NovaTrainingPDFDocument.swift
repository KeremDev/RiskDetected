import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Owner-entered record, deliberately not an Ek-2 certificate or signature.
struct NovaTrainingPDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    let data: Data
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
    init(session: NovaTrainingSession) {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            var y: CGFloat = 48
            var page = 0
            func newPage() {
                context.beginPage(); page += 1; y = 48
                UIColor.white.setFill(); context.cgContext.fill(bounds)
                ("NOVA / Eğitim kayıt belgesi" as NSString).draw(at: CGPoint(x: 40, y: 22), withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.darkGray])
                ("Sürüm \(session.version) | Sayfa \(page) | İmzasız kayıt çıktısı" as NSString).draw(at: CGPoint(x: 40, y: 814), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray])
            }
            func paragraph(_ text: String, size: CGFloat = 12, bold: Bool = false) {
                let style = NSMutableParagraphStyle(); style.lineSpacing = 4
                let attrs: [NSAttributedString.Key: Any] = [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black, .paragraphStyle: style]
                let height = ceil((text as NSString).boundingRect(with: CGSize(width: 515, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil).height)
                if y + height > 784 { newPage() }
                (text as NSString).draw(in: CGRect(x: 40, y: y, width: 515, height: height + 2), withAttributes: attrs)
                y += height + 13
            }
            for company in session.companies {
                for person in company.participants {
                    newPage()
                    paragraph("EĞİTİM KAYIT BELGESİ", size: 21, bold: true)
                    paragraph(session.title, size: 17, bold: true)
                    paragraph("Katılımcı: \(person.name)")
                    paragraph("Firma: \(company.company_name)")
                    paragraph("Eğitmen: \(session.trainer)")
                    paragraph("Eğitim tarihi: \(session.held_on) | Yöntem: \(trainingMethodName(session.method))")
                    paragraph("Kayıtlı süre: \(company.duration_minutes) dakika | Sonraki eğitim: \(company.valid_until ?? "Tanımlanmadı")")
                    paragraph("Yer / bağlantı: \(session.location.isEmpty ? "Belirtilmedi" : session.location)")
                    paragraph("Kayıt durumu: \(company.state == "completed" ? "Gerçekleşmiş eğitim beyanı" : company.state == "planned" ? "Eski plan - gerçekleşme doğrulanmadı" : "İptal")")
                    if !session.notes.isEmpty { paragraph("Notlar: \(session.notes)", size: 10) }
                    paragraph("Bu çıktı kullanıcı tarafından girilen eğitim kaydını gösterir. Katılım imzası, sınav/değerlendirme sonucu veya mevzuata uygunluk doğrulaması değildir. Ek-2 temel eğitim belgesi yerine geçmez.", size: 10)
                    paragraph("Kayıt no: \(session.id.uuidString) / \(company.id.uuidString)", size: 8)
                }
            }
            if page == 0 { newPage(); paragraph("Bu kayıtta katılımcı bulunmuyor.") }
        }
    }
}
