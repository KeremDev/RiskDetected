import Foundation
import UIKit

enum PDFReportKind: String, CaseIterable, Identifiable {
    case standard
    case riskAnalysis

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standart PDF"
        case .riskAnalysis: return "Detaylı risk analizi"
        }
    }

    var subtitle: String {
        switch self {
        case .standard:
            return "RiskDetected şablonu ile hızlı saha raporu."
        case .riskAnalysis:
            return "Fine-Kinney veya 5×5 metoduna göre denetim çıktısı."
        }
    }

    var headerTitle: String {
        switch self {
        case .standard: return "SAHA TARAMA RAPORU"
        case .riskAnalysis: return "İŞ GÜVENLİĞİ RİSK ANALİZİ"
        }
    }

    var detailTitle: String {
        switch self {
        case .standard: return "BULGU DETAYLARI"
        case .riskAnalysis: return "RİSK ANALİZİ TABLOSU"
        }
    }
}

struct PDFReportOptions: Equatable {
    var kind: PDFReportKind = .standard
    var method: RiskMethod = .fineKinney
    var preparedBy: String = ""
    var preparedTitle: String = ""
    var certificateNumber: String = ""
    var companyName: String = ""
    var companyInfo: String = ""

    static func standard(method: RiskMethod) -> PDFReportOptions {
        PDFReportOptions(kind: .standard, method: method)
    }
}

final class PDFReportService: @unchecked Sendable {
    static let shared = PDFReportService()

    private init() {}

    struct ReportInput {
        let bundle: AnalysisResultBundle
        let findings: [Finding]
        let profile: UserProfile?
        let image: UIImage?
        let companyLogo: UIImage?
        let options: PDFReportOptions
    }

    func generateAsync(input: ReportInput) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    let url = try autoreleasepool {
                        try generate(input: input)
                    }
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func generate(input: ReportInput) throws -> URL {
        if ReportFailureSimulation.isEnabled(.pdfRender) {
            throw ReportFailureSimulation.simulatedError(.pdfRender)
        }

        let fileURL = outputURL(for: input.bundle.analysis)
        let pageRect = CGRect(x: 0, y: 0, width: 842, height: 595) // A4 landscape @ 72 dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        try renderer.writePDF(to: fileURL) { context in
            switch input.options.kind {
            case .standard:
                drawCoverPage(input: input, context: context, pageRect: pageRect)
                drawFindingPages(input: input, context: context, pageRect: pageRect)
            case .riskAnalysis:
                drawRiskMethodReferencePage(input: input, context: context, pageRect: pageRect)
                drawRiskAnalysisTablePages(input: input, context: context, pageRect: pageRect)
            }
        }

