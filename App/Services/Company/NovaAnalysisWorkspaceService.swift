import Foundation
import UIKit

/// Composition between the İSGADA analysis screens and the services the product
/// already ships. Nothing here re-implements the analysis pipeline, the report
/// renderer or the nonconformity boundary; it only carries them.
@MainActor
enum NovaAnalysisWorkspace {
    /// The original analysis item behind a filed nonconformity. Keeping this
    /// presentation model here lets the board reuse the exact finding sheet
    /// instead of rebuilding a reduced copy of it from the record projection.
    struct RecordFindingPresentation {
        let analysisID: UUID
        let item: NovaAnalysisItem
        let section: NovaAnalysisSectionKind
        let method: NovaRiskMethod
        let photo: UIImage?
        let analysisTitle: String
        let companyName: String
        let createdOn: String
    }

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
        if let backend = try NovaExpertAnalysisBackend.current() {
            return try await backend.summaries(method: method, limit: limit, offset: offset)
        }
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
        if let backend = try NovaExpertAnalysisBackend.current() { return try await backend.reports(limit: limit) }
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
        if NovaExpertTransport.shared.capture()?.access.workspaceID != nil {
            return try? await NovaExpertAnalysisBackend.current()?.photos(analysisID).first
        }
        guard let path = try? await AnalysisService.shared.firstPhotoPaths(analysisIDs: [analysisID])[analysisID],
              let data = try? await AnalysisService.shared.photoData(path: path) else { return nil }
        return UIImage(data: data)
    }

    /// The picture behind a record. Only a record born from a photo finding has
    /// one: the finding is looked up, then its analysis, then that analysis's
    /// first photo. A manual record simply has none.
    static func recordThumbnail(_ entry: NovaNonconformityEntry) async -> UIImage? {
        if NovaExpertTransport.shared.capture()?.access.workspaceID != nil {
            guard let backend = try? NovaExpertAnalysisBackend.current(), let id = try? await backend.source(entry.id) else { return nil }
            return try? await backend.photos(id).first
        }
        guard entry.row.camefromFinding, let reference = entry.row.source_ref,
              let finding = UUID(uuidString: reference) else { return nil }
        struct Row: Decodable { let analysis_id: UUID }
        guard let data = try? await SupabaseService.shared.client.from("findings")
            .select("analysis_id").eq("id", value: finding.uuidString).limit(1).execute().data,
              let rows = try? JSONDecoder().decode([Row].self, from: data),
              let analysis = rows.first?.analysis_id else { return nil }
        return await thumbnail(analysisID: analysis)
    }

    /// Resolves the durable source reference saved on a nonconformity back to
    /// the item shown on the analysis result page. The board can therefore show
    /// the same finding detail UI, including its original photo and factors.
    static func recordFinding(_ entry: NovaNonconformityEntry, identity: NovaSessionIdentity,
                              preferredMethod: RiskMethod) async throws -> RecordFindingPresentation {
        try Task.checkCancellation()
        if let backend = try NovaExpertAnalysisBackend.current() {
            let id = try await backend.source(entry.id)
            let detail = try await backend.detail(id, method: preferredMethod)
            guard let source = detail.sections.lazy.flatMap({ section in section.items.map { (section.kind, $0) } })
                .first(where: { $0.1.id.uuidString.lowercased() == entry.row.source_ref?.lowercased() || entry.row.source_ref?.contains($0.1.id.uuidString.lowercased()) == true }) else { throw NovaNonconformityFailure.unavailable }
            let photos = try await backend.photos(id)
            return .init(analysisID: id, item: source.1, section: source.0,
                method: preferredMethod == .matrix5x5 ? .matrix5x5 : .fineKinney,
                photo: photos.first, analysisTitle: detail.title, companyName: detail.companyName ?? entry.companyName, createdOn: detail.createdOn)
        }
        guard novaCurrentSessionIdentity() == identity,
              entry.row.camefromFinding,
              let reference = entry.row.source_ref,
              let findingID = UUID(uuidString: reference) else {
            throw NovaNonconformityFailure.denied
        }
        struct Link: Decodable { let analysis_id: UUID }
        let raw = try await SupabaseService.shared.client.from("findings")
            .select("analysis_id").eq("id", value: findingID.uuidString).limit(1).execute().data
        guard novaCurrentSessionIdentity() == identity,
              let link = try JSONDecoder().decode([Link].self, from: raw).first else {
            throw NovaNonconformityFailure.unavailable
        }
        let detail = try await self.detail(analysisID: link.analysis_id, identity: identity,
                                           method: preferredMethod, methodLabel: preferredMethod.label)
        var source: (NovaAnalysisSectionKind, NovaAnalysisItem)?
        for section in detail.sections {
            if let item = section.items.first(where: { $0.id == findingID }) {
                source = (section.kind, item)
                break
            }
        }
        guard let (section, item) = source else { throw NovaNonconformityFailure.unavailable }
        let pictures = await photos(analysisID: link.analysis_id)
        let photo: UIImage?
        if let index = item.photoIndices.first, index >= 1, index <= pictures.count {
            photo = pictures[index - 1]
        } else {
            photo = pictures.first
        }
        let method: NovaRiskMethod = preferredMethod == .matrix5x5 ? .matrix5x5 : .fineKinney
        return .init(analysisID: link.analysis_id, item: item, section: section, method: method,
                     photo: photo, analysisTitle: detail.title, companyName: entry.companyName,
                     createdOn: detail.createdOn)
    }

    /// Every picture of one analysis, in order.
    static func photos(analysisID: UUID) async -> [UIImage] {
        if NovaExpertTransport.shared.capture()?.access.workspaceID != nil {
            return (try? await NovaExpertAnalysisBackend.current()?.photos(analysisID)) ?? []
        }
        guard let bundle = try? await AnalysisService.shared.result(analysisID: analysisID) else { return [] }
        return await photos(bundle)
    }

    static func remove(analysisID: UUID, findingID: UUID) async throws {
        if let backend = try NovaExpertAnalysisBackend.current() {
            return try await backend.mutate("remove", analysis: analysisID, item: findingID)
        }
        _ = try await AnalysisService.shared.deleteFinding(analysisID: analysisID, findingID: findingID,
            expectedVersion: nil)
    }

    static func react(analysisID: UUID, itemID: UUID, section: NovaAnalysisSectionKind,
                      reaction: NovaAnalysisReaction) async throws {
        if let backend = try NovaExpertAnalysisBackend.current() {
            return try await backend.mutate("react", analysis: analysisID, item: itemID, extra: ["reaction": .string(reaction.rawValue)])
        }
        guard let target = AnalysisResultSectionID(rawValue: section.rawValue) else { return }
        let value: AnalysisItemReaction = reaction == .like ? .like : reaction == .dislike ? .dislike : .none
        try await AnalysisResultHubService.shared.setFeedback(analysisID: analysisID, language: .current,
            section: target, itemID: itemID, reaction: value)
    }

    /// The record board reads every company the account can still read, one at
    /// a time, re-checking the session between calls exactly as the company
    /// loader does. A failed company read must fail the board: returning the
    /// other rows would turn an incomplete result into a convincing zero/count.
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
            let list = try await read(company: company.id, kind: "list", decoding: ListEnvelope.self)
            let places = try await read(company: company.id, kind: "workplaces", decoding: WorkplaceEnvelope.self)
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
        let data = try await NovaExpertTransport.shared.execute("isg_nonconformity_read_v1", params: [
            "p_company": PersonnelRPCValue.id(company), "p_kind": .string(kind),
            "p_query": .null, "p_state": .null, "p_after": .null, "p_id": .null], ticket: NovaExpertTransport.shared.capture())
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

    /// Reads the analysis row first, then enriches it with the newer result-hub
    /// projection when one exists. Analyses created before that projection was
    /// introduced still open from their durable finding rows.
    static func detail(analysisID: UUID, identity: NovaSessionIdentity,
                       method: RiskMethod, methodLabel: String) async throws -> NovaAnalysisDetailData {
        if let backend = try NovaExpertAnalysisBackend.current() { return try await backend.detail(analysisID, method: method) }
        let bundle = try await AnalysisService.shared.result(analysisID: analysisID)
        let isFreshResult = date(bundle.analysis.createdAt).map {
            abs(Date().timeIntervalSince($0)) < 120
        } ?? false
        let loadedHub: AnalysisResultHubResponse?
        if isFreshResult {
            loadedHub = try? await AnalysisResultHubService.shared.loadWhenReady(
                analysisID: analysisID,
                language: .current
            )
        } else {
            // Historical rows will not gain a missing projection by polling;
            // one request is enough before falling back to their saved findings.
            loadedHub = try? await AnalysisResultHubService.shared.load(
                analysisID: analysisID,
                language: .current
            )
        }
        let companies = (try? await loadNovaPilotOverview(identity: identity)) ?? []
        let name = bundle.analysis.companyID.flatMap { id in companies.first { $0.id == id }?.name }
        return detailData(bundle: bundle, hub: loadedHub, companyName: name,
            method: method, methodLabel: methodLabel)
    }

    /// Pure assembly point used by the live loader and the legacy regression
    /// fixture. Keeping the fallback here prevents a missing enrichment from
    /// ever turning a readable analysis into an error screen again.
    static func detailData(bundle: AnalysisResultBundle, hub loadedHub: AnalysisResultHubResponse?,
                           companyName: String?, method: RiskMethod,
                           methodLabel: String) -> NovaAnalysisDetailData {
        let hub = loadedHub?.enabled == true ? loadedHub : nil
        let projectionComplete = hub.map { value in
            NovaAnalysisSectionKind.allCases.allSatisfy { kind in
                value.sections.contains { $0.id.rawValue == kind.rawValue }
            }
        } ?? false
        let resolvedSections = self.sections(hub: hub, bundle: bundle)
        let focuses = bundle.analysis.canvas.split(separator: ",").map(String.init)
            .compactMap { id in AnalysisCanvas.all.first { $0.id == id.trimmingCharacters(in: .whitespaces) }?.title }
        return .init(analysisID: bundle.analysis.id, title: bundle.analysis.title, createdOn: day(bundle.analysis.createdAt),
            methodLabel: methodLabel, method: method == .fineKinney ? .fineKinney : .matrix5x5,
            companyID: bundle.analysis.companyID, companyName: companyName, sections: resolvedSections,
            isProjectionMissing: !projectionComplete,
            photoCount: bundle.photos.count,
            sectorLabel: bundle.analysis.analysisSectorID?.label(),
            focusLabels: focuses)
    }

    /// The hub is the product's full projection. When it is unavailable the
    /// durable finding rows still contain the split between scored findings
    /// and unscored specialist observations, so preserve that split instead of
    /// putting every row under Risk Analizi.
    private static func sections(hub: AnalysisResultHubResponse?, bundle: AnalysisResultBundle) -> [NovaAnalysisSection] {
        let findings = bundle.findings.sorted { $0.ordinal < $1.ordinal }
        return NovaAnalysisSectionKind.allCases.map { kind in
            if let section = hub?.sections.first(where: { $0.id.rawValue == kind.rawValue }) {
                return .init(kind: kind, items: section.items.enumerated().map { at, item in
                    self.item(item, at: at, kind: kind)
                }, isTeaser: section.access == .teaser)
            }
            let fallbackRows: [FindingRow]
            switch kind {
            case .riskAnalysis:
                fallbackRows = findings.filter(isScoredFinding)
            case .expertRecommendations:
                fallbackRows = findings.filter { !isScoredFinding($0) }
            case .approvedNotebook, .trainingRecommendations:
                fallbackRows = []
            }
            return .init(kind: kind, items: fallbackRows.map {
                fallbackItem($0, kind: kind)
            }, isTeaser: false)
        }
    }

    /// Mirrors the server's `findingSection` rule. `is_scored` is authoritative;
    /// item class keeps rows from older V4 payloads correctly classified when
    /// that boolean was not yet written.
    private static func isScoredFinding(_ finding: FindingRow) -> Bool {
        if let isScored = finding.isScored { return isScored }
        switch finding.itemClass?.lowercased() {
        case "assurance_requirement", "verification_request", "positive_control", "not_assessable":
            return false
        default:
            return true
        }
    }

    private static func fallbackItem(_ finding: FindingRow,
                                     kind: NovaAnalysisSectionKind) -> NovaAnalysisItem {
        var item = NovaAnalysisItem(id: finding.id, ordinal: finding.ordinal, title: finding.title,
            category: finding.category, body: finding.description ?? "",
            measure: finding.recommendedAction, references: finding.referencesText)
        item.rootCause = finding.rootCauseText
        item.measures = measures(finding.recommendedMeasures)
        item.photoIndices = finding.sourcePhotoIndices ?? []
        if kind.isScored {
            item.fineKinney = fineKinney(band: finding.fkBand, score: finding.fkScore,
                probability: finding.fkProbability, frequency: finding.fkFrequency, severity: finding.fkSeverity)
            item.matrix = matrix(band: finding.m5Band, score: finding.m5Score,
                probability: finding.m5Probability, severity: finding.m5Severity)
        }
        return item
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
        if let backend = try NovaExpertAnalysisBackend.current() {
            return try await backend.mutate("assign", analysis: analysisID, extra: ["company_id": .id(companyID)])
        }
        try await AnalysisService.shared.assignCompany(to: analysisID, companyID: companyID)
    }

    static func edit(_ change: NovaAnalysisFindingEdit) async throws {
        if let backend = try NovaExpertAnalysisBackend.current() { return try await backend.edit(change) }
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
        if let backend = try NovaExpertAnalysisBackend.current() { return try await backend.report(request) }
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
