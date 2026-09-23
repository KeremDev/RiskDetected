import Foundation
import UIKit
import PDFKit
import CoreText
struct NovaTrainingSession: Codable {}
func trainingMethodName(_ method: String) -> String { method == "online" ? "Online" : method == "mixed" ? "Karma" : "Yüz yüze" }
@main struct RenderChecks {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]); let output = root.appendingPathComponent("artifacts/education")
        for name in ["Mulish-Regular","Mulish-Bold"] { CTFontManagerRegisterFontsForURL(root.appendingPathComponent("App/Resources/Fonts/\(name).ttf") as CFURL, .process, nil) }
        let data = try Data(contentsOf: output.appendingPathComponent("server-snapshots.json"))
        let snapshots = try JSONDecoder().decode([NovaEducationCertificate.Snapshot].self, from: data)
        for (i,snapshot) in snapshots.enumerated() {
            let data = NovaEducationCertificatePDF.data(snapshot)
            guard let document = PDFDocument(data:data), document.pageCount == 2 else { fatalError("Standard certificate \(i) not two pages: \(PDFDocument(data:data)?.pageCount ?? 0)") }
            let text = document.string ?? ""
            precondition(text.contains("başarıyla tamamlamıştır") && text.contains(snapshot.person.name!) && text.contains("G3-L"))
            precondition(!text.contains("T.C.") && !text.contains("sınav puanı"))
            precondition(!text.contains("İşyeri / görev bağlamı:"))
            try data.write(to: output.appendingPathComponent("certificate-\(i).pdf"))
            if i == 0 { for page in 0..<2 { try document.page(at:page)!.thumbnail(of:CGSize(width:595,height:842),for:.mediaBox).pngData()!.write(to:output.appendingPathComponent("certificate-page-\(page).png")) } }
        }
        var long = try JSONSerialization.jsonObject(with: data) as! [[String:Any]]
        var scope = long[0]["scope"] as! [String:Any]
        var topics = scope["topics"] as! [[String:Any]]
        for i in 0..<30 { var topic = topics.last!; topic["code"] = "G4-LONG-\(i)"; topic["title"] = "Uzun işyeri konusu \(i): " + String(repeating:"Türkçe açıklama, çalışan, öğreti, güvenlik. ", count: 12); topics.append(topic) }
        scope["topics"] = topics; scope["context_note"] = String(repeating:"İşyerine ve göreve özgü ayrıntılı risk dayanağı açıklaması. ",count:160)
        long[0]["scope"] = scope
        for (index,size) in [CGSize(width:40,height:40),CGSize(width:200,height:40),CGSize(width:40,height:200)].enumerated() {
            let png = UIGraphicsImageRenderer(size:size).image { ctx in UIColor.systemTeal.setFill(); ctx.fill(CGRect(origin:.zero,size:size)) }.pngData()!
            var example = try JSONSerialization.jsonObject(with:data) as! [[String:Any]]
            example[0]["logo_png_base64"] = png.base64EncodedString()
            let value = try JSONDecoder().decode(NovaEducationCertificate.Snapshot.self,from:JSONSerialization.data(withJSONObject:example[0]))
            let pdf = NovaEducationCertificatePDF.data(value)
            precondition(PDFDocument(data:pdf)!.pageCount == 2)
            try pdf.write(to:output.appendingPathComponent("certificate-logo-\(index).pdf"))
        }
        let longSnapshot = try JSONDecoder().decode(NovaEducationCertificate.Snapshot.self,from:JSONSerialization.data(withJSONObject:long[0]))
        let longPDF = NovaEducationCertificatePDF.data(longSnapshot); let longDoc = PDFDocument(data:longPDF)!
        precondition(longDoc.pageCount > 2 && longDoc.pageCount % 2 == 0)
        precondition(longDoc.string!.contains("G4-LONG-29"))
        try longPDF.write(to:output.appendingPathComponent("certificate-long.pdf"))
        var midnight = try JSONSerialization.jsonObject(with:data) as! [[String:Any]]
        var midnightScope = midnight[0]["scope"] as! [String:Any]
        var midnightLessons = midnightScope["lessons"] as! [[String:Any]]
        for i in midnightLessons.indices { midnightLessons[i]["starts_at"] = NovaEducationClock.iso(NovaEducationClock.date("2026-09-10T20:00:00Z")!.addingTimeInterval(Double(i)*3600)) }
        midnightScope["lessons"] = midnightLessons; midnight[0]["scope"] = midnightScope
        let midnightSnapshot = try JSONDecoder().decode(NovaEducationCertificate.Snapshot.self,from:JSONSerialization.data(withJSONObject:midnight[0]))
        let midnightText = PDFDocument(data:NovaEducationCertificatePDF.data(midnightSnapshot))!.string!
        precondition(midnightText.contains("10.09.2026 23:00") && midnightText.contains("11.09.2026 00:00"))
        let package = try JSONDecoder().decode(NovaEducationPackage.self,from:Data(contentsOf:root.appendingPathComponent("content/education/tr-isg-2026-v1.json")))
        var topics370 = package.topics(cycle:"initial",hazard:"low"); topics370[0].instruction_minutes += 10
        let lessons = NovaEducationClock.distribute(topics:topics370,days:NovaEducationClock.initialDays(minutes:370,basic:true),basic:true)
        precondition(lessons.count == 8 && lessons.last!.instruction_minutes == 55)
        precondition(lessons.reduce(0) { $0 + $1.instruction_minutes } == 370 && lessons.reduce(0) { $0 + $1.break_minutes } == 120)
        print("PASS: \(snapshots.count) server snapshots decode; normal 2-page PDFs; long \(longDoc.pageCount)-page PDF; Turkish text; 370 minutes = 8 lessons")
    }
}
