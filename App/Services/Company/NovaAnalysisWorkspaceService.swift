import Foundation
import UIKit

/// Composition between the İSGADA analysis screens and the services the product
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

    /// One page of completed analyses, newest first, with the company name
    /// resolved from the pilot list. An id we cannot name stays unnamed
    /// rather than being shown as if it had no company. `hasMore` is the
    /// server's own signal (a full page came back), never a guess from a
    /// count this call never asked for.
    static func summaries(identity: NovaSessionIdentity, method: RiskMethod,
                          limit: Int = 50, offset: Int = 0) async throws -> (rows: [NovaAnalysisSummary], hasMore: Bool) {
        let rows = try await AnalysisService.shared.listRecent(limit: limit, offset: offset)
        let companies = (try? await loadNovaPilotOverview(identity: identity)) ?? []
        let names = Dictionary(uniqueKeysWithValues: companies.map { ($0.id, $0.name) })
        let summaries = rows.map { row in
            NovaAnalysisSummary(id: row.id, title: row.title, createdOn: day(row.createdAt),
                companyName: row.companyID.flatMap { names[$0] }
                    ?? row.companyID.map { _ in RDLocalization.string("localizable.nova.analysis.company.unnamed",
                        table: .localizable, fallback: "Bağlı firma") },
                findingCount: row.findingCount,
                photoCount: row.photoCount ?? 0,
                sectorLabel: row.analysisSectorID?.label(),
                // The band of the expert's own method, never the other one's.
                highestBand: method == .fineKinney ? row.highestBandFK : row.highestBandM5,
                focusLabel: focusLabel(row.canvas),
                // The list only ever holds finished analyses, so this is the
                // row's own status rather than a guess about one.
                isReviewed: row.status == "completed",
                createdAt: date(row.createdAt))
        }
        return (summaries, rows.count == limit)
    }

    /// The first focus the analysis ran under, as the product names it.
    private static func focusLabel(_ canvas: String) -> String? {
        canvas.split(separator: ",").map(String.init)
            .compactMap { id in AnalysisCanvas.all.first { $0.id == id.trimmingCharacters(in: .whitespaces) }?.title }
            .first
    }

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter.novaFractional.date(from: value)
            ?? ISO8601DateFormatter.novaPlain.date(from: value)
    }

    /// The reports the account produced from photo analyses. The archive is
    /// the product's own; nothing is recomputed from the analyses here.
    static func reports(identity: NovaSessionIdentity, limit: Int = 50) async throws -> [NovaAnalysisReportEntry] {
        let rows = try await AnalysisService.shared.listReports(limit: limit, photoAnalysesOnly: true)
        let companies = (try? await loadNovaPilotOverview(identity: identity)) ?? []
        let names = Dictionary(uniqueKeysWithValues: companies.map { ($0.id, $0.name) })
        return rows.map { row in
            let method = RiskMethod(rawValue: row.method)
            return NovaAnalysisReportEntry(id: row.id, title: row.title, fileName: row.fileName,
                createdOn: day(row.createdAt),
                // A company we cannot name is still a company: the snapshot the
                // archive kept answers it when the pilot list does not.
                companyName: row.companyID.flatMap { names[$0] } ?? row.companySnapshot?.name,
                format: row.format ?? "pdf",
                methodLabel: method?.label ?? row.method,
                kindLabel: row.kind,
                fileSize: row.fileSize,
                analysisID: row.analysisID,
                createdAt: date(row.createdAt))
        }
    }

    /// Today in the expert's own time zone, as an ISO day string. Overdue is a
    /// calendar question, so it is answered once here rather than in a view.
    static func todayISO() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// The first picture of an analysis, for the list. A missing or unreadable
    /// picture is simply absent; the row still renders.
    static func thumbnail(analysisID: UUID) async -> UIImage? {
        guard let path = try? await AnalysisService.shared.firstPhotoPaths(analysisIDs: [analysisID])[analysisID],
              let data = try? await AnalysisService.shared.photoData(path: path) else { return nil }
        return UIImage(data: data)
    }

    /// The picture behind a record. Only a record born from a photo finding has
    /// one: the finding is looked up, then its analysis, then that analysis's
    /// first photo. A manual record simply has none.
    static func recordThumbnail(_ entry: NovaNonconformityEntry) async -> UIImage? {
        guard entry.row.camefromFinding, let reference = entry.row.source_ref,
              let finding = UUID(uuidString: reference) else { return nil }
        struct Row: Decodable { let analysis_id: UUID }
        guard let data = try? await SupabaseService.shared.client.from("findings")
            .select("analysis_id").eq("id", value: finding.uuidString).limit(1).execute().data,
              let rows = try? JSONDecoder().decode([Row].self, from: data),
              let analysis = rows.first?.analysis_id else { return nil }
        return await thumbnail(analysisID: analysis)
    }

    /// Every picture of one analysis, in order.
    static func photos(analysisID: UUID) async -> [UIImage] {
        guard let bundle = try? await AnalysisService.shared.result(analysisID: analysisID) else { return [] }
        return await photos(bundle)
    }

    static func remove(analysisID: UUID, findingID: UUID) async throws {
        _ = try await AnalysisService.shared.deleteFinding(analysisID: analysisID, findingID: findingID,
            expectedVersion: nil)
    }

    static func react(analysisID: UUID, itemID: UUID, section: NovaAnalysisSectionKind,
                      reaction: NovaAnalysisReaction) async throws {
        guard let target = AnalysisResultSectionID(rawValue: section.rawValue) else { return }
        let value: AnalysisItemReaction = reaction == .like ? .like : reaction == .dislike ? .dislike : .none
        try await AnalysisResultHubService.shared.setFeedback(analysisID: analysisID, language: .current,
            section: target, itemID: itemID, reaction: value)
    }

    /// The record board reads every company the account can still read, one at
    /// a time, re-checking the session between calls exactly as the company
    /// loader does. A company that fails its own check is left out, not faked.
    static func board(identity: NovaSessionIdentity) async throws -> [NovaNonconformityEntry] {
        func check() throws {
            try Task.checkCancellation()
            guard novaCurrentSessionIdentity() == identity else { throw NovaNonconformityFailure.denied }
        }
        try check()
        let companies = try await loadNovaPilotOverview(identity: identity).filter { !$0.is_archived }
        var result: [NovaNonconformityEntry] = []
        for company in companies {
            try check()
            guard let places = try? await read(company: company.id, kind: "workplaces", decoding: WorkplaceEnvelope.self),
                  let list = try? await read(company: company.id, kind: "list", decoding: ListEnvelope.self) else { continue }
            try check()
            let names = Dictionary(uniqueKeysWithValues: places.rows.map { ($0.id, $0.name) })
            result.append(contentsOf: list.rows.map { row in
                .init(row: row, companyID: company.id, companyName: company.name,
                      workplaceName: names[row.workplace_id])
            })
        }
        // Newest first, and stable when two records share a day.
        return result.sorted {
            $0.row.opened_on == $1.row.opened_on
                ? $0.row.title.localizedCaseInsensitiveCompare($1.row.title) == .orderedAscending
                : $0.row.opened_on > $1.row.opened_on
        }
    }

    private struct ListEnvelope: Decodable { let rows: [NovaNonconformityRow] }
    private struct WorkplaceEnvelope: Decodable { let rows: [NovaNonconformityWorkplace] }

    private static func read<T: Decodable>(company: UUID, kind: String, decoding: T.Type) async throws -> T {
        let data = try await SupabaseService.shared.client.rpc("isg_nonconformity_read_v1", params: [
            "p_company": PersonnelRPCValue.id(company), "p_kind": .string(kind),
            "p_query": .null, "p_state": .null, "p_after": .null, "p_id": .null]).execute().data
        return try JSONDecoder().decode(T.self, from: data)
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
        let hub = try await AnalysisResultHubService.shared.loadWhenReady(analysisID: analysisID, language: .current)
        // A disabled or incomplete projection is not an empty analysis.
        guard hub.enabled, NovaAnalysisSectionKind.allCases.allSatisfy({ kind in
            hub.sections.contains { $0.id.rawValue == kind.rawValue }
        }) else { throw URLError(.badServerResponse) }
        let companies = (try? await loadNovaPilotOverview(identity: identity)) ?? []
        let name = bundle.analysis.companyID.flatMap { id in companies.first { $0.id == id }?.name }
        let sections = self.sections(hub: hub, bundle: bundle)
        let focuses = bundle.analysis.canvas.split(separator: ",").map(String.init)
            .compactMap { id in AnalysisCanvas.all.first { $0.id == id.trimmingCharacters(in: .whitespaces) }?.title }
        return .init(analysisID: analysisID, title: bundle.analysis.title, createdOn: day(bundle.analysis.createdAt),
            methodLabel: methodLabel, method: method == .fineKinney ? .fineKinney : .matrix5x5,
            companyID: bundle.analysis.companyID, companyName: name, sections: sections,
            isProjectionMissing: false,
            photoCount: bundle.photos.count,
            sectorLabel: bundle.analysis.analysisSectorID?.label(),
            focusLabels: focuses)
    }

    /// The hub is the product's own projection. When it is not available the
    /// scored findings still come from the analysis itself, and the three
    /// judgement sections are shown as empty rather than invented.
    private static func sections(hub: AnalysisResultHubResponse?, bundle: AnalysisResultBundle) -> [NovaAnalysisSection] {
        NovaAnalysisSectionKind.allCases.map { kind in
            if let section = hub?.sections.first(where: { $0.id.rawValue == kind.rawValue }) {
                return .init(kind: kind, items: section.items.enumerated().map { at, item in
                    self.item(item, at: at, kind: kind)
                }, isTeaser: section.access == .teaser)
            }
            guard kind == .riskAnalysis else { return .init(kind: kind, items: [], isTeaser: false) }
            return .init(kind: kind, items: bundle.findings.sorted { $0.ordinal < $1.ordinal }.map { finding in
                var item = NovaAnalysisItem(id: finding.id, ordinal: finding.ordinal, title: finding.title,
                    category: finding.category, body: finding.description ?? "",
                    measure: finding.recommendedAction, references: finding.referencesText)
                item.rootCause = finding.rootCauseText
                item.measures = measures(finding.recommendedMeasures)
                item.photoIndices = finding.sourcePhotoIndices ?? []
                item.fineKinney = fineKinney(band: finding.fkBand, score: finding.fkScore,
                    probability: finding.fkProbability, frequency: finding.fkFrequency, severity: finding.fkSeverity)
                item.matrix = matrix(band: finding.m5Band, score: finding.m5Score,
                    probability: finding.m5Probability, severity: finding.m5Severity)
                return item
            }, isTeaser: false)
        }
    }

    private static func item(_ value: AnalysisResultHubItem, at index: Int,
                             kind: NovaAnalysisSectionKind) -> NovaAnalysisItem {
        var item = NovaAnalysisItem(id: value.id, ordinal: value.ordinal ?? value.displayOrder ?? (index + 1),
            title: value.displayTitle, category: value.categoryLabel ?? value.category,
            body: value.displayBody.isEmpty ? (value.text ?? "") : value.displayBody,
            measure: value.recommendedAction ?? value.recommendationText,
            references: value.referencesText ?? value.referenceText)
        item.rootCause = value.rootCauseText
        item.measures = measures(value.recommendedMeasures)
        item.audience = value.audienceLabel
        item.durationLabel = value.durationLabel
        item.durationValue = value.durationValue
        item.durationNote = value.durationNote
        item.photoIndices = value.sourcePhotoIndices ?? []
        item.reaction = reaction(value.userReaction)
        // Only the risk-analysis section carries a band. The judgement sections
        // arrive unscored and must not be shown as if they had one.
        if kind.isScored {
            item.fineKinney = fineKinney(band: value.fkBand, score: value.fkScore,
                probability: value.fkProbability, frequency: value.fkFrequency, severity: value.fkSeverity)
            item.matrix = matrix(band: value.m5Band, score: value.m5Score,
                probability: value.m5Probability, severity: value.m5Severity)
        }
        return item
    }

    private static func reaction(_ value: AnalysisItemReaction?) -> NovaAnalysisReaction {
        switch value {
        case .like: return .like
        case .dislike: return .dislike
        default: return .none
        }
    }

    private static func measures(_ values: [FindingMeasure]?) -> [NovaAnalysisMeasure] {
        (values ?? []).map { measure in
            .init(id: measure.id, title: measure.displayTitle, text: measure.text,
                  isPreventive: measure.kind == .preventive)
        }
    }

    /// The factors are shown only when the analysis recorded all of them, so a
    /// product the screen prints can never be missing one of its terms.
    private static func fineKinney(band: String?, score: Double?, probability: Double?,
                                   frequency: Double?, severity: Double?) -> NovaAnalysisScore? {
        guard band != nil || score != nil else { return nil }
        var factors: [NovaAnalysisScoreFactor] = []
        if let probability, let frequency, let severity {
            factors = [.init(label: RDLocalization.string("localizable.nova.risk.factor.probability", table: .localizable, fallback: "O"), value: probability),
                       .init(label: RDLocalization.string("localizable.nova.risk.factor.frequency", table: .localizable, fallback: "F"), value: frequency),
                       .init(label: RDLocalization.string("localizable.nova.risk.factor.severity", table: .localizable, fallback: "Ş"), value: severity)]
        }
        return .init(band: band, value: score, factors: factors)
    }

    private static func matrix(band: String?, score: Int?, probability: Int?, severity: Int?) -> NovaAnalysisScore? {
        guard band != nil || score != nil else { return nil }
        var factors: [NovaAnalysisScoreFactor] = []
        if let probability, let severity {
            factors = [.init(label: RDLocalization.string("localizable.nova.risk.factor.probability", table: .localizable, fallback: "O"), value: Double(probability)),
                       .init(label: RDLocalization.string("localizable.nova.risk.factor.severity", table: .localizable, fallback: "Ş"), value: Double(severity))]
        }
        return .init(band: band, value: score.map(Double.init), factors: factors)
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
