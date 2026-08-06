import Foundation
import UIKit
#if DEBUG
import PDFKit
#endif

enum PDFReportKind: String, CaseIterable, Identifiable {
    case standard
    case riskAnalysis

    var id: String { rawValue }

    var title: String {
        localizedTitle()
    }

    func localizedTitle(language: RDLanguage = .turkish) -> String {
        switch self {
        case .standard:
            return RDLocalization.shared.text(.standardPDFTitle, language: language)
        case .riskAnalysis:
            return RDLocalization.shared.text(.riskAnalysisPDFTitle, language: language)
        }
    }

    var subtitle: String {
        localizedSubtitle()
    }

    func localizedSubtitle(language: RDLanguage = .turkish) -> String {
        switch self {
        case .standard:
            return RDLocalization.shared.text(.standardPDFSubtitle, language: language)
        case .riskAnalysis:
            return RDLocalization.shared.text(.riskAnalysisPDFSubtitle, language: language)
        }
    }

    var headerTitle: String {
        localizedHeaderTitle()
    }

    func localizedHeaderTitle(language: RDLanguage = .turkish) -> String {
        switch self {
        case .standard:
            return RDLocalization.shared.text(.standardReportHeader, language: language)
        case .riskAnalysis:
            return RDLocalization.shared.text(.riskAnalysisReportHeader, language: language)
        }
    }

    var detailTitle: String {
        localizedDetailTitle()
    }

