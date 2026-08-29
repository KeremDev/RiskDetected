import Foundation
import PDFKit
import UIKit

final class AnalysisResultHubPDFService {
    static let shared = AnalysisResultHubPDFService()

    func generate(
        section: AnalysisResultSectionID,
        items: [AnalysisResultHubItem],
        analysisTitle: String,
        method: RiskMethod,
        language: RDLanguage,
        company: Company? = nil
    ) throws -> URL {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 42
        let contentWidth = page.width - (margin * 2)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let isTR = language == .turkish
        let title = section.title(language: language)
        let disclaimer = section == .approvedNotebook
            ? (isTR
                ? "Onaylı Defter önerisi/taslağıdır. İş güvenliği uzmanı değerlendirmesi, imzası ve resmî deftere aktarımı gerekir."
                : "Safety Log recommendation. Expert review and transfer to the applicable official record are required.")
            : section == .expertRecommendations
            ? (isTR
                ? "Bağlayıcı uzman görüşü değildir. Saha teyidi ve uzman değerlendirmesi gerekir."
                : "This is not a binding expert opinion. Field verification and expert review are required.")
            : nil

        var pageNumber = 0
        var y = margin
        let bodyFont = RDTypography.uiFont(size: 10.5)
        let titleFont = RDTypography.uiFont(size: 22, weight: .bold)
        let itemTitleFont = RDTypography.uiFont(size: 13.5, weight: .bold)
        let labelFont = RDTypography.uiFont(size: 9, weight: .bold)
        let ink = UIColor(red: 0.07, green: 0.10, blue: 0.09, alpha: 1)
        let green = UIColor(red: 0.02, green: 0.43, blue: 0.17, alpha: 1)
        let slate = UIColor(red: 0.35, green: 0.40, blue: 0.39, alpha: 1)
        let line = UIColor(red: 0.84, green: 0.88, blue: 0.86, alpha: 1)

        func drawText(
            _ text: String,
            font: UIFont,
            color: UIColor,
            rect: CGRect,
            lineSpacing: CGFloat = 2
        ) -> CGFloat {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = lineSpacing
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let measured = attributed.boundingRect(
                with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).integral
            attributed.draw(with: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: measured.height), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            return measured.height
        }

        func drawFooter() {
            let footer = "RiskDetected  |  \(pageNumber)"
            _ = drawText(footer, font: RDTypography.uiFont(size: 8.5), color: slate, rect: CGRect(x: margin, y: page.height - 29, width: contentWidth, height: 15))
        }

        func beginPage(_ context: UIGraphicsPDFRendererContext) {
            if pageNumber > 0 { drawFooter() }
            context.beginPage()
            pageNumber += 1
            y = margin
            let logoRect = CGRect(x: margin, y: y, width: 28, height: 28)
            green.setFill()
            UIBezierPath(roundedRect: logoRect, cornerRadius: 8).fill()
            let mark = "R"
            let markAttributes: [NSAttributedString.Key: Any] = [
                .font: RDTypography.uiFont(size: 15, weight: .heavy),
                .foregroundColor: UIColor.white
            ]
            mark.draw(at: CGPoint(x: logoRect.minX + 8, y: logoRect.minY + 5), withAttributes: markAttributes)
            _ = drawText("RISKDETECTED", font: RDTypography.uiFont(size: 10.5, weight: .bold), color: green, rect: CGRect(x: margin + 38, y: y + 7, width: 180, height: 20))
            y += 43
        }

        let data = renderer.pdfData { context in
            beginPage(context)
            y += drawText(title, font: titleFont, color: ink, rect: CGRect(x: margin, y: y, width: contentWidth, height: 80)) + 4
            y += drawText(analysisTitle, font: RDTypography.uiFont(size: 11.5, weight: .medium), color: slate, rect: CGRect(x: margin, y: y, width: contentWidth, height: 60)) + 14
            if let company {
                y += drawText(
                    company.name,
                    font: RDTypography.uiFont(size: 11.5, weight: .semibold),
                    color: ink,
                    rect: CGRect(x: margin, y: y, width: contentWidth, height: 40)
                ) + 2
                let companyInfo = company.reportInfoText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !companyInfo.isEmpty {
                    y += drawText(
                        companyInfo,
                        font: RDTypography.uiFont(size: 9.5, weight: .regular),
                        color: slate,
                        rect: CGRect(x: margin, y: y, width: contentWidth, height: 60)
                    ) + 10
                } else {
                    y += 8
                }
            }
            if let disclaimer {
                let height = measuredTextHeight(
                    disclaimer,
                    font: RDTypography.uiFont(size: 9.5, weight: .medium),
                    width: contentWidth - 24
                )
                UIColor(red: 0.92, green: 0.98, blue: 0.94, alpha: 1).setFill()
                UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: contentWidth, height: height + 18), cornerRadius: 8).fill()
                _ = drawText(disclaimer, font: RDTypography.uiFont(size: 9.5, weight: .medium), color: green, rect: CGRect(x: margin + 12, y: y + 9, width: contentWidth - 24, height: height))
                y += height + 30
            }