        return fileURL
    }

    private func outputURL(for analysis: AnalysisRow) -> URL {
        let safeTitle = analysis.title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "·", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        let shortID = String(analysis.id.uuidString.prefix(8)).uppercased()
        let fileName = "RiskDetected_\(safeTitle)_\(shortID).pdf"
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    private func drawCoverPage(input: ReportInput, context: UIGraphicsPDFRendererContext, pageRect: CGRect) {
        context.beginPage()
        drawPageChrome(input: input, pageRect: pageRect, title: input.options.kind.headerTitle, page: 1)

        let margin: CGFloat = 42
        let contentTop: CGFloat = 92
        let analysis = input.bundle.analysis
        let profile = input.profile

        drawText(
            analysis.title,
            in: CGRect(x: margin, y: contentTop, width: 440, height: 36),
            font: .systemFont(ofSize: 24, weight: .bold),
            color: .rdPDFBlack
        )

        drawText(
            "\(formattedDate(analysis.createdAt)) · \(canvasLabel(analysis.canvas)) · \(input.findings.count) bulgu",
            in: CGRect(x: margin, y: contentTop + 38, width: 480, height: 22),
            font: .systemFont(ofSize: 12, weight: .medium),
            color: .rdPDFSlate
        )

        drawSummaryCards(input: input, origin: CGPoint(x: margin, y: contentTop + 88))

        if let image = input.image {
            drawImage(image, in: CGRect(x: 548, y: contentTop, width: 252, height: 178), cornerRadius: 14)
        } else if analysis.kind == "text" {
            drawPlaceholder(in: CGRect(x: 548, y: contentTop, width: 252, height: 178), text: "Metin Analizi")
        } else {
            drawPlaceholder(in: CGRect(x: 548, y: contentTop, width: 252, height: 178), text: "Fotoğraf")
        }

        let summary = analysis.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        drawInfoBox(
            title: "AI ÖZETİ",
            body: summary?.isEmpty == false ? summary! : "\(input.findings.count) bulgu tespit edildi. Bulgular \(input.options.method.label) metoduna göre önceliklendirilmiştir.",
            rect: CGRect(x: margin, y: 340, width: 758, height: 86)
        )

        let expert = input.options.preparedBy.nonEmpty ?? profile?.displayName ?? "Kullanıcı"
        let title = input.options.preparedTitle.nonEmpty ?? profile?.title
        let certificate = input.options.certificateNumber.nonEmpty ?? profile?.certificateNumber
        let companyName = input.options.companyName.nonEmpty ?? profile?.companyName
        let companyInfo = input.options.companyInfo.nonEmpty ?? profile?.phone
        let credential = [
            title,
            certificate.map { "Belge no: \($0)" }
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
            .joined(separator: " · ")
        let companyParts = [
            companyName.map { "Firma: \($0)" },
            companyInfo
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
            .joined(separator: " · ")
        let footerParts = [
            "Hazırlayan: \(expert)",
            credential.nonEmpty ?? "İSG Uzmanı",
            companyParts.nonEmpty,
            "Doküman No: #\(String(analysis.id.uuidString.prefix(8)).uppercased())"
        ].compactMap { $0 }
        let footer = footerParts.joined(separator: " · ")
        drawText(
            footer,
            in: CGRect(x: margin, y: 448, width: 758, height: 22),
            font: .monospacedSystemFont(ofSize: 10, weight: .medium),
            color: .rdPDFSlate
        )

        drawMethodLegend(input: input, rect: CGRect(x: margin, y: 482, width: 758, height: 54))
    }

    private func drawFindingPages(input: ReportInput, context: UIGraphicsPDFRendererContext, pageRect: CGRect) {
        let rowsPerPage = 5
        let chunks = input.findings.chunked(into: rowsPerPage)
        guard !chunks.isEmpty else { return }

        for (pageIndex, findings) in chunks.enumerated() {
            context.beginPage()
            drawPageChrome(input: input, pageRect: pageRect, title: input.options.kind.detailTitle, page: pageIndex + 2)
            drawTableHeader(y: 92)

            var y: CGFloat = 122
            for (idx, finding) in findings.enumerated() {
                let ordinal = pageIndex * rowsPerPage + idx + 1
                drawFindingRow(ordinal: ordinal, finding: finding, method: input.options.method, y: y)
                y += 86
            }
        }
    }

    private func drawRiskMethodReferencePage(input: ReportInput, context: UIGraphicsPDFRendererContext, pageRect: CGRect) {
        context.beginPage()
        drawRiskAnalysisChrome(input: input, pageRect: pageRect, title: input.options.method == .fineKinney ? "FINE-KINNEY METODU REFERANS TABLOSU" : "5x5 L-TİPİ MATRİS REFERANS TABLOSU", page: 1)

        let margin: CGFloat = 32
        if input.options.method == .fineKinney {
            drawFineKinneyReference(origin: CGPoint(x: margin, y: 82))
        } else {
            drawMatrix5Reference(origin: CGPoint(x: margin, y: 82))
        }

        drawRiskAnalysisInfoStrip(input: input, rect: CGRect(x: margin, y: 520, width: pageRect.width - margin * 2, height: 42))
    }

    private func drawRiskAnalysisTablePages(input: ReportInput, context: UIGraphicsPDFRendererContext, pageRect: CGRect) {
        let rowsPerPage = input.options.method == .fineKinney ? 4 : 4
        let chunks = input.findings.chunked(into: rowsPerPage)
        guard !chunks.isEmpty else { return }

        for (pageIndex, findings) in chunks.enumerated() {
            context.beginPage()
            drawRiskAnalysisChrome(input: input, pageRect: pageRect, title: input.options.method == .fineKinney ? "TEHLİKE VE RİSK DEĞERLENDİRME FORMU (FINE-KINNEY)" : "TEHLİKE VE RİSK DEĞERLENDİRME FORMU (5x5 L-TİPİ)", page: pageIndex + 2)

            if input.options.method == .fineKinney {
                drawFineKinneyAssessmentTable(input: input, findings: findings, pageIndex: pageIndex, rowsPerPage: rowsPerPage)
            } else {
                drawMatrixAssessmentTable(input: input, findings: findings, pageIndex: pageIndex, rowsPerPage: rowsPerPage)
            }
        }
    }

    private func drawPageChrome(input: ReportInput, pageRect: CGRect, title: String, page: Int) {
        UIColor.rdPDFPaper.setFill()
        UIBezierPath(rect: pageRect).fill()

        if let logo = UIImage(named: "RDLogo") {
            drawImage(logo, in: CGRect(x: 42, y: 26, width: 120, height: 34), cornerRadius: 0, mode: .scaleAspectFit)
        } else {
            drawText("RiskDetected", in: CGRect(x: 42, y: 26, width: 140, height: 28), font: .systemFont(ofSize: 20, weight: .bold), color: .rdPDFBlack)
        }

        if let companyLogo = input.companyLogo {
            drawImage(companyLogo, in: CGRect(x: 172, y: 26, width: 54, height: 34), cornerRadius: 6, mode: .scaleAspectFit)
        } else if let companyName = input.options.companyName.nonEmpty {
            drawText(companyName, in: CGRect(x: 172, y: 32, width: 110, height: 18), font: .systemFont(ofSize: 10, weight: .semibold), color: .rdPDFSlate)
        }

        drawText(
            title,
            in: CGRect(x: 220, y: 31, width: 360, height: 22),
            font: .systemFont(ofSize: 13, weight: .bold),
            color: .rdPDFSlate,
            alignment: .center
        )

        drawText(
            "Sayfa \(page)",
            in: CGRect(x: pageRect.width - 118, y: 31, width: 76, height: 18),
            font: .monospacedSystemFont(ofSize: 10, weight: .medium),
            color: .rdPDFSlate,
            alignment: .right
        )

        UIColor.rdPDFBlack.setFill()
        UIBezierPath(rect: CGRect(x: 42, y: 70, width: pageRect.width - 84, height: 2)).fill()
    }

    private func drawRiskAnalysisChrome(input: ReportInput, pageRect: CGRect, title: String, page: Int) {
        UIColor.white.setFill()
        UIBezierPath(rect: pageRect).fill()

        let margin: CGFloat = 32
        roundedStroke(CGRect(x: margin, y: 24, width: pageRect.width - margin * 2, height: 42), radius: 0, stroke: .rdPDFBlack, fill: .white, lineWidth: 1.4)
        drawText(title, in: CGRect(x: margin + 12, y: 36, width: pageRect.width - margin * 2 - 24, height: 16), font: .systemFont(ofSize: 13, weight: .bold), color: .rdPDFBlack, alignment: .center)

        if let logo = UIImage(named: "RDLogo") {
            drawImage(logo, in: CGRect(x: margin + 8, y: 29, width: 104, height: 28), cornerRadius: 0, mode: .scaleAspectFit)
        }
        if let companyLogo = input.companyLogo {
            drawImage(companyLogo, in: CGRect(x: pageRect.width - margin - 86, y: 29, width: 50, height: 28), cornerRadius: 4, mode: .scaleAspectFit)
        }
        drawText("Sayfa \(page)", in: CGRect(x: pageRect.width - margin - 34, y: 38, width: 30, height: 12), font: .monospacedSystemFont(ofSize: 8, weight: .medium), color: .rdPDFSlate, alignment: .right)
    }

    private func drawSummaryCards(input: ReportInput, origin: CGPoint) {
        let levels: [RiskLevel] = [.critical, .high, .medium, .low]
        let width: CGFloat = 110
        let gap: CGFloat = 10

        for (index, level) in levels.enumerated() {
            let count = input.findings.filter { $0.band(for: input.options.method).level == level }.count
            let rect = CGRect(x: origin.x + CGFloat(index) * (width + gap), y: origin.y, width: width, height: 72)
            roundedFill(rect, radius: 12, color: level.pdfBackground)
            drawText("\(count)", in: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: 60, height: 26), font: .monospacedSystemFont(ofSize: 24, weight: .bold), color: level.pdfColor)
            drawText(level.label.uppercased(), in: CGRect(x: rect.minX + 12, y: rect.minY + 42, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 10, weight: .bold), color: level.pdfColor)
        }
    }

    private func drawFineKinneyReference(origin: CGPoint) {
        let tableWidth: CGFloat = 246
        let gap: CGFloat = 18
        drawReferenceTable(
            title: "OLASILIK (O)",
            columns: ["Değer", "Zararın gerçekleşme olasılığı"],
            rows: [
                ["10", "Beklenir, kesin"],
                ["6", "Yüksek, oldukça mümkün"],
                ["3", "Olası"],
                ["1", "Mümkün fakat düşük"],
                ["0.5", "Beklenmez fakat mümkün"],
                ["0.2", "Beklenmez"],
            ],
            rect: CGRect(x: origin.x, y: origin.y, width: tableWidth, height: 212)
        )
        drawReferenceTable(
            title: "FREKANS (F)",
            columns: ["Değer", "Tehlikeye maruz kalma tekrarı"],
            rows: [
                ["10", "Hemen hemen sürekli / saatte birkaç defa"],
                ["6", "Sık / günde bir veya birkaç defa"],
                ["3", "Ara sıra / haftada birkaç defa"],
                ["2", "Sık değil / ayda birkaç defa"],
                ["1", "Seyrek / yılda birkaç defa"],
                ["0.5", "Çok seyrek / yılda bir veya daha az"],
            ],
            rect: CGRect(x: origin.x + tableWidth + gap, y: origin.y, width: tableWidth, height: 212)
        )
        drawReferenceTable(
            title: "ŞİDDET (Ş)",
            columns: ["Değer", "İnsan/çevre üzerinde tahmini zarar"],
            rows: [
                ["100", "Birden fazla ölümlü kaza / çevresel felaket"],
                ["40", "Ölümlü kaza / ciddi çevresel zarar"],
                ["15", "Kalıcı hasar veya iş kaybı"],
                ["7", "Önemli yaralanma / dış ilk yardım"],
                ["3", "Küçük yaralanma / iç ilk yardım"],
                ["1", "Ucuz atlatma / çevresel zarar yok"],
            ],
            rect: CGRect(x: origin.x + (tableWidth + gap) * 2, y: origin.y, width: tableWidth, height: 212)
        )

        drawReferenceTable(
            title: "RİSK DEĞERİ (R = O x F x Ş)",
            columns: ["Risk değeri", "Risk adı", "Eylem", "Termin"],
            rows: [
                ["1801 ≤ R", "Tolerans gösterilemez", "İş derhal durdurulur; tesis/çevre kapatılması düşünülebilir.", "Hemen / 1 hafta"],
                ["401 ≤ R < 1801", "En kısa sürede giderilecek", "Risk kabul edilebilir seviyeye düşene kadar faaliyet kısıtlanır.", "1 aydan kısa"],
                ["201 ≤ R < 401", "Esaslı risk", "Acil önlem alınır ve faaliyet izlenir.", "1-3 ay"],
                ["71 ≤ R < 201", "Önemli risk", "Düzeltici faaliyet planı başlatılır.", "6 ay"],
                ["21 ≤ R < 71", "Olası risk", "Kontroller sürdürülür ve izlenir.", "1 yıl"],
                ["R < 21", "Önemsiz risk", "İlave kontrole gerek olmayabilir.", "Kontrol"],
            ],
            rect: CGRect(x: origin.x, y: origin.y + 244, width: 774, height: 178),
            rowColors: [.rdPDFCritical, .rdPDFCritical, .rdPDFHigh, .rdPDFMedium, .rdPDFLow, .rdPDFGreen]
        )
    }

    private func drawMatrix5Reference(origin: CGPoint) {
        drawReferenceTable(
            title: "OLASILIK (O)",
            columns: ["Derece", "Tanım"],
            rows: [
                ["1", "Gerçekleşme ihtimali çok az"],
                ["2", "Gerçekleşme ihtimali az"],
                ["3", "Gerçekleşme ihtimali var"],
                ["4", "Gerçekleşme ihtimali yüksek"],
                ["5", "Gerçekleşme ihtimali çok yüksek"],
            ],
            rect: CGRect(x: origin.x, y: origin.y, width: 360, height: 162)
        )
        drawReferenceTable(
            title: "ŞİDDET (Ş)",
            columns: ["Derece", "Tanım"],
            rows: [
                ["1", "Hafif yaralanmalar / iş günü kaybı yok"],
                ["2", "İlk yardım gerektiren küçük yaralanma"],
                ["3", "İş günü kaybı veya tedavi gerektiren yaralanma"],
                ["4", "Uzun süreli kayıp / ağır yaralanma"],
                ["5", "Kalıcı iş göremezlik veya ölüm"],
            ],
            rect: CGRect(x: origin.x + 392, y: origin.y, width: 382, height: 162)
        )

        let matrixRect = CGRect(x: origin.x + 74, y: origin.y + 214, width: 620, height: 232)
        drawText("5x5 Risk Matrisi - R = O x Ş", in: CGRect(x: matrixRect.minX, y: matrixRect.minY - 28, width: matrixRect.width, height: 18), font: .systemFont(ofSize: 12, weight: .bold), color: .rdPDFBlack, alignment: .center)
        let cellW = matrixRect.width / 6
        let cellH = matrixRect.height / 6
        for row in 0..<6 {
            for col in 0..<6 {
                let rect = CGRect(x: matrixRect.minX + CGFloat(col) * cellW, y: matrixRect.minY + CGFloat(row) * cellH, width: cellW, height: cellH)
                if row == 0 && col == 0 {
                    roundedStroke(rect, radius: 0, stroke: .rdPDFLine, fill: .rdPDFFog)
                    drawText("O / Ş", in: rect.insetBy(dx: 4, dy: 10), font: .systemFont(ofSize: 8, weight: .bold), color: .rdPDFSlate, alignment: .center)
                } else if row == 0 {
                    roundedStroke(rect, radius: 0, stroke: .rdPDFLine, fill: .rdPDFFog)
                    drawText("\(col)", in: rect.insetBy(dx: 4, dy: 10), font: .systemFont(ofSize: 9, weight: .bold), color: .rdPDFBlack, alignment: .center)
                } else if col == 0 {
                    roundedStroke(rect, radius: 0, stroke: .rdPDFLine, fill: .rdPDFFog)
                    drawText("\(row)", in: rect.insetBy(dx: 4, dy: 10), font: .systemFont(ofSize: 9, weight: .bold), color: .rdPDFBlack, alignment: .center)
                } else {
                    let score = row * col
                    roundedStroke(rect, radius: 0, stroke: .white, fill: matrixColor(score))
                    drawText("\(score)", in: rect.insetBy(dx: 4, dy: 10), font: .monospacedSystemFont(ofSize: 10, weight: .bold), color: .rdPDFBlack, alignment: .center)
                }
            }
        }
    }

    private func drawMethodLegend(input: ReportInput, rect: CGRect) {
        roundedStroke(rect, radius: 10, stroke: .rdPDFLine, fill: .white)
        let total = input.findings.reduce(0) { $0 + $1.score(for: input.options.method) }
        let top = input.findings.map { $0.score(for: input.options.method) }.max() ?? 0
        drawText("Metodoloji", in: CGRect(x: rect.minX + 14, y: rect.minY + 10, width: 120, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: .rdPDFSlate)
        drawText("\(input.options.method.fullName) · R = \(input.options.method.formula)", in: CGRect(x: rect.minX + 14, y: rect.minY + 29, width: 250, height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: .rdPDFBlack)
        drawText("En yüksek: \(scoreText(top))", in: CGRect(x: rect.minX + 340, y: rect.minY + 18, width: 140, height: 18), font: .monospacedSystemFont(ofSize: 12, weight: .bold), color: .rdPDFBlack)
        drawText("Toplam: \(scoreText(total))", in: CGRect(x: rect.minX + 520, y: rect.minY + 18, width: 140, height: 18), font: .monospacedSystemFont(ofSize: 12, weight: .bold), color: .rdPDFBlack)
    }

    private func drawRiskAnalysisInfoStrip(input: ReportInput, rect: CGRect) {
        roundedStroke(rect, radius: 0, stroke: .rdPDFBlack, fill: .rdPDFFog, lineWidth: 1)
        let analysis = input.bundle.analysis
        let prepared = input.options.preparedBy.nonEmpty ?? input.profile?.displayName ?? "Kullanıcı"
        let company = input.options.companyName.nonEmpty ?? input.profile?.companyName ?? "Firma belirtilmedi"
        let title = input.options.preparedTitle.nonEmpty ?? input.profile?.title ?? "Belirtilmedi"
        let certificate = input.options.certificateNumber.nonEmpty ?? input.profile?.certificateNumber ?? "Belirtilmedi"
        let companyInfo = input.options.companyInfo.nonEmpty ?? input.profile?.phone
        drawText("Analiz: \(analysis.title)", in: CGRect(x: rect.minX + 10, y: rect.minY + 5, width: 260, height: 10), font: .systemFont(ofSize: 7.5, weight: .bold), color: .rdPDFBlack)
        drawText("Firma: \(company)", in: CGRect(x: rect.minX + 10, y: rect.minY + 18, width: 260, height: 10), font: .systemFont(ofSize: 7.5), color: .rdPDFSlate)
        drawText("Firma bilgisi: \(companyInfo ?? "Belirtilmedi")", in: CGRect(x: rect.minX + 10, y: rect.minY + 31, width: 260, height: 10), font: .systemFont(ofSize: 7.5), color: .rdPDFSlate)
        drawText("Hazırlayan: \(prepared)", in: CGRect(x: rect.minX + 294, y: rect.minY + 5, width: 220, height: 10), font: .systemFont(ofSize: 7.5), color: .rdPDFSlate)
        drawText("Ünvan: \(title)", in: CGRect(x: rect.minX + 294, y: rect.minY + 18, width: 220, height: 10), font: .systemFont(ofSize: 7.5), color: .rdPDFSlate)
        drawText("Belge No: \(certificate)", in: CGRect(x: rect.minX + 294, y: rect.minY + 31, width: 220, height: 10), font: .systemFont(ofSize: 7.5), color: .rdPDFSlate)
        drawText("Tarih: \(formattedDate(analysis.createdAt))", in: CGRect(x: rect.minX + 548, y: rect.minY + 9, width: 200, height: 10), font: .systemFont(ofSize: 7.5), color: .rdPDFSlate, alignment: .right)
        drawText("Doküman No: #\(String(analysis.id.uuidString.prefix(8)).uppercased())", in: CGRect(x: rect.minX + 548, y: rect.minY + 23, width: 200, height: 10), font: .monospacedSystemFont(ofSize: 7.5, weight: .semibold), color: .rdPDFBlack, alignment: .right)
    }

    private func drawFineKinneyAssessmentTable(input: ReportInput, findings: [Finding], pageIndex: Int, rowsPerPage: Int) {
        let x: CGFloat = 32
        let y: CGFloat = 82
        let headerH: CGFloat = 44
        let rowH: CGFloat = 112
        let widths: [CGFloat] = [22, 52, 124, 58, 22, 22, 22, 36, 54, 150, 130, 44, 42]
        let headers = ["No", "Faaliyet\nAlanı", "Tehlikeli durum / davranış", "Risk", "O", "F", "Ş", "R", "Risk\nderecesi", "Önlem / kontrol tedbirleri", "Mevzuat", "Sorumlu", "Termin"]

        drawGridHeader(x: x, y: y, widths: widths, height: headerH, headers: headers, fill: .rdPDFTableBlue)

        for (idx, finding) in findings.enumerated() {
            let ordinal = pageIndex * rowsPerPage + idx + 1
            let rowY = y + headerH + CGFloat(idx) * rowH
            let band = finding.fkBand
            let activityArea = canvasLabel(input.bundle.analysis.canvas)
            let values = [
                "\(ordinal)",
                activityArea,
                finding.title + "\n" + finding.description,
                finding.category,
                scoreText(finding.fk.probability),
                scoreText(finding.fk.frequency),
                scoreText(finding.fk.severity),
                scoreText(finding.fkScore),
                band.label,
                finding.action,
                finding.references,
                input.options.preparedBy.nonEmpty ?? "İşveren",
                suggestedTerm(for: band.level),
            ]
            drawAssessmentRow(x: x, y: rowY, widths: widths, height: rowH, values: values, band: band.level, scoreColumn: 7, bandColumn: 8)
        }
    }

    private func drawMatrixAssessmentTable(input: ReportInput, findings: [Finding], pageIndex: Int, rowsPerPage: Int) {
        let x: CGFloat = 32
        let y: CGFloat = 82
        let headerH: CGFloat = 44
        let rowH: CGFloat = 100
        let widths: [CGFloat] = [22, 58, 132, 66, 26, 26, 38, 56, 170, 130, 54]
        let headers = ["No", "Faaliyet\nAlanı", "Tehlikeli durum / davranış", "Risk", "O", "Ş", "R", "Risk\nderecesi", "Önlem / kontrol tedbirleri", "Mevzuat", "Termin"]

        drawGridHeader(x: x, y: y, widths: widths, height: headerH, headers: headers, fill: .rdPDFTableBlue)

        for (idx, finding) in findings.enumerated() {
            let ordinal = pageIndex * rowsPerPage + idx + 1
            let rowY = y + headerH + CGFloat(idx) * rowH
            let band = finding.m5Band
            let activityArea = canvasLabel(input.bundle.analysis.canvas)
            let values = [
                "\(ordinal)",
                activityArea,
                finding.title + "\n" + finding.description,
                finding.category,
                "\(finding.m5.probability)",
                "\(finding.m5.severity)",
                "\(finding.m5Score)",
                band.label,
                finding.action,
                finding.references,
                suggestedTerm(for: band.level),
            ]
            drawAssessmentRow(x: x, y: rowY, widths: widths, height: rowH, values: values, band: band.level, scoreColumn: 6, bandColumn: 7)
        }
    }

    private func drawInfoBox(title: String, body: String, rect: CGRect) {
        roundedFill(rect, radius: 12, color: .rdPDFFog)
        drawText(title, in: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: rect.width - 28, height: 15), font: .systemFont(ofSize: 10, weight: .bold), color: .rdPDFSlate)
        drawText(body, in: CGRect(x: rect.minX + 14, y: rect.minY + 32, width: rect.width - 28, height: rect.height - 42), font: .systemFont(ofSize: 11), color: .rdPDFBlack)
    }

    private func drawReferenceTable(title: String, columns: [String], rows: [[String]], rect: CGRect, rowColors: [UIColor]? = nil) {
        roundedStroke(rect, radius: 0, stroke: .rdPDFTableLine, fill: .white, lineWidth: 0.8)
        let titleH: CGFloat = 20
        let headerH: CGFloat = 22
        let rowH = (rect.height - titleH - headerH) / CGFloat(max(rows.count, 1))
        roundedStroke(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: titleH), radius: 0, stroke: .rdPDFTableLine, fill: .rdPDFTableBlue, lineWidth: 0.8)
        drawText(title, in: CGRect(x: rect.minX + 4, y: rect.minY + 5, width: rect.width - 8, height: 10), font: .systemFont(ofSize: 9, weight: .bold), color: .rdPDFBlack, alignment: .center)

        let colWidths = referenceColumnWidths(count: columns.count, width: rect.width)
        var x = rect.minX
        for (idx, column) in columns.enumerated() {
            let w = colWidths[idx]
            roundedStroke(CGRect(x: x, y: rect.minY + titleH, width: w, height: headerH), radius: 0, stroke: .rdPDFTableLine, fill: .rdPDFFog, lineWidth: 0.8)
            drawText(column, in: CGRect(x: x + 3, y: rect.minY + titleH + 5, width: w - 6, height: headerH - 7), font: .systemFont(ofSize: 7, weight: .bold), color: .rdPDFBlack, alignment: .center)
            x += w
        }

        for (rowIdx, row) in rows.enumerated() {
            x = rect.minX
            let y = rect.minY + titleH + headerH + CGFloat(rowIdx) * rowH
            for colIdx in 0..<columns.count {
                let w = colWidths[colIdx]
                let fill = colIdx == 0 ? (rowColors?[safe: rowIdx] ?? .white) : UIColor.white
                roundedStroke(CGRect(x: x, y: y, width: w, height: rowH), radius: 0, stroke: .rdPDFTableLine, fill: fill, lineWidth: 0.6)
                drawText(row[safe: colIdx] ?? "", in: CGRect(x: x + 4, y: y + 4, width: w - 8, height: rowH - 8), font: .systemFont(ofSize: colIdx == 0 ? 8 : 7, weight: colIdx == 0 ? .bold : .regular), color: fill == UIColor.white ? .rdPDFBlack : .white, alignment: .center)
                x += w
            }
        }
    }

    private func referenceColumnWidths(count: Int, width: CGFloat) -> [CGFloat] {
        switch count {
        case 2: return [56, width - 56]
        case 4: return [110, 128, width - 110 - 128 - 110, 110]
        default:
            return Array(repeating: width / CGFloat(max(count, 1)), count: count)
        }
    }

    private func drawGridHeader(x: CGFloat, y: CGFloat, widths: [CGFloat], height: CGFloat, headers: [String], fill: UIColor) {
        var currentX = x
        for (idx, width) in widths.enumerated() {
            roundedStroke(CGRect(x: currentX, y: y, width: width, height: height), radius: 0, stroke: .rdPDFBlack, fill: fill, lineWidth: 0.8)
            drawText(headers[safe: idx] ?? "", in: CGRect(x: currentX + 3, y: y + 8, width: width - 6, height: height - 12), font: .systemFont(ofSize: 7, weight: .bold), color: .rdPDFBlack, alignment: .center)
            currentX += width
        }
    }

    private func drawAssessmentRow(x: CGFloat, y: CGFloat, widths: [CGFloat], height: CGFloat, values: [String], band: RiskLevel, scoreColumn: Int, bandColumn: Int) {
        var currentX = x
        for (idx, width) in widths.enumerated() {
            let fill: UIColor
            let textColor: UIColor
            if idx == scoreColumn || idx == bandColumn {
                fill = band.pdfColor
                textColor = .white
            } else {
                fill = .white
                textColor = .rdPDFBlack
            }
            roundedStroke(CGRect(x: currentX, y: y, width: width, height: height), radius: 0, stroke: .rdPDFBlack, fill: fill, lineWidth: 0.55)
            let font: UIFont = idx == scoreColumn || idx == bandColumn || idx == 0
                ? .systemFont(ofSize: idx == scoreColumn ? 10 : 7, weight: .bold)
                : .systemFont(ofSize: 6.8)
            drawText(values[safe: idx] ?? "", in: CGRect(x: currentX + 4, y: y + 7, width: width - 8, height: height - 14), font: font, color: textColor, alignment: idx <= 1 || idx == scoreColumn || idx == bandColumn ? .center : .left)
            currentX += width
        }
    }

    private func drawTableHeader(y: CGFloat) {
        let x: CGFloat = 42
        drawText("#", in: CGRect(x: x, y: y, width: 28, height: 18), font: .systemFont(ofSize: 9, weight: .bold), color: .rdPDFSlate)
        drawText("RİSK / KANIT", in: CGRect(x: x + 36, y: y, width: 300, height: 18), font: .systemFont(ofSize: 9, weight: .bold), color: .rdPDFSlate)
        drawText("SKOR", in: CGRect(x: x + 372, y: y, width: 70, height: 18), font: .systemFont(ofSize: 9, weight: .bold), color: .rdPDFSlate)
        drawText("ÖNERİLEN ÖNLEM", in: CGRect(x: x + 462, y: y, width: 290, height: 18), font: .systemFont(ofSize: 9, weight: .bold), color: .rdPDFSlate)
        UIColor.rdPDFLine.setFill()
        UIBezierPath(rect: CGRect(x: 42, y: y + 22, width: 758, height: 1)).fill()
    }

    private func drawFindingRow(ordinal: Int, finding: Finding, method: RiskMethod, y: CGFloat) {
        let x: CGFloat = 42
        let rowRect = CGRect(x: x, y: y, width: 758, height: 74)
        roundedStroke(rowRect, radius: 10, stroke: .rdPDFLine, fill: .white)

        drawText("\(ordinal)", in: CGRect(x: x + 12, y: y + 12, width: 24, height: 20), font: .monospacedSystemFont(ofSize: 12, weight: .bold), color: .rdPDFBlack)

        drawText(finding.title, in: CGRect(x: x + 48, y: y + 10, width: 286, height: 18), font: .systemFont(ofSize: 12, weight: .bold), color: .rdPDFBlack)
        drawText(finding.description, in: CGRect(x: x + 48, y: y + 30, width: 286, height: 34), font: .systemFont(ofSize: 9), color: .rdPDFSlate)

        let band = finding.band(for: method)
        roundedFill(CGRect(x: x + 370, y: y + 14, width: 70, height: 34), radius: 8, color: band.level.pdfColor)
        drawText(scoreText(finding.score(for: method)), in: CGRect(x: x + 370, y: y + 19, width: 70, height: 20), font: .monospacedSystemFont(ofSize: 16, weight: .bold), color: .white, alignment: .center)
        drawText(band.label, in: CGRect(x: x + 360, y: y + 52, width: 90, height: 14), font: .systemFont(ofSize: 8, weight: .bold), color: band.level.pdfColor, alignment: .center)

        drawText(finding.action, in: CGRect(x: x + 462, y: y + 12, width: 286, height: 52), font: .systemFont(ofSize: 10), color: .rdPDFBlack)
    }

    private func drawImage(_ image: UIImage, in rect: CGRect, cornerRadius: CGFloat, mode: UIView.ContentMode = .scaleAspectFill) {
        guard let cgContext = UIGraphicsGetCurrentContext() else { return }
        cgContext.saveGState()
        defer { cgContext.restoreGState() }

        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        path.addClip()

        let imageRect: CGRect
        switch mode {
        case .scaleAspectFit:
            imageRect = image.aspectFitRect(in: rect)
        default:
            imageRect = image.aspectFillRect(in: rect)
        }
        image.draw(in: imageRect)
    }

    private func drawPlaceholder(in rect: CGRect, text: String) {
        roundedFill(rect, radius: 14, color: .rdPDFFog)
        drawText(text.uppercased(), in: rect.insetBy(dx: 12, dy: rect.height / 2 - 8), font: .systemFont(ofSize: 10, weight: .bold), color: .rdPDFSlate, alignment: .center)
    }

    private func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
    }

    private func roundedFill(_ rect: CGRect, radius: CGFloat, color: UIColor) {
        color.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
    }

    private func roundedStroke(_ rect: CGRect, radius: CGFloat, stroke: UIColor, fill: UIColor, lineWidth: CGFloat = 1) {
        fill.setFill()
        stroke.setStroke()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        path.lineWidth = lineWidth
        path.fill()
        path.stroke()
    }

    private func formattedDate(_ raw: String?) -> String {
        guard let raw else { return "Tarih yok" }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMMM yyyy · HH:mm"
        return formatter.string(from: date)
    }

    private func canvasLabel(_ id: String) -> String {
        AnalysisCanvas.all.first(where: { $0.id == id })?.title ?? id.capitalized
    }

    private func scoreText(_ value: Double) -> String {
        value == floor(value) ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func matrixColor(_ score: Int) -> UIColor {
        switch score {
        case 20...: return .rdPDFCritical
        case 10...19: return .rdPDFHigh
        case 5...9: return .rdPDFMedium
        default: return .rdPDFGreen
        }
    }

    private func suggestedTerm(for level: RiskLevel) -> String {
        switch level {
        case .critical: return "Hemen"
        case .high: return "30 gün"
        case .medium: return "90 gün"
        case .low: return "Kontrol"
        case .unknown: return "Belirle"
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }

    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension UIImage {
    func aspectFillRect(in rect: CGRect) -> CGRect {
        let scale = max(rect.width / size.width, rect.height / size.height)
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
    }

    func aspectFitRect(in rect: CGRect) -> CGRect {
        let scale = min(rect.width / size.width, rect.height / size.height)
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
    }
}

private extension UIColor {
    static let rdPDFBlack = UIColor(red: 0.043, green: 0.051, blue: 0.055, alpha: 1)
    static let rdPDFSlate = UIColor(red: 0.42, green: 0.45, blue: 0.50, alpha: 1)
    static let rdPDFLine = UIColor(red: 0.86, green: 0.89, blue: 0.88, alpha: 1)
    static let rdPDFPaper = UIColor(red: 0.98, green: 0.985, blue: 0.98, alpha: 1)
    static let rdPDFFog = UIColor(red: 0.945, green: 0.957, blue: 0.949, alpha: 1)
    static let rdPDFTableLine = UIColor(red: 0.15, green: 0.48, blue: 0.58, alpha: 1)
    static let rdPDFTableBlue = UIColor(red: 0.86, green: 0.95, blue: 0.98, alpha: 1)
    static let rdPDFCritical = UIColor(red: 0.80, green: 0.00, blue: 0.00, alpha: 1)
    static let rdPDFHigh = UIColor(red: 0.94, green: 0.68, blue: 0.00, alpha: 1)
    static let rdPDFMedium = UIColor(red: 0.96, green: 0.88, blue: 0.10, alpha: 1)
    static let rdPDFLow = UIColor(red: 0.11, green: 0.65, blue: 0.86, alpha: 1)
    static let rdPDFGreen = UIColor(red: 0.35, green: 0.78, blue: 0.25, alpha: 1)
}

private extension RiskLevel {
    var pdfColor: UIColor {
        switch self {
        case .critical: return UIColor(red: 0.71, green: 0.14, blue: 0.10, alpha: 1)
        case .high: return UIColor(red: 0.78, green: 0.42, blue: 0.00, alpha: 1)
        case .medium: return UIColor(red: 0.78, green: 0.60, blue: 0.02, alpha: 1)
        case .low: return UIColor(red: 0.14, green: 0.48, blue: 0.23, alpha: 1)
        case .unknown: return UIColor(red: 0.58, green: 0.64, blue: 0.72, alpha: 1)
        }
    }

    var pdfBackground: UIColor {
        switch self {
        case .critical: return UIColor(red: 0.99, green: 0.93, blue: 0.93, alpha: 1)
        case .high: return UIColor(red: 1.00, green: 0.96, blue: 0.87, alpha: 1)
        case .medium: return UIColor(red: 1.00, green: 0.98, blue: 0.76, alpha: 1)
        case .low: return UIColor(red: 0.91, green: 0.96, blue: 0.94, alpha: 1)
        case .unknown: return UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)
        }
    }
}