    func localizedDetailTitle(language: RDLanguage = .turkish) -> String {
        switch self {
        case .standard:
            return RDLocalization.shared.text(.findingDetailsHeader, language: language)
        case .riskAnalysis:
            return RDLocalization.shared.text(.riskAnalysisTableHeader, language: language)
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
    var companyID: UUID?
    var language: RDLanguage = .turkish

    static func standard(method: RiskMethod) -> PDFReportOptions {
        PDFReportOptions(kind: .standard, method: method)
    }
}

final class PDFReportService: @unchecked Sendable {
    static let shared = PDFReportService()
    private static let coverImageRasterScale: CGFloat = 2

    private struct AssessmentTableRow {
        let ordinal: Int
        let finding: Finding
        let height: CGFloat
    }

    private init() {}

    enum ReportError: LocalizedError {
        case localizationSnapshotMissing
        case reportLanguageMismatch

        var errorDescription: String? {
            switch self {
            case .localizationSnapshotMissing:
                return "REPORT_LOCALIZATION_SNAPSHOT_MISSING"
            case .reportLanguageMismatch:
                return "REPORT_LANGUAGE_MISMATCH"
            }
        }
    }

    struct ReportInput {
        let bundle: AnalysisResultBundle
        let findings: [Finding]
        let profile: UserProfile?
        let image: UIImage?
        let images: [UIImage]
        let companyLogo: UIImage?
        let options: PDFReportOptions

        init(
            bundle: AnalysisResultBundle,
            findings: [Finding],
            profile: UserProfile?,
            image: UIImage?,
            companyLogo: UIImage?,
            options: PDFReportOptions
        ) {
            self.bundle = bundle
            self.findings = findings
            self.profile = profile
            self.image = image
            self.images = image.map { [$0] } ?? []
            self.companyLogo = companyLogo
            self.options = options
        }

        init(
            bundle: AnalysisResultBundle,
            findings: [Finding],
            profile: UserProfile?,
            images: [UIImage],
            companyLogo: UIImage?,
            options: PDFReportOptions
        ) {
            self.bundle = bundle
            self.findings = findings
            self.profile = profile
            self.image = images.first
            self.images = images
            self.companyLogo = companyLogo
            self.options = options
        }
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
        guard input.bundle.analysis.hasCompleteLocalizationSnapshot else {
            throw ReportError.localizationSnapshotMissing
        }
        guard input.options.language == input.bundle.analysis.resolvedOutputLanguage else {
            throw ReportError.reportLanguageMismatch
        }

        let fileURL = outputURL(
            for: input.bundle.analysis,
            language: input.options.language
        )
        let pageRect = CGRect(x: 0, y: 0, width: 842, height: 595) // A4 landscape @ 72 dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        try renderer.writePDF(to: fileURL) { context in
            switch input.options.kind {
            case .standard:
                let totalPages = standardTotalPageCount(input: input, pageRect: pageRect)
                drawCoverPage(input: input, context: context, pageRect: pageRect, totalPages: totalPages)
                drawFindingPages(input: input, context: context, pageRect: pageRect, totalPages: totalPages)
            case .riskAnalysis:
                let assessmentPages = riskAssessmentPages(input: input, pageRect: pageRect)
                let totalPages = max(1, assessmentPages.count + 1)
                drawRiskMethodReferencePage(input: input, context: context, pageRect: pageRect, totalPages: totalPages)
                drawRiskAnalysisTablePages(input: input, context: context, pageRect: pageRect, pages: assessmentPages, totalPages: totalPages)
            }
        }

        return fileURL
    }

    private func outputURL(for analysis: AnalysisRow, language: RDLanguage) -> URL {
        let safeTitle = analysis.title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "·", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        let shortID = String(analysis.id.uuidString.prefix(8)).uppercased()
        let reportKind = language == .english ? "Risk_Assessment" : "Risk_Analizi"
        let fileName = "RiskDetected_\(safeTitle)_\(reportKind)_\(shortID).pdf"
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    private func drawCoverPage(input: ReportInput, context: UIGraphicsPDFRendererContext, pageRect: CGRect, totalPages: Int) {
        context.beginPage()
        drawPageChrome(input: input, pageRect: pageRect, title: input.options.kind.localizedHeaderTitle(language: input.options.language), page: 1, totalPages: totalPages)

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

        let language = input.options.language
        let sectorPart = analysis.analysisSectorID.map {
            "\(copy(language: language, tr: "Analiz kapsamı", en: "Analysis scope")): \($0.label(language: language)) · "
        } ?? ""
        drawText(
            "\(formattedDate(analysis.createdAt, language: language)) · \(sectorPart)\(copy(language: language, tr: "Analiz odağı", en: "Analysis focus")): \(canvasLabel(analysis.canvas, language: language)) · \(findingCountText(input.findings.count, language: language))",
            in: CGRect(x: margin, y: contentTop + 38, width: 520, height: 22),
            font: .systemFont(ofSize: 12, weight: .medium),
            color: .rdPDFSlate
        )

        drawSummaryCards(input: input, origin: CGPoint(x: margin, y: contentTop + 88))

        if !input.images.isEmpty {
            drawCoverImages(input.images, in: CGRect(x: 548, y: contentTop, width: 252, height: 178))
        } else if analysis.kind == "text" {
            drawPlaceholder(
                in: CGRect(x: 548, y: contentTop, width: 252, height: 178),
                text: copy(language: language, tr: "Metin Analizi", en: "Text Analysis")
            )
        } else {
            drawPlaceholder(
                in: CGRect(x: 548, y: contentTop, width: 252, height: 178),
                text: copy(language: language, tr: "Fotoğraf", en: "Photo")
            )
        }

        let summary = analysis.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        drawInfoBox(
            title: copy(language: language, tr: "Uygunsuzluk Özeti", en: "Finding Summary"),
            body: summary?.isEmpty == false
                ? summary!
                : copy(
                    language: language,
                    tr: "\(input.findings.count) bulgu tespit edildi. Bulgular \(methodName(input.options.method, language: language)) metoduna göre önceliklendirilmiştir.",
                    en: "\(input.findings.count) findings were identified and prioritised using the \(methodName(input.options.method, language: language)) method."
                ),
            rect: CGRect(x: margin, y: 340, width: 758, height: 86)
        )

        let expert = input.options.preparedBy.nonEmpty
            ?? profile?.displayName
            ?? copy(language: language, tr: "Kullanıcı", en: "User")
        let title = input.options.preparedTitle.nonEmpty ?? profile?.title
        let certificate = input.options.certificateNumber.nonEmpty ?? profile?.certificateNumber
        let companyName = input.options.companyName.nonEmpty ?? profile?.companyName
        let companyInfo = input.options.companyInfo.nonEmpty ?? profile?.phone
        let credential = [
            title,
            certificate.map { "\(copy(language: language, tr: "Belge no", en: "Certificate no.")): \($0)" }
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
            .joined(separator: " · ")
        let companyParts = [
            companyName.map { "\(copy(language: language, tr: "Firma", en: "Company")): \($0)" },
            companyInfo
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
            .joined(separator: " · ")
        let footerParts = [
            "\(copy(language: language, tr: "Hazırlayan", en: "Prepared by")): \(expert)",
            credential.nonEmpty ?? copy(language: language, tr: "İSG Uzmanı", en: "Safety professional"),
            companyParts.nonEmpty,
            "\(copy(language: language, tr: "Doküman No", en: "Document no.")): #\(String(analysis.id.uuidString.prefix(8)).uppercased())"
        ].compactMap { $0 }
        let footer = footerParts.joined(separator: " · ")
        drawFittingText(
            footer,
            in: CGRect(x: margin, y: 448, width: 758, height: 22),
            baseFont: .monospacedSystemFont(ofSize: 9.5, weight: .medium),
            minimumFontSize: 7,
            color: .rdPDFSlate
        )

        drawText(
            reportDisclaimer(language: language),
            in: CGRect(x: margin, y: 472, width: 758, height: 18),
            font: .systemFont(ofSize: 7.2, weight: .regular),
            color: .rdPDFSlate,
            alignment: .center
        )
        drawMethodLegend(input: input, rect: CGRect(x: margin, y: 496, width: 758, height: 48))
    }

    private func drawFindingPages(input: ReportInput, context: UIGraphicsPDFRendererContext, pageRect: CGRect, totalPages: Int) {
        guard !input.findings.isEmpty else { return }

        let topY: CGFloat = 122
        let bottomY = pageRect.height - 42
        let rowSpacing: CGFloat = 8
        let maxRowHeight = bottomY - topY
        var page = 2
        var y = topY

        func beginFindingPage() {
            context.beginPage()
            drawPageChrome(input: input, pageRect: pageRect, title: input.options.kind.localizedDetailTitle(language: input.options.language), page: page, totalPages: totalPages)
            drawTableHeader(y: 92, language: input.options.language)
            y = topY
            page += 1
        }

        beginFindingPage()

        for (index, finding) in input.findings.enumerated() {
            let rowHeight = min(standardFindingRowHeight(for: finding, language: input.options.language), maxRowHeight)
            if y > topY, y + rowHeight > bottomY {
                beginFindingPage()
            }

            drawFindingRow(
                ordinal: index + 1,
                finding: finding,
                method: input.options.method,
                language: input.options.language,
                y: y,
                height: rowHeight
            )
            y += rowHeight + rowSpacing
        }
    }

    private func standardTotalPageCount(input: ReportInput, pageRect: CGRect) -> Int {
        guard !input.findings.isEmpty else { return 1 }

        let topY: CGFloat = 122
        let bottomY = pageRect.height - 42
        let rowSpacing: CGFloat = 8
        let maxRowHeight = bottomY - topY
        var pages = 1
        var y = topY
        var hasFindingPage = false

        for finding in input.findings {
            let rowHeight = min(standardFindingRowHeight(for: finding, language: input.options.language), maxRowHeight)
            if !hasFindingPage {
                pages += 1
                hasFindingPage = true
                y = topY
            } else if y > topY, y + rowHeight > bottomY {
                pages += 1
                y = topY
            }
            y += rowHeight + rowSpacing
        }

        return pages
    }

    private func riskAssessmentPages(input: ReportInput, pageRect: CGRect) -> [[AssessmentTableRow]] {
        guard !input.findings.isEmpty else { return [] }

        let headerH: CGFloat = 44
        let topY: CGFloat = 82 + headerH
        let bottomY = pageRect.height - 32
        let maxRowHeight = bottomY - topY
        var pages: [[AssessmentTableRow]] = []
        var currentRows: [AssessmentTableRow] = []
        var usedHeight: CGFloat = 0

        for (index, finding) in input.findings.enumerated() {
            let rowHeight = min(assessmentRowHeight(input: input, finding: finding, ordinal: index + 1), maxRowHeight)
            if !currentRows.isEmpty, usedHeight + rowHeight > maxRowHeight {
                pages.append(currentRows)
                currentRows.removeAll(keepingCapacity: true)
                usedHeight = 0
            }

            currentRows.append(AssessmentTableRow(ordinal: index + 1, finding: finding, height: rowHeight))
            usedHeight += rowHeight
        }

        if !currentRows.isEmpty {
            pages.append(currentRows)
        }

        return pages
    }

    private func drawRiskMethodReferencePage(input: ReportInput, context: UIGraphicsPDFRendererContext, pageRect: CGRect, totalPages: Int) {
        context.beginPage()
        let language = input.options.language
        let title = input.options.method == .fineKinney
            ? copy(language: language, tr: "FINE-KINNEY METODU REFERANS TABLOSU", en: "FINE-KINNEY METHOD REFERENCE TABLE")
            : copy(language: language, tr: "5x5 L-TİPİ MATRİS REFERANS TABLOSU", en: "5×5 L-TYPE MATRIX REFERENCE TABLE")
        drawRiskAnalysisChrome(input: input, pageRect: pageRect, title: title, page: 1, totalPages: totalPages)

        let margin: CGFloat = 32
        if input.options.method == .fineKinney {
            drawFineKinneyReference(origin: CGPoint(x: margin, y: 82), language: language)
        } else {
            drawMatrix5Reference(origin: CGPoint(x: margin, y: 82), language: language)
        }

        drawRiskAnalysisInfoStrip(input: input, rect: CGRect(x: margin, y: 520, width: pageRect.width - margin * 2, height: 42))
    }

    private func drawRiskAnalysisTablePages(input: ReportInput, context: UIGraphicsPDFRendererContext, pageRect: CGRect, pages: [[AssessmentTableRow]], totalPages: Int) {
        guard !pages.isEmpty else { return }

        for (pageIndex, rows) in pages.enumerated() {
            context.beginPage()
            let title = input.options.method == .fineKinney
                ? copy(language: input.options.language, tr: "TEHLİKE VE RİSK DEĞERLENDİRME FORMU (FINE-KINNEY)", en: "HAZARD AND RISK ASSESSMENT FORM (FINE-KINNEY)")
                : copy(language: input.options.language, tr: "TEHLİKE VE RİSK DEĞERLENDİRME FORMU (5x5 L-TİPİ)", en: "HAZARD AND RISK ASSESSMENT FORM (5×5 L-TYPE)")
            drawRiskAnalysisChrome(input: input, pageRect: pageRect, title: title, page: pageIndex + 2, totalPages: totalPages)

            if input.options.method == .fineKinney {
                drawFineKinneyAssessmentTable(input: input, rows: rows)
            } else {
                drawMatrixAssessmentTable(input: input, rows: rows)
            }
        }
    }

    private func drawPageChrome(input: ReportInput, pageRect: CGRect, title: String, page: Int, totalPages: Int) {
        UIColor.rdPDFPaper.setFill()
        UIBezierPath(rect: pageRect).fill()

        drawReportLogo(input: input, in: CGRect(x: 42, y: 26, width: 120, height: 34), fallbackTextRect: CGRect(x: 42, y: 26, width: 140, height: 28), companyCornerRadius: 6)

        if input.companyLogo == nil, let companyName = input.options.companyName.nonEmpty {
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
            "\(copy(language: input.options.language, tr: "Sayfa", en: "Page")) \(page)/\(totalPages)",
            in: CGRect(x: pageRect.width - 118, y: 31, width: 76, height: 18),
            font: .monospacedSystemFont(ofSize: 10, weight: .medium),
            color: .rdPDFSlate,
            alignment: .right
        )

        UIColor.rdPDFBlack.setFill()
        UIBezierPath(rect: CGRect(x: 42, y: 70, width: pageRect.width - 84, height: 2)).fill()
    }

    private func drawRiskAnalysisChrome(input: ReportInput, pageRect: CGRect, title: String, page: Int, totalPages: Int) {
        UIColor.white.setFill()
        UIBezierPath(rect: pageRect).fill()

        let margin: CGFloat = 32
        roundedStroke(CGRect(x: margin, y: 24, width: pageRect.width - margin * 2, height: 42), radius: 0, stroke: .rdPDFBlack, fill: .white, lineWidth: 1.4)
        drawText(title, in: CGRect(x: margin + 12, y: 36, width: pageRect.width - margin * 2 - 24, height: 16), font: .systemFont(ofSize: 13, weight: .bold), color: .rdPDFBlack, alignment: .center)

        drawReportLogo(input: input, in: CGRect(x: margin + 8, y: 29, width: 104, height: 28), fallbackTextRect: CGRect(x: margin + 8, y: 29, width: 104, height: 18), companyCornerRadius: 4)
        drawText(
            "\(copy(language: input.options.language, tr: "Sayfa", en: "Page")) \(page)/\(totalPages)",
            in: CGRect(x: pageRect.width - margin - 62, y: 38, width: 58, height: 12),
            font: .monospacedSystemFont(ofSize: 8, weight: .medium),
            color: .rdPDFSlate,
            alignment: .right
        )
    }

    private func drawReportLogo(input: ReportInput, in rect: CGRect, fallbackTextRect: CGRect, companyCornerRadius: CGFloat) {
        if let companyLogo = input.companyLogo {
            drawImage(companyLogo, in: rect, cornerRadius: companyCornerRadius, mode: .scaleAspectFit)
        } else if let logo = UIImage(named: "RDLogo") {
            drawImage(logo, in: rect, cornerRadius: 0, mode: .scaleAspectFit)
        } else {
            drawText("RiskDetected", in: fallbackTextRect, font: .systemFont(ofSize: 20, weight: .bold), color: .rdPDFBlack)
        }
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
            drawText(riskLevelLabel(level, language: input.options.language).uppercased(), in: CGRect(x: rect.minX + 12, y: rect.minY + 42, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 10, weight: .bold), color: level.pdfColor)
        }
    }

    private func drawFineKinneyReference(origin: CGPoint, language: RDLanguage) {
        let tableWidth: CGFloat = 246
        let gap: CGFloat = 18
        let probabilityRows = language == .english
            ? [
                ["10", "Expected; near certain"],
                ["6", "High; quite possible"],
                ["3", "Possible"],
                ["1", "Possible but unlikely"],
                ["0.5", "Unexpected but possible"],
                ["0.2", "Not expected"],
            ]
            : [
                ["10", "Beklenir, kesin"],
                ["6", "Yüksek, oldukça mümkün"],
                ["3", "Olası"],
                ["1", "Mümkün fakat düşük"],
                ["0.5", "Beklenmez fakat mümkün"],
                ["0.2", "Beklenmez"],
            ]
        drawReferenceTable(
            title: copy(language: language, tr: "OLASILIK (O)", en: "PROBABILITY (P)"),
            columns: [
                copy(language: language, tr: "Değer", en: "Value"),
                copy(language: language, tr: "Zararın gerçekleşme olasılığı", en: "Likelihood of harm"),
            ],
            rows: probabilityRows,
            rect: CGRect(x: origin.x, y: origin.y, width: tableWidth, height: 212)
        )
        let frequencyRows = language == .english
            ? [
                ["10", "Almost continuous / several times per hour"],
                ["6", "Frequent / once or several times per day"],
                ["3", "Occasional / several times per week"],
                ["2", "Infrequent / several times per month"],
                ["1", "Rare / several times per year"],
                ["0.5", "Very rare / once per year or less"],
            ]
            : [
                ["10", "Hemen hemen sürekli / saatte birkaç defa"],
                ["6", "Sık / günde bir veya birkaç defa"],
                ["3", "Ara sıra / haftada birkaç defa"],
                ["2", "Sık değil / ayda birkaç defa"],
                ["1", "Seyrek / yılda birkaç defa"],
                ["0.5", "Çok seyrek / yılda bir veya daha az"],
            ]
        drawReferenceTable(
            title: copy(language: language, tr: "FREKANS (F)", en: "FREQUENCY (F)"),
            columns: [
                copy(language: language, tr: "Değer", en: "Value"),
                copy(language: language, tr: "Tehlikeye maruz kalma tekrarı", en: "Exposure frequency"),
            ],
            rows: frequencyRows,
            rect: CGRect(x: origin.x + tableWidth + gap, y: origin.y, width: tableWidth, height: 212)
        )
        let severityRows = language == .english
            ? [
                ["100", "Multiple fatalities / environmental disaster"],
                ["40", "Fatality / serious environmental harm"],
                ["15", "Permanent injury or work loss"],
                ["7", "Significant injury / external first aid"],
                ["3", "Minor injury / on-site first aid"],
                ["1", "Near miss / no environmental harm"],
            ]
            : [
                ["100", "Birden fazla ölümlü kaza / çevresel felaket"],
                ["40", "Ölümlü kaza / ciddi çevresel zarar"],
                ["15", "Kalıcı hasar veya iş kaybı"],
                ["7", "Önemli yaralanma / dış ilk yardım"],
                ["3", "Küçük yaralanma / iç ilk yardım"],
                ["1", "Ucuz atlatma / çevresel zarar yok"],
            ]
        drawReferenceTable(
            title: copy(language: language, tr: "ŞİDDET (Ş)", en: "SEVERITY (S)"),
            columns: [
                copy(language: language, tr: "Değer", en: "Value"),
                copy(language: language, tr: "İnsan/çevre üzerinde tahmini zarar", en: "Estimated harm to people/environment"),
            ],
            rows: severityRows,
            rect: CGRect(x: origin.x + (tableWidth + gap) * 2, y: origin.y, width: tableWidth, height: 212)
        )

        let riskRows = language == .english
            ? [
                ["1801 ≤ R", "Intolerable", "Stop work immediately; consider isolating the area.", "Immediate / 1 week"],
                ["401 ≤ R < 1801", "Act as soon as possible", "Restrict activity until risk is reduced.", "Less than 1 month"],
                ["201 ≤ R < 401", "Substantial risk", "Take urgent action and monitor the activity.", "1–3 months"],
                ["71 ≤ R < 201", "Significant risk", "Start a corrective action plan.", "6 months"],
                ["21 ≤ R < 71", "Possible risk", "Maintain and monitor controls.", "1 year"],
                ["R < 21", "Minor risk", "Additional controls may not be required.", "Review"],
            ]
            : [
                ["1801 ≤ R", "Tolerans gösterilemez", "İş derhal durdurulur; tesis/çevre kapatılması düşünülebilir.", "Hemen / 1 hafta"],
                ["401 ≤ R < 1801", "En kısa sürede giderilecek", "Risk kabul edilebilir seviyeye düşene kadar faaliyet kısıtlanır.", "1 aydan kısa"],
                ["201 ≤ R < 401", "Esaslı risk", "Acil önlem alınır ve faaliyet izlenir.", "1-3 ay"],
                ["71 ≤ R < 201", "Önemli risk", "Düzeltici faaliyet planı başlatılır.", "6 ay"],
                ["21 ≤ R < 71", "Olası risk", "Kontroller sürdürülür ve izlenir.", "1 yıl"],
                ["R < 21", "Önemsiz risk", "İlave kontrole gerek olmayabilir.", "Kontrol"],
            ]
        drawReferenceTable(
            title: copy(language: language, tr: "RİSK DEĞERİ (R = O x F x Ş)", en: "RISK VALUE (R = P × F × S)"),
            columns: [
                copy(language: language, tr: "Risk değeri", en: "Risk value"),
                copy(language: language, tr: "Risk adı", en: "Risk band"),
                copy(language: language, tr: "Eylem", en: "Action"),
                copy(language: language, tr: "Termin", en: "Due"),
            ],
            rows: riskRows,
            rect: CGRect(x: origin.x, y: origin.y + 244, width: 774, height: 178),
            rowColors: [.rdPDFCritical, .rdPDFCritical, .rdPDFHigh, .rdPDFMedium, .rdPDFLow, .rdPDFGreen]
        )
    }

    private func drawMatrix5Reference(origin: CGPoint, language: RDLanguage) {
        let probabilityRows = language == .english
            ? [
                ["1", "Very unlikely"],
                ["2", "Unlikely"],
                ["3", "Possible"],
                ["4", "Likely"],
                ["5", "Very likely"],
            ]
            : [
                ["1", "Gerçekleşme ihtimali çok az"],
                ["2", "Gerçekleşme ihtimali az"],
                ["3", "Gerçekleşme ihtimali var"],
                ["4", "Gerçekleşme ihtimali yüksek"],
                ["5", "Gerçekleşme ihtimali çok yüksek"],
            ]
        drawReferenceTable(
            title: copy(language: language, tr: "OLASILIK (O)", en: "PROBABILITY (P)"),
            columns: [
                copy(language: language, tr: "Derece", en: "Rating"),
                copy(language: language, tr: "Tanım", en: "Description"),
            ],
            rows: probabilityRows,
            rect: CGRect(x: origin.x, y: origin.y, width: 360, height: 162)
        )
        let severityRows = language == .english
            ? [
                ["1", "Minor injury / no lost time"],
                ["2", "Minor injury requiring first aid"],
                ["3", "Lost time or treatment required"],
                ["4", "Long-term absence / serious injury"],
                ["5", "Permanent disability or fatality"],
            ]
            : [
                ["1", "Hafif yaralanmalar / iş günü kaybı yok"],
                ["2", "İlk yardım gerektiren küçük yaralanma"],
                ["3", "İş günü kaybı veya tedavi gerektiren yaralanma"],
                ["4", "Uzun süreli kayıp / ağır yaralanma"],
                ["5", "Kalıcı iş göremezlik veya ölüm"],
            ]
        drawReferenceTable(
            title: copy(language: language, tr: "ŞİDDET (Ş)", en: "SEVERITY (S)"),
            columns: [
                copy(language: language, tr: "Derece", en: "Rating"),
                copy(language: language, tr: "Tanım", en: "Description"),
            ],
            rows: severityRows,
            rect: CGRect(x: origin.x + 392, y: origin.y, width: 382, height: 162)
        )

        let matrixRect = CGRect(x: origin.x + 74, y: origin.y + 214, width: 620, height: 232)
        drawText(
            copy(language: language, tr: "5x5 Risk Matrisi - R = O x Ş", en: "5×5 Risk Matrix — R = P × S"),
            in: CGRect(x: matrixRect.minX, y: matrixRect.minY - 28, width: matrixRect.width, height: 18),
            font: .systemFont(ofSize: 12, weight: .bold),
            color: .rdPDFBlack,
            alignment: .center
        )
        let cellW = matrixRect.width / 6
        let cellH = matrixRect.height / 6
        for row in 0..<6 {
            for col in 0..<6 {
                let rect = CGRect(x: matrixRect.minX + CGFloat(col) * cellW, y: matrixRect.minY + CGFloat(row) * cellH, width: cellW, height: cellH)
                if row == 0 && col == 0 {
                    roundedStroke(rect, radius: 0, stroke: .rdPDFLine, fill: .rdPDFFog)
                    drawText(
                        copy(language: language, tr: "O / Ş", en: "P / S"),
                        in: rect.insetBy(dx: 4, dy: 10),
                        font: .systemFont(ofSize: 8, weight: .bold),
                        color: .rdPDFSlate,
                        alignment: .center
                    )
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
        let language = input.options.language
        drawText(copy(language: language, tr: "Metodoloji", en: "Methodology"), in: CGRect(x: rect.minX + 14, y: rect.minY + 7, width: 120, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: .rdPDFSlate)
        drawText("\(methodName(input.options.method, language: language)) · R = \(methodFormula(input.options.method, language: language))", in: CGRect(x: rect.minX + 14, y: rect.minY + 25, width: 250, height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: .rdPDFBlack)
        drawText("\(copy(language: language, tr: "En yüksek", en: "Highest")): \(scoreText(top, language: language))", in: CGRect(x: rect.minX + 340, y: rect.minY + 15, width: 140, height: 18), font: .monospacedSystemFont(ofSize: 12, weight: .bold), color: .rdPDFBlack)
        drawText("\(copy(language: language, tr: "Toplam", en: "Total")): \(scoreText(total, language: language))", in: CGRect(x: rect.minX + 520, y: rect.minY + 15, width: 140, height: 18), font: .monospacedSystemFont(ofSize: 12, weight: .bold), color: .rdPDFBlack)
    }

    private func drawRiskAnalysisInfoStrip(input: ReportInput, rect: CGRect) {
        roundedStroke(rect, radius: 0, stroke: .rdPDFBlack, fill: .rdPDFFog, lineWidth: 1)
        let analysis = input.bundle.analysis
        let language = input.options.language
        let unspecified = copy(language: language, tr: "Belirtilmedi", en: "Not provided")
        let prepared = input.options.preparedBy.nonEmpty
            ?? input.profile?.displayName
            ?? copy(language: language, tr: "Kullanıcı", en: "User")
        let company = input.options.companyName.nonEmpty
            ?? input.profile?.companyName
            ?? copy(language: language, tr: "Firma belirtilmedi", en: "Company not provided")
        let title = input.options.preparedTitle.nonEmpty ?? input.profile?.title ?? unspecified
        let certificate = input.options.certificateNumber.nonEmpty ?? input.profile?.certificateNumber ?? unspecified
        let companyInfo = input.options.companyInfo.nonEmpty ?? input.profile?.phone
        let sectorLine = analysis.analysisSectorID.map {
            "\(copy(language: language, tr: "Analiz kapsamı", en: "Analysis scope")): \($0.label(language: language))\n"
        } ?? ""
        drawFittingText(
            "\(sectorLine)\(copy(language: language, tr: "Analiz", en: "Analysis")): \(analysis.title)\n\(copy(language: language, tr: "Firma", en: "Company")): \(company)\n\(copy(language: language, tr: "Firma bilgisi", en: "Company details")): \(companyInfo ?? unspecified)",
            in: CGRect(x: rect.minX + 10, y: rect.minY + 5, width: 260, height: 37),
            baseFont: .systemFont(ofSize: 7.4, weight: .semibold),
            minimumFontSize: 5.8,
            color: .rdPDFSlate
        )
        drawFittingText(
            "\(copy(language: language, tr: "Hazırlayan", en: "Prepared by")): \(prepared)\n\(copy(language: language, tr: "Ünvan", en: "Title")): \(title)\n\(copy(language: language, tr: "Belge No", en: "Certificate no.")): \(certificate)",
            in: CGRect(x: rect.minX + 294, y: rect.minY + 5, width: 220, height: 37),
            baseFont: .systemFont(ofSize: 7.4, weight: .semibold),
            minimumFontSize: 5.8,
            color: .rdPDFSlate
        )
        drawFittingText(
            "\(copy(language: language, tr: "Tarih", en: "Date")): \(formattedDate(analysis.createdAt, language: language))\n\(copy(language: language, tr: "Doküman No", en: "Document no.")): #\(String(analysis.id.uuidString.prefix(8)).uppercased())",
            in: CGRect(x: rect.minX + 548, y: rect.minY + 9, width: 200, height: 24),
            baseFont: .monospacedSystemFont(ofSize: 7.4, weight: .semibold),
            minimumFontSize: 5.8,
            color: .rdPDFBlack,
            alignment: .right
        )
    }

    private func drawFineKinneyAssessmentTable(input: ReportInput, rows: [AssessmentTableRow]) {
        let x: CGFloat = 32
        let y: CGFloat = 82
        let headerH: CGFloat = 44
        let includesRegulatory = reportIncludesRegulatory(input)
        let widths: [CGFloat] = includesRegulatory
            ? [22, 54, 130, 62, 24, 24, 24, 38, 58, 168, 140, 58]
            : [22, 54, 130, 62, 24, 24, 24, 38, 58, 308, 58]
        let headers: [String]
        if input.options.language == .english {
            headers = ["No.", "Activity\narea", "Hazardous condition / behaviour", "Risk", "P", "F", "S", "R", "Risk\nband", "Control measures", "Due"]
        } else {
            headers = includesRegulatory
                ? ["No", "Faaliyet\nAlanı", "Tehlikeli durum / davranış", "Risk", "O", "F", "Ş", "R", "Risk\nderecesi", "Önlem / kontrol tedbirleri", "Mevzuat", "Termin"]
                : ["No", "Faaliyet\nAlanı", "Tehlikeli durum / davranış", "Risk", "O", "F", "Ş", "R", "Risk\nderecesi", "Önlem / kontrol tedbirleri", "Termin"]
        }

        drawGridHeader(x: x, y: y, widths: widths, height: headerH, headers: headers, fill: .rdPDFTableBlue)

        var rowY = y + headerH
        for row in rows {
            let finding = row.finding
            let band = finding.fkBand
            let values = fineKinneyAssessmentValues(input: input, finding: finding, ordinal: row.ordinal)
            drawAssessmentRow(x: x, y: rowY, widths: widths, height: row.height, values: values, band: band.level, scoreColumn: 7, bandColumn: 8)
            rowY += row.height
        }
    }

    private func drawMatrixAssessmentTable(input: ReportInput, rows: [AssessmentTableRow]) {
        let x: CGFloat = 32
        let y: CGFloat = 82
        let headerH: CGFloat = 44
        let includesRegulatory = reportIncludesRegulatory(input)
        let widths: [CGFloat] = includesRegulatory
            ? [22, 58, 132, 66, 26, 26, 38, 56, 170, 130, 54]
            : [22, 58, 132, 66, 26, 26, 38, 56, 300, 54]
        let headers: [String]
        if input.options.language == .english {
            headers = ["No.", "Activity\narea", "Hazardous condition / behaviour", "Risk", "P", "S", "R", "Risk\nband", "Control measures", "Due"]
        } else {
            headers = includesRegulatory
                ? ["No", "Faaliyet\nAlanı", "Tehlikeli durum / davranış", "Risk", "O", "Ş", "R", "Risk\nderecesi", "Önlem / kontrol tedbirleri", "Mevzuat", "Termin"]
                : ["No", "Faaliyet\nAlanı", "Tehlikeli durum / davranış", "Risk", "O", "Ş", "R", "Risk\nderecesi", "Önlem / kontrol tedbirleri", "Termin"]
        }

        drawGridHeader(x: x, y: y, widths: widths, height: headerH, headers: headers, fill: .rdPDFTableBlue)

        var rowY = y + headerH
        for row in rows {
            let finding = row.finding
            let band = finding.m5Band
            let values = matrixAssessmentValues(input: input, finding: finding, ordinal: row.ordinal)
            drawAssessmentRow(x: x, y: rowY, widths: widths, height: row.height, values: values, band: band.level, scoreColumn: 6, bandColumn: 7)
            rowY += row.height
        }
    }

    private func fineKinneyAssessmentValues(input: ReportInput, finding: Finding, ordinal: Int) -> [String] {
        var values = [
            "\(ordinal)",
            canvasLabel(input.bundle.analysis.canvas, language: input.options.language),
            finding.displayTitle + "\n" + finding.description,
            finding.category,
            scoreText(finding.fk.probability, language: input.options.language),
            scoreText(finding.fk.frequency, language: input.options.language),
            scoreText(finding.fk.severity, language: input.options.language),
            scoreText(finding.fkScore, language: input.options.language),
            riskBandLabel(finding.fkBand.level, method: .fineKinney, score: finding.fkScore, language: input.options.language),
            actionTextWithRootCause(for: finding, language: input.options.language),
        ]
        if reportIncludesRegulatory(input) {
            values.append(finding.references)
        }
        values.append(suggestedTerm(for: finding.fkBand.level, language: input.options.language))
        return values
    }

    private func matrixAssessmentValues(input: ReportInput, finding: Finding, ordinal: Int) -> [String] {
        var values = [
            "\(ordinal)",
            canvasLabel(input.bundle.analysis.canvas, language: input.options.language),
            finding.displayTitle + "\n" + finding.description,
            finding.category,
            "\(finding.m5.probability)",
            "\(finding.m5.severity)",
            "\(finding.m5Score)",
            riskBandLabel(finding.m5Band.level, method: .matrix5x5, score: Double(finding.m5Score), language: input.options.language),
            actionTextWithRootCause(for: finding, language: input.options.language),
        ]
        if reportIncludesRegulatory(input) {
            values.append(finding.references)
        }
        values.append(suggestedTerm(for: finding.m5Band.level, language: input.options.language))
        return values
    }

    private func assessmentRowHeight(input: ReportInput, finding: Finding, ordinal: Int) -> CGFloat {
        let isFineKinney = input.options.method == .fineKinney
        let includesRegulatory = reportIncludesRegulatory(input)
        let widths: [CGFloat]
        if isFineKinney {
            widths = includesRegulatory
                ? [22, 54, 130, 62, 24, 24, 24, 38, 58, 168, 140, 58]
                : [22, 54, 130, 62, 24, 24, 24, 38, 58, 308, 58]
        } else {
            widths = includesRegulatory
                ? [22, 58, 132, 66, 26, 26, 38, 56, 170, 130, 54]
                : [22, 58, 132, 66, 26, 26, 38, 56, 300, 54]
        }
        let values = isFineKinney
            ? fineKinneyAssessmentValues(input: input, finding: finding, ordinal: ordinal)
            : matrixAssessmentValues(input: input, finding: finding, ordinal: ordinal)
        let scoreColumn = isFineKinney ? 7 : 6
        let bandColumn = isFineKinney ? 8 : 7
        let minHeight: CGFloat = isFineKinney ? 92 : 84

        var requiredHeight = minHeight
        for (idx, value) in values.enumerated() {
            let font: UIFont
            if idx == scoreColumn {
                font = .systemFont(ofSize: 10, weight: .bold)
            } else if idx == bandColumn || idx == 0 {
                font = .systemFont(ofSize: 7, weight: .bold)
            } else {
                font = .systemFont(ofSize: 6.8)
            }
            let alignment: NSTextAlignment = idx <= 1 || idx == scoreColumn || idx == bandColumn ? .center : .left
            let measured = measuredTextHeight(value, width: max(8, widths[idx] - 8), font: font, alignment: alignment)
            requiredHeight = max(requiredHeight, measured + 18)
        }

        return ceil(requiredHeight)
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
            let alignment: NSTextAlignment = idx <= 1 || idx == scoreColumn || idx == bandColumn ? .center : .left
            let textRect = CGRect(x: currentX + 4, y: y + 7, width: width - 8, height: height - 14)
            if idx == scoreColumn || idx == bandColumn || idx == 0 {
                drawText(values[safe: idx] ?? "", in: textRect, font: font, color: textColor, alignment: alignment)
            } else {
                drawFittingText(
                    values[safe: idx] ?? "",
                    in: textRect,
                    baseFont: font,
                    minimumFontSize: 5.4,
                    color: textColor,
                    alignment: alignment
                )
            }
            currentX += width
        }
    }

    private func drawTableHeader(y: CGFloat, language: RDLanguage) {
        let x: CGFloat = 42
        drawText("#", in: CGRect(x: x, y: y, width: 28, height: 18), font: .systemFont(ofSize: 9, weight: .bold), color: .rdPDFSlate)
        drawText(copy(language: language, tr: "RİSK / KANIT", en: "RISK / EVIDENCE"), in: CGRect(x: x + 36, y: y, width: 300, height: 18), font: .systemFont(ofSize: 9, weight: .bold), color: .rdPDFSlate)
        drawText(copy(language: language, tr: "SKOR", en: "SCORE"), in: CGRect(x: x + 372, y: y, width: 70, height: 18), font: .systemFont(ofSize: 9, weight: .bold), color: .rdPDFSlate)
        drawText(copy(language: language, tr: "ÖNLEM / KONTROL TEDBİRLERİ", en: "ACTION / CONTROL MEASURES"), in: CGRect(x: x + 462, y: y, width: 290, height: 18), font: .systemFont(ofSize: 8.2, weight: .bold), color: .rdPDFSlate)
        UIColor.rdPDFLine.setFill()
        UIBezierPath(rect: CGRect(x: 42, y: y + 22, width: 758, height: 1)).fill()
    }

    private func actionTextWithRootCause(for finding: Finding, language: RDLanguage) -> String {
        let rootCause = finding.rootCause.trimmingCharacters(in: .whitespacesAndNewlines)
        let measures = finding.measures.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let measuresText: String
        if measures.isEmpty {
            let action = finding.action.trimmingCharacters(in: .whitespacesAndNewlines)
            measuresText = action.isEmpty
                ? ""
                : "\(copy(language: language, tr: "Düzeltici Önlem", en: "Corrective action")): \(action)"
        } else {
            measuresText = measures.map { measure in
                let title: String
                switch measure.kind {
                case .corrective:
                    title = copy(language: language, tr: "Düzeltici Önlem", en: "Corrective action")
                case .preventive:
                    title = copy(language: language, tr: "Önleyici Kontrol", en: "Preventive control")
                case .unknown:
                    title = measure.title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                        ?? copy(language: language, tr: "Kontrol Tedbiri", en: "Control measure")
                }
                return "\(title): \(measure.text)"
            }.joined(separator: "\n")
        }
        guard !rootCause.isEmpty else { return measuresText }
        return "\(measuresText)\n\n\(copy(language: language, tr: "Kök neden", en: "Root cause")): \(rootCause)"
    }

    private func standardFindingRowHeight(for finding: Finding, language: RDLanguage) -> CGFloat {
        let minHeight: CGFloat = 82
        let titleHeight = max(
            18,
            measuredTextHeight(
                finding.displayTitle,
                width: 302,
                font: .systemFont(ofSize: 12, weight: .bold),
                alignment: .left
            )
        )
        let descriptionHeight = measuredTextHeight(
            finding.description,
            width: 302,
            font: .systemFont(ofSize: 9),
            alignment: .left
        )
        let actionHeight = measuredTextHeight(
            actionTextWithRootCause(for: finding, language: language),
            width: 296,
            font: .systemFont(ofSize: 10),
            alignment: .left
        )

        let riskColumnHeight = 10 + titleHeight + 7 + descriptionHeight + 12
        let actionColumnHeight = 24 + actionHeight
        return ceil(max(minHeight, riskColumnHeight, actionColumnHeight))
    }

    private func drawFindingRow(
        ordinal: Int,
        finding: Finding,
        method: RiskMethod,
        language: RDLanguage,
        y: CGFloat,
        height: CGFloat
    ) {
        let x: CGFloat = 42
        let rowRect = CGRect(x: x, y: y, width: 758, height: height)
        roundedStroke(rowRect, radius: 10, stroke: .rdPDFLine, fill: .white)

        drawText("\(ordinal)", in: CGRect(x: x + 12, y: y + 12, width: 24, height: 20), font: .monospacedSystemFont(ofSize: 12, weight: .bold), color: .rdPDFBlack)

        let titleHeight = max(
            18,
            measuredTextHeight(
                finding.displayTitle,
                width: 302,
                font: .systemFont(ofSize: 12, weight: .bold),
                alignment: .left
            )
        )
        let descriptionY = y + 10 + titleHeight + 7
        drawFittingText(
            finding.displayTitle,
            in: CGRect(x: x + 48, y: y + 9, width: 302, height: titleHeight),
            baseFont: .systemFont(ofSize: 12, weight: .bold),
            minimumFontSize: 9.2,
            color: .rdPDFBlack
        )
        drawFittingText(
            finding.description,
            in: CGRect(x: x + 48, y: descriptionY, width: 302, height: max(18, y + height - descriptionY - 12)),
            baseFont: .systemFont(ofSize: 9),
            minimumFontSize: 7.2,
            color: .rdPDFSlate
        )

        let band = finding.band(for: method)
        roundedFill(CGRect(x: x + 370, y: y + 14, width: 70, height: 34), radius: 8, color: band.level.pdfColor)
        let score = finding.score(for: method)
        drawText(scoreText(score, language: language), in: CGRect(x: x + 370, y: y + 19, width: 70, height: 20), font: .monospacedSystemFont(ofSize: 16, weight: .bold), color: .white, alignment: .center)
        drawText(riskBandLabel(band.level, method: method, score: score, language: language), in: CGRect(x: x + 360, y: y + 52, width: 90, height: 14), font: .systemFont(ofSize: 8, weight: .bold), color: band.level.pdfColor, alignment: .center)

        drawFittingText(
            actionTextWithRootCause(for: finding, language: language),
            in: CGRect(x: x + 462, y: y + 12, width: 296, height: max(18, height - 24)),
            baseFont: .systemFont(ofSize: 10),
            minimumFontSize: 7.5,
            color: .rdPDFBlack
        )
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

    private func drawCoverImages(_ images: [UIImage], in rect: CGRect) {
        let visibleImages = Array(images.prefix(5))
        guard visibleImages.count > 1 else {
            if let image = visibleImages.first {
                drawCoverImage(image, in: rect, cornerRadius: 14)
            }
            return
        }

        roundedFill(rect, radius: 14, color: .rdPDFFog)
        let gap: CGFloat = 6
        let columns = visibleImages.count <= 2 ? visibleImages.count : 3
        let rows = Int(ceil(Double(visibleImages.count) / Double(columns)))
        let cellWidth = (rect.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
        let cellHeight = (rect.height - CGFloat(rows - 1) * gap) / CGFloat(rows)

        for (index, image) in visibleImages.enumerated() {
            let column = index % columns
            let row = index / columns
            let cellRect = CGRect(
                x: rect.minX + CGFloat(column) * (cellWidth + gap),
                y: rect.minY + CGFloat(row) * (cellHeight + gap),
                width: cellWidth,
                height: cellHeight
            )
            drawCoverImage(image, in: cellRect, cornerRadius: 10)
            roundedStroke(
                cellRect,
                radius: 10,
                stroke: UIColor.white.withAlphaComponent(0.82),
                fill: .clear,
                lineWidth: 1
            )
            drawText(
                "\(index + 1)",
                in: CGRect(x: cellRect.minX + 6, y: cellRect.minY + 5, width: 22, height: 14),
                font: .monospacedSystemFont(ofSize: 9, weight: .bold),
                color: .white,
                alignment: .center
            )
        }
    }

    private func drawCoverImage(_ image: UIImage, in rect: CGRect, cornerRadius: CGFloat) {
        let rasterized = image.pdfCoverRasterized(
            filling: rect.size,
            scale: Self.coverImageRasterScale
        )
        drawImage(rasterized, in: rect, cornerRadius: cornerRadius)
    }

    private func drawPlaceholder(in rect: CGRect, text: String) {
        roundedFill(rect, radius: 14, color: .rdPDFFog)
        drawText(text.uppercased(), in: rect.insetBy(dx: 12, dy: rect.height / 2 - 8), font: .systemFont(ofSize: 10, weight: .bold), color: .rdPDFSlate, alignment: .center)
    }

    private func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
        guard let cgContext = UIGraphicsGetCurrentContext() else { return }
        cgContext.saveGState()
        UIBezierPath(rect: rect).addClip()
        defer { cgContext.restoreGState() }

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

    private func drawFittingText(
        _ text: String,
        in rect: CGRect,
        baseFont: UIFont,
        minimumFontSize: CGFloat,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        var size = baseFont.pointSize
        while size > minimumFontSize {
            let font = UIFont(descriptor: baseFont.fontDescriptor, size: size)
            if measuredTextHeight(text, width: rect.width, font: font, alignment: alignment) <= rect.height {
                drawText(text, in: rect, font: font, color: color, alignment: alignment)
                return
            }
            size -= 0.4
        }
        drawText(text, in: rect, font: UIFont(descriptor: baseFont.fontDescriptor, size: minimumFontSize), color: color, alignment: alignment)
    }

    private func measuredTextHeight(_ text: String, width: CGFloat, font: UIFont, alignment: NSTextAlignment) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let rect = NSString(string: text).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraph,
            ],
            context: nil
        )
        return ceil(rect.height)
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

    private func formattedDate(_ raw: String?, language: RDLanguage = .turkish) -> String {
        guard let raw else {
            return copy(language: language, tr: "Tarih yok", en: "Date unavailable")
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func canvasLabel(_ id: String, language: RDLanguage) -> String {
        if language == .turkish {
            return AnalysisCanvas.all.first(where: { $0.id == id })?.title ?? id.capitalized
        }
        let englishLabels: [String: String] = [
            "general": "General",
            "ppe": "PPE",
            "machine": "Machinery",
            "warning_signs": "Warning signs",
            "electrical": "Electrical",
            "sector": "Sector-specific",
            "fire": "Fire",
            "ergonomics": "Special equipment",
            "environment_measurement": "Workplace measurements",
            "explosion": "Explosion",
            "environment": "Environment",
            "legislation": "Regulatory review",
            "working_at_height": "Working at height",
            "mobile_equipment": "Mobile equipment",
            "general_premium": "General premium",
            "construction_machinery": "Construction machinery",
        ]
        return englishLabels[id] ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func scoreText(_ value: Double, language: RDLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = value == floor(value) ? 0 : 1
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func matrixColor(_ score: Int) -> UIColor {
        switch score {
        case 20...: return .rdPDFCritical
        case 10...19: return .rdPDFHigh
        case 5...9: return .rdPDFMedium
        default: return .rdPDFGreen
        }
    }

    private func suggestedTerm(for level: RiskLevel, language: RDLanguage) -> String {
        switch (language, level) {
        case (.turkish, .critical): return "Acil / 1-3 gün"
        case (.turkish, .high): return "7 gün"
        case (.turkish, .medium): return "15 gün"
        case (.turkish, .low): return "30 gün"
        case (.turkish, .unknown): return "Değerlendirilecek"
        case (.english, .critical): return "Urgent / 1–3 days"
        case (.english, .high): return "7 days"
        case (.english, .medium): return "15 days"
        case (.english, .low): return "30 days"
        case (.english, .unknown): return "To be assessed"
        }
    }

    private func reportIncludesRegulatory(_ input: ReportInput) -> Bool {
        input.options.language == .turkish
            && input.bundle.analysis.supportsStructuredRegulatoryReferences
    }

    private func copy(language: RDLanguage, tr: String, en: String) -> String {
        language == .english ? en : tr
    }

    private func findingCountText(_ count: Int, language: RDLanguage) -> String {
        if language == .english {
            return count == 1 ? "1 finding" : "\(count) findings"
        }
        return "\(count) bulgu"
    }

    private func methodName(_ method: RiskMethod, language: RDLanguage) -> String {
        switch (language, method) {
        case (.english, .fineKinney): return "Fine-Kinney"
        case (.english, .matrix5x5): return "5×5 L-Type Matrix"
        case (.turkish, .fineKinney): return "Fine-Kinney"
        case (.turkish, .matrix5x5): return "5×5 L-Tipi Matris"
        }
    }

    private func methodFormula(_ method: RiskMethod, language: RDLanguage) -> String {
        switch (language, method) {
        case (.english, .fineKinney): return "P × F × S"
        case (.english, .matrix5x5): return "P × S"
        case (.turkish, .fineKinney): return "O × F × Ş"
        case (.turkish, .matrix5x5): return "O × Ş"
        }
    }

    private func riskLevelLabel(_ level: RiskLevel, language: RDLanguage) -> String {
        guard language == .english else { return level.label }
        switch level {
        case .critical: return "Critical"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .unknown: return "Unknown"
        }
    }

    private func riskBandLabel(
        _ level: RiskLevel,
        method: RiskMethod,
        score: Double,
        language: RDLanguage
    ) -> String {
        guard language == .english else {
            return method == .fineKinney
                ? RiskBands.fineKinney(score).label
                : RiskBands.matrix5x5(Int(score)).label
        }
        switch level {
        case .critical: return "Intolerable"
        case .high: return "High risk"
        case .medium: return "Significant risk"
        case .low: return score <= (method == .fineKinney ? 20 : 2) ? "Minor risk" : "Low risk"
        case .unknown: return "Unassessed"
        }
    }

    private func reportDisclaimer(language: RDLanguage) -> String {
        copy(
            language: language,
            tr: "Bu rapor saha güvenliği değerlendirmesini destekler; yetkili kişi değerlendirmesinin yerine geçmez ve mevzuata uygunluk kararı oluşturmaz.",
            en: "This report supports a safety review; it does not replace assessment by a competent person or determine legal compliance."
        )
    }
}

#if DEBUG
extension PDFReportService {
    static func runEnglishExtractionSelfTest() throws {
        let analysisJSON = """
        {
          "id": "00000000-0000-0000-0000-00000000e501",
          "user_id": "00000000-0000-0000-0000-00000000e502",
          "title": "Warehouse inspection",
          "kind": "photo",
          "canvas": "general",
          "status": "completed",
          "ai_summary": "One finding requires corrective action.",
          "finding_count": 1,
          "created_at": "2026-07-30T12:00:00Z",
          "analysis_sector": "logistics_warehouse",
          "analysis_sector_source": "user_selected",
          "analysis_sector_prompt_version": "active-sector-v1",
          "output_language": "en",
          "output_locale": "en-GB",
          "work_jurisdiction_country": "ZZ",
          "safety_profile_id": "english_international_generic_v1",
          "safety_profile_version": 1,
          "localization_snapshot": {
            "schema_version": 1,
            "output_language": "en",
            "output_locale": "en-GB",
            "work_jurisdiction_country": "ZZ",
            "work_jurisdiction_region": null,
            "safety_profile_id": "english_international_generic_v1",
            "safety_profile_version": 1,
            "structured_regulatory_references_enabled": false
          }
        }
        """
        let analysis = try JSONDecoder().decode(
            AnalysisRow.self,
            from: Data(analysisJSON.utf8)
        )
        let finding = Finding(
            id: 1,
            title: "Unprotected loading edge",
            category: "Fall hazard",
            confidence: 0.96,
            description: "The loading edge has no physical barrier.",
            action: "Install a suitable barrier before work resumes.",
            measures: [
                FindingMeasure(
                    kind: .corrective,
                    title: "Corrective action",
                    text: "Install a suitable barrier before work resumes."
                ),
                FindingMeasure(
                    kind: .preventive,
                    title: "Preventive control",
                    text: "Add the barrier to the pre-use inspection."
                ),
            ],
            references: "User-provided internal procedure",
            rootCause: "The pre-use inspection did not cover loading edges.",
            fk: FineKinneyParams(probability: 6, frequency: 3, severity: 15),
            m5: FiveByFiveParams(probability: 4, severity: 5)
        )
        let bundle = AnalysisResultBundle(
            analysis: analysis,
            findings: [],
            photos: []
        )
        let baseOptions = PDFReportOptions(
            kind: .standard,
            method: .fineKinney,
            preparedBy: "Test Operator",
            preparedTitle: "Safety professional",
            certificateNumber: "",
            companyName: "Test Company",
            companyInfo: "",
            companyID: nil,
            language: .english
        )

        var extractedDocuments: [String] = []
        for kind in [PDFReportKind.standard, .riskAnalysis] {
            var options = baseOptions
            options.kind = kind
            let url = try PDFReportService.shared.generate(
                input: ReportInput(
                    bundle: bundle,
                    findings: [finding],
                    profile: nil,
                    images: [],
                    companyLogo: nil,
                    options: options
                )
            )
            guard let document = PDFDocument(url: url), let text = document.string else {
                throw ReportExtractionSelfTestError.pdfTextUnavailable(kind.rawValue)
            }
            extractedDocuments.append(text)
        }

        let extracted = extractedDocuments.joined(separator: "\n")
        let required = [
            "Finding Summary",
            "RISK / EVIDENCE",
            "ACTION / CONTROL MEASURES",
            "FINE-KINNEY METHOD REFERENCE TABLE",
            "HAZARD AND RISK ASSESSMENT FORM",
            "Root cause",
            "This report supports a safety review",
        ]
        for marker in required where !extracted.localizedCaseInsensitiveContains(marker) {
            throw ReportExtractionSelfTestError.requiredMarkerMissing(marker)
        }

        let forbidden = [
            "Mevzuat",
            "İSG Uzmanı",
            "OSGB",
            "ÇSGB",
            "6331",
            "mevzuata uygundur",
            "yasal uygunluk",
        ]
        for marker in forbidden where extracted.localizedCaseInsensitiveContains(marker) {
            throw ReportExtractionSelfTestError.forbiddenMarkerFound(marker)
        }
    }

    private enum ReportExtractionSelfTestError: LocalizedError {
        case pdfTextUnavailable(String)
        case requiredMarkerMissing(String)
        case forbiddenMarkerFound(String)

        var errorDescription: String? {
            switch self {
            case .pdfTextUnavailable(let kind):
                return "PDF text extraction failed for \(kind)."
            case .requiredMarkerMissing(let marker):
                return "Required PDF marker missing: \(marker)"
            case .forbiddenMarkerFound(let marker):
                return "Forbidden PDF marker found: \(marker)"
            }
        }
    }
}
#endif

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
    func pdfCoverRasterized(filling targetSize: CGSize, scale: CGFloat) -> UIImage {
        guard targetSize.width > 0, targetSize.height > 0 else { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = max(1, scale)
        format.opaque = true
        let targetRect = CGRect(origin: .zero, size: targetSize)
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: targetRect).fill()
            draw(in: aspectFillRect(in: targetRect))
        }
    }

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