            for (index, item) in items.enumerated() {
                let blocks = contentBlocks(for: item, section: section, method: method, language: language)
                let itemTitle = item.displayTitle(language: language)
                let titleHeight = measuredTextHeight(itemTitle, font: itemTitleFont, width: contentWidth - 28)
                let bodyHeight = blocks.reduce(CGFloat.zero) { partial, block in
                    partial + 17 + measuredTextHeight(block.value, font: bodyFont, width: contentWidth - 28) + 7
                }
                let cardHeight = max(78, 44 + titleHeight + bodyHeight)
                if y + cardHeight > page.height - 52 {
                    beginPage(context)
                }

                UIColor.white.setFill()
                line.setStroke()
                let cardRect = CGRect(x: margin, y: y, width: contentWidth, height: cardHeight)
                let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 10)
                path.fill()
                path.lineWidth = 0.8
                path.stroke()

                _ = drawText("\(index + 1)", font: RDTypography.uiFont(size: 10, weight: .bold), color: green, rect: CGRect(x: margin + 14, y: y + 14, width: 24, height: 18))
                var cardY = y + 13
                cardY += drawText(itemTitle, font: itemTitleFont, color: ink, rect: CGRect(x: margin + 42, y: cardY, width: contentWidth - 56, height: titleHeight)) + 11
                for block in blocks {
                    _ = drawText(block.label.uppercased(with: language.locale), font: labelFont, color: green, rect: CGRect(x: margin + 14, y: cardY, width: contentWidth - 28, height: 15))
                    cardY += 16
                    cardY += drawText(block.value, font: bodyFont, color: block.color == "slate" ? slate : ink, rect: CGRect(x: margin + 14, y: cardY, width: contentWidth - 28, height: 200)) + 8
                }
                y += cardHeight + 12
            }
            drawFooter()
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RiskDetected-Reports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let prefix = section == .riskAnalysis ? "RA" : section == .expertRecommendations ? "UG" : "OD"
        let url = folder.appendingPathComponent("\(prefix)-\(analysisTitle.safeFileComponent)-\(UUID().uuidString.prefix(8)).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    #if DEBUG
    static func runResultHubVisualSelfTest() throws -> [URL] {
        let json = """
        [
          {
            "id": "00000000-0000-0000-0000-000000000101",
            "title": "Açık Kenarda Düşme Tehlikesi",
            "description": "Çalışma platformunun erişilebilir açık kenarında düşmeyi önleyen yeterli koruluk sistemi görünmemektedir.",
            "recommended_action": "Öncelikle uygun kenar koruma sistemi kurulmalı; çalışma, koruma doğrulanana kadar kontrollü alana alınmalıdır.",
            "fk_score": 1440,
            "fk_band": "critical",
            "is_scored": true
          },
          {
            "id": "00000000-0000-0000-0000-000000000102",
            "title": "İskele Kurulum Güvencesinin Doğrulanması",
            "description": "İskelenin kurulum, ankraj ve taşıma uygunluğu yetkili saha kontrolüyle doğrulanmalıdır.",
            "recommended_action": "Kurulum planı ve saha uygunluğu kontrol edilerek sonuç kayıt altına alınmalıdır.",
            "recommended_measures": [
              {
                "kind": "corrective",
                "title": "Düzeltici Önlem",
                "text": "İskele kullanımını durdurun; kurulum ve ankraj uygunluğunu yetkili kişiyle doğrulayın."
              },
              {
                "kind": "preventive",
                "title": "Önleyici Faaliyet",
                "text": "İskele kabul ve periyodik kontrol kayıtlarını saha kontrol planına bağlayın."
              }
            ],
            "root_cause_text": "Kurulum kabul sürecinin saha başlangıç kontrolüne bağlanmamış olması.",
            "references_text": "Yapı İşlerinde İş Sağlığı ve Güvenliği Yönetmeliği; İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği.",
            "needs_field_verification": true,
            "is_scored": false
          },
          {
            "id": "00000000-0000-0000-0000-000000000103",
            "title": "Açık Kenar Koruması",
            "finding_text": "Erişilebilir çalışma platformunda açık kenar boyunca yeterli düşmeye karşı koruma görülmemiştir.",
            "recommendation_text": "Uygun üst ve ara korkuluk ile topuk levhasından oluşan kenar koruma sistemi kurulmalı, uygunluğu saha kontrolüyle doğrulanmalıdır.",
            "reference_text": "Doğrulanmış iş ekipmanı ve yüksekte çalışma güvenliği kuralları.",
            "source_finding_ids": ["00000000-0000-0000-0000-000000000101"],
            "is_scored": false
          }
        ]
        """
        let items = try JSONDecoder().decode([AnalysisResultHubItem].self, from: Data(json.utf8))
        let service = AnalysisResultHubPDFService.shared
        let urls = [
            try service.generate(
                section: .riskAnalysis,
                items: [items[0]],
                analysisTitle: "Şantiye Pilot Analizi",
                method: .fineKinney,
                language: .turkish
            ),
            try service.generate(
                section: .expertRecommendations,
                items: [items[1]],
                analysisTitle: "Şantiye Pilot Analizi",
                method: .fineKinney,
                language: .turkish
            ),
            try service.generate(
                section: .approvedNotebook,
                items: [items[2]],
                analysisTitle: "Şantiye Pilot Analizi",
                method: .fineKinney,
                language: .turkish
            ),
            try service.generate(
                section: .approvedNotebook,
                items: [items[2]],
                analysisTitle: "Construction Pilot Analysis",
                method: .fineKinney,
                language: .english
            )
        ]
        guard
            let englishText = PDFDocument(url: urls[3])?.string,
            englishText.contains("Safety Log Recommendation"),
            !englishText.contains("Onaylı Defter Önerisi")
        else {
            throw NSError(
                domain: "AnalysisResultHubPDFService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "English Safety Log terminology check failed"]
            )
        }
        guard let expertText = PDFDocument(url: urls[1])?.string else {
            throw NSError(
                domain: "AnalysisResultHubPDFService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Expert report text extraction failed"]
            )
        }
        let requiredExpertSections = [
            "DÜZELTİCİ ÖNLEM",
            "ÖNLEYİCİ FAALİYET",
            "KÖK NEDEN",
            "MEVZUAT",
        ]
        guard requiredExpertSections.allSatisfy(expertText.contains) else {
            throw NSError(
                domain: "AnalysisResultHubPDFService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Expert report detail sections are incomplete"]
            )
        }
        return urls
    }
    #endif

    private func contentBlocks(
        for item: AnalysisResultHubItem,
        section: AnalysisResultSectionID,
        method: RiskMethod,
        language: RDLanguage
    ) -> [(label: String, value: String, color: String)] {
        let isTR = language == .turkish
        if section == .approvedNotebook {
            var rows = [
                (isTR ? "Tespit" : "Finding", item.findingText ?? "", "ink"),
                (isTR ? "Öneri" : "Recommendation", item.recommendationText ?? "", "slate")
            ]
            if let reference = item.referenceText, !reference.isEmpty {
                rows.append((isTR ? "Dayanak" : "Basis", reference, "slate"))
            }
            return rows.filter { !$0.1.isEmpty }
        }
        var rows: [(label: String, value: String, color: String)] = []
        let clean: (String?) -> String? = { value in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty
            else { return nil }
            return trimmed
        }
        let joinedMeasures: (FindingMeasure.Kind) -> String? = { kind in
            let values = item.recommendedMeasures?
                .filter { $0.kind == kind }
                .compactMap { clean($0.text) }
                ?? []
            var seen = Set<String>()
            let uniqueValues = values.filter { seen.insert($0).inserted }
            let joined = uniqueValues.joined(separator: "\n\n")
            return joined.isEmpty ? nil : joined
        }

        if let description = clean(item.description) {
            rows.append((isTR ? "Açıklama" : "Description", description, "ink"))
        }

        let corrective = joinedMeasures(.corrective)
        if let recommendation = clean(item.recommendedAction),
           recommendation != corrective {
            rows.append((isTR ? "Uzman Önerisi" : "Expert Recommendation", recommendation, "slate"))
        }
        if let corrective = corrective ?? clean(item.recommendedAction) {
            rows.append((isTR ? "Düzeltici Önlem" : "Corrective Action", corrective, "ink"))
        }
        if let preventive = joinedMeasures(.preventive) {
            rows.append((isTR ? "Önleyici Faaliyet" : "Preventive Action", preventive, "slate"))
        }
        if let otherMeasures = joinedMeasures(.unknown) {
            rows.append((isTR ? "Diğer Kontrol Tedbirleri" : "Other Control Measures", otherMeasures, "slate"))
        }
        if let rootCause = clean(item.rootCauseText) {
            rows.append((isTR ? "Kök Neden" : "Root Cause", rootCause, "ink"))
        }
        if let references = clean(item.referencesText) ?? clean(item.referenceText) {
            rows.append((isTR ? "Mevzuat" : "Regulatory References", references, "slate"))
        }

        if section == .riskAnalysis {
            let score = method == .fineKinney ? item.fkScore : item.m5Score.map(Double.init)
            let band = method == .fineKinney ? item.fkBand : item.m5Band
            let bandText = localizedRiskBand(band, language: language)
            let scoreValue = score.map { localizedScore($0, language: language) } ?? "-"
            rows.append((isTR ? "Risk" : "Risk", "\(bandText) - \(scoreValue)", "ink"))
        } else {
            rows.append((isTR ? "Durum" : "Status", isTR ? "Saha teyidi gerekir" : "Field verification required", "slate"))
        }
        return rows.filter { !$0.1.isEmpty }
    }

    private func localizedRiskBand(_ rawValue: String?, language: RDLanguage) -> String {
        let isTR = language == .turkish
        switch rawValue?.lowercased() {
        case "critical": return isTR ? "Kritik risk" : "Critical risk"
        case "high": return isTR ? "Yüksek risk" : "High risk"
        case "medium": return isTR ? "Orta risk" : "Medium risk"
        case "low": return isTR ? "Düşük risk" : "Low risk"
        default: return isTR ? "Değerlendirilmedi" : "Unassessed"
        }
    }

    private func localizedScore(_ value: Double, language: RDLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func measuredTextHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        return NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph])
            .boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            .integral.height
    }
}

private extension String {
    var safeFileComponent: String {
        let clean = folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(clean.prefix(60)).isEmpty ? "report" : String(clean.prefix(60))
    }
}
