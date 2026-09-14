import Foundation
import UIKit

/// Composition between the NOVA analysis screens and the services the product
/// already ships. Nothing here re-implements the analysis pipeline, the report
/// renderer or the nonconformity boundary; it only carries them.
@MainActor
enum NovaAnalysisWorkspace {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "d MMMM yyyy · HH:mm"
        return formatter
    }()

    /// Supabase timestamps arrive with and without fractional seconds; a stamp
    /// neither parser understands is shown as it came rather than as a guess.
    static func day(_ value: String?) -> String {
        guard let value else { return "" }
        guard let date = ISO8601DateFormatter.novaFractional.date(from: value)
            ?? ISO8601DateFormatter.novaPlain.date(from: value) else { return value }
        return dayFormatter.string(from: date)
    }

    /// Every completed analysis on the account, with the company name resolved
    /// from the pilot list. An id we cannot name stays unnamed rather than
    /// being shown as if it had no company.
    static func summaries(identity: NovaSessionIdentity, limit: Int = 30) async throws -> [NovaAnalysisSummary] {
        let rows = try await AnalysisService.shared.listRecent(limit: limit)
        let companies = (try? await loadNovaPilotOverview(identity: identity)) ?? []
        let names = Dictionary(uniqueKeysWithValues: companies.map { ($0.id, $0.name) })
        return rows.map { row in
            NovaAnalysisSummary(id: row.id, title: row.title, createdOn: day(row.createdAt),
                companyName: row.companyID.flatMap { names[$0] }
                    ?? row.companyID.map { _ in RDLocalization.string("localizable.nova.analysis.company.unnamed",
                        table: .localizable, fallback: "Bağlı firma") },
                findingCount: row.findingCount)
        }
    }

    static func companyOptions(identity: NovaSessionIdentity) async throws -> [NovaAnalysisCompanyOption] {
        try await loadNovaPilotOverview(identity: identity).filter { !$0.is_archived }.map { company in
            .init(id: company.id, name: company.name,
                  detail: String(format: RDLocalization.string("localizable.nova.analysis.company.detail", table: .localizable,
                      fallback: "%1$d işyeri · %2$d personel"), company.workplace_count, company.personnel_count),
                  sector: company.sector)
        }
    }

    /// Reads the four sections through the existing result-hub function and the
    /// analysis row itself. A missing projection is reported, never faked.
    static func detail(analysisID: UUID, identity: NovaSessionIdentity,
                       method: RiskMethod, methodLabel: String) async throws -> NovaAnalysisDetailData {
        let bundle = try await AnalysisService.shared.result(analysisID: analysisID)
        let hub = try? await AnalysisResultHubService.shared.loadWhenReady(analysisID: analysisID, language: .current)
        let companies = (try? await loadNovaPilotOverview(identity: identity)) ?? []
        let name = bundle.analysis.companyID.flatMap { id in companies.first { $0.id == id }?.name }
        let sections = self.sections(hub: hub, bundle: bundle, method: method)
        return .init(analysisID: analysisID, title: bundle.analysis.title, createdOn: day(bundle.analysis.createdAt),
            methodLabel: methodLabel, method: method == .fineKinney ? .fineKinney : .matrix5x5,
            companyID: bundle.analysis.companyID, companyName: name, sections: sections,
            isProjectionMissing: hub?.enabled != true)
    }

    /// The hub is the product's own projection. When it is not available the
    /// scored findings still come from the analysis itself, and the three
    /// judgement sections are shown as empty rather than invented.
    private static func sections(hub: AnalysisResultHubResponse?, bundle: AnalysisResultBundle,
                                 method: RiskMethod) -> [NovaAnalysisSection] {
        NovaAnalysisSectionKind.allCases.map { kind in
            if let section = hub?.sections.first(where: { $0.id.rawValue == kind.rawValue }) {
                return .init(kind: kind, items: section.items.enumerated().map { at, item in
                    self.item(item, at: at, kind: kind, method: method)
                }, isTeaser: section.access == .teaser)
            }
            guard kind == .riskAnalysis else { return .init(kind: kind, items: [], isTeaser: false) }
            return .init(kind: kind, items: bundle.findings.sorted { $0.ordinal < $1.ordinal }.map { finding in
                .init(id: finding.id, ordinal: finding.ordinal, title: finding.title, category: finding.category,
                      body: finding.description ?? "", measure: finding.recommendedAction,
                      references: finding.referencesText,
                      band: method == .fineKinney ? finding.fkBand : finding.m5Band,
                      score: method == .fineKinney ? finding.fkScore : finding.m5Score.map(Double.init))
            }, isTeaser: false)
        }
    }

    private static func item(_ value: AnalysisResultHubItem, at index: Int,
                             kind: NovaAnalysisSectionKind, method: RiskMethod) -> NovaAnalysisItem {
        // Only the risk-analysis section carries a band. The judgement sections
        // arrive unscored and must not be shown as if they had one.
        let band = kind.isScored ? (method == .fineKinney ? value.fkBand : value.m5Band) : nil
        let score = kind.isScored ? (method == .fineKinney ? value.fkScore : value.m5Score.map(Double.init)) : nil
        return .init(id: value.id, ordinal: value.ordinal ?? value.displayOrder ?? (index + 1),
            title: value.displayTitle, category: value.categoryLabel ?? value.category,
            body: value.displayBody.isEmpty ? (value.text ?? "") : value.displayBody,
            measure: value.recommendedAction ?? value.recommendationText,
            references: value.referencesText ?? value.referenceText,
            band: band, score: score)
    }

    static func assign(analysisID: UUID, companyID: UUID) async throws {
        try await AnalysisService.shared.assignCompany(to: analysisID, companyID: companyID)
    }

    static func edit(_ change: NovaAnalysisFindingEdit) async throws {
        var patch = FindingMutationPatch()
        patch.title = trimmed(change.title)
        patch.category = trimmed(change.category)
        patch.description = trimmed(change.body)
        patch.recommendedAction = trimmed(change.measure)
        patch.referencesText = trimmed(change.references)
        if change.score.isComplete {
            switch change.score.method {
            case .fineKinney:
                patch.fkProbability = change.score.probability
                patch.fkFrequency = change.score.frequency
                patch.fkSeverity = change.score.severity
            case .matrix5x5:
                patch.m5Probability = change.score.matrixProbability
                patch.m5Severity = change.score.matrixSeverity
            case .none: break
            }
        }
        _ = try await AnalysisService.shared.updateFinding(analysisID: change.analysisID,
            findingID: change.findingID, expectedVersion: nil, patch: patch)
    }

    /// The report shows the photos the analysis was actually run on. A photo we
    /// cannot download is left out; the report is not blocked on it.
    private static func photos(_ bundle: AnalysisResultBundle) async -> [UIImage] {
        var result: [UIImage] = []
        for photo in bundle.photos.sorted(by: { ($0.sequenceIndex ?? 0) < ($1.sequenceIndex ?? 0) }) {
            guard let data = try? await AnalysisService.shared.photoData(path: photo.storagePath),
                  let image = UIImage(data: data) else { continue }
            result.append(image)
        }
        return result
    }

    private static func trimmed(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// PDF goes through the local renderer and the archive call the product
    /// already uses; Excel is rendered by the server function. Both file the
    /// report against the company when one was chosen.
    static func report(_ request: NovaAnalysisReportRequest, profile: UserProfile?, userID: UUID,
                       company: Company?) async throws -> String {
        let requestID = UUID().uuidString
        let supportID = AppErrorMessage.newSupportID()
        let method: RiskMethod = request.method == .fineKinney ? .fineKinney : .matrix5x5
        if request.format == .excel {
            let row = try await AnalysisService.shared.generateExcelReport(analysisID: request.analysisID,
                method: method, language: .current, companyID: request.companyID,
                requestID: requestID, supportID: supportID)
            return row.fileName
        }
        let bundle = try await AnalysisService.shared.result(analysisID: request.analysisID)
        var options = PDFReportOptions()
        options.method = method
        options.language = .current
        options.companyID = request.companyID
        options.companyName = company?.name ?? ""
        let input = PDFReportService.ReportInput(bundle: bundle, findings: bundle.findings.map(\.asFinding),
            profile: profile, images: await photos(bundle), companyLogo: nil, options: options)
        let url = try await PDFReportService.shared.generateAsync(input: input)
        let row = try await AnalysisService.shared.storeReport(userID: userID, bundle: bundle, fileURL: url,
            kind: options.kind, method: method, company: company, requestID: requestID, supportID: supportID)
        return row.fileName
    }
}

extension ISO8601DateFormatter {
    static let novaFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    static let novaPlain = ISO8601DateFormatter()
}
