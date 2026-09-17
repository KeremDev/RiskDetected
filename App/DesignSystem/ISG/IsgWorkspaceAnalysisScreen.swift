import SwiftUI

/// D8 presentation for analyses committed inside an OSGB workspace. The screen
/// never reads the personal analysis service and keeps every action inside the
/// selected workspace/company envelope.
struct IsgWorkspaceAnalysisScreen: View {
    @ObservedObject var store: IsgWorkspaceStore
    let companyID: UUID
    let companyName: String
    let canOperate: Bool
    let onBack: () -> Void
    @State private var selectedAnalysisID: UUID?
    @Environment(\.novaCelebrate) private var celebrate

    var body: some View {
        Group {
            if let selectedAnalysisID {
                NovaAnalysisDetailScreen(analysisID: selectedAnalysisID,
                    client: detailClient(selectedAnalysisID),
                    onBack: { self.selectedAnalysisID = nil },
                    canWrite: canOperate, canEdit: false, canReact: false,
                    canFile: canOperate, canFileTraining: false,
                    canReport: canOperate, reportResultIsArchiveName: false)
            } else {
                NovaAnalysisListScreen(load: load, thumbnail: { _ in nil },
                    onOpen: { selectedAnalysisID = $0 }, onBack: onBack)
            }
        }
    }

    private func load(offset: Int) async throws -> (rows: [NovaAnalysisSummary], hasMore: Bool) {
        let page = try await store.analyses(companyID: companyID, offset: offset, limit: 30)
        return (page.rows.map(summary), page.hasMore)
    }

    private func summary(_ value: IsgWorkspaceAnalysisSummary) -> NovaAnalysisSummary {
        let stamp = parseDate(value.createdAt)
        return .init(id: value.id, title: value.title, createdOn: displayDate(stamp, fallback: value.createdAt),
            companyName: companyName, findingCount: value.findingCount, photoCount: value.kind == "photo" ? 1 : 0,
            sectorLabel: nil, highestBand: value.highestBand, focusLabel: nil,
            isReviewed: false, createdAt: stamp)
    }

    private func detailClient(_ analysisID: UUID) -> NovaAnalysisDetailClient {
        .init(load: {
                let value = try await store.analysis(companyID: companyID, analysisID: analysisID)
                return detail(value)
            },
            photos: { [] },
            companies: { [.init(id: companyID, name: companyName, detail: "", sector: nil)] },
            assign: { _ in throw IsgWorkspaceAPIFailure.invalidRequest },
            workplaces: { requestedCompany in
                guard requestedCompany == companyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
                return try await store.directory(.workplace, companyID: companyID).map {
                    .init(id: $0.id, name: $0.name, needs_review: false)
                }
            },
            file: { request in await file(request, analysisID: analysisID) },
            edit: { _ in throw IsgWorkspaceAPIFailure.invalidRequest },
            remove: { _ in throw IsgWorkspaceAPIFailure.invalidRequest },
            react: { _, _, _ in throw IsgWorkspaceAPIFailure.invalidRequest },
            report: { request in try await requestExport(request, analysisID: analysisID) })
    }

    private func detail(_ value: IsgWorkspaceAnalysisResult) -> NovaAnalysisDetailData {
        let method = NovaRiskMethod(rawValue: value.primaryMethod) ?? .fineKinney
        return .init(analysisID: value.analysisID, title: value.title,
            createdOn: displayDate(parseDate(value.createdAt), fallback: value.createdAt),
            methodLabel: NovaNonconformityWords.method(method), method: method,
            companyID: companyID, companyName: companyName,
            sections: [
                .init(kind: .riskAnalysis, items: map(value.riskFindings), isTeaser: false),
                .init(kind: .expertRecommendations, items: map(value.expertItems), isTeaser: false),
                .init(kind: .trainingRecommendations, items: map(value.trainingItems), isTeaser: false)
            ], isProjectionMissing: false, photoCount: 0, sectorLabel: nil, focusLabels: [])
    }

    private func map(_ values: [IsgWorkspaceAnalysisItem]) -> [NovaAnalysisItem] {
        values.enumerated().map { index, value in
            let fk = value.fkScore.map { score in
                NovaAnalysisScore(band: value.fkBand, value: score,
                    factors: [
                        value.fkProbability.map { .init(label: "O", value: $0) },
                        value.fkFrequency.map { .init(label: "F", value: $0) },
                        value.fkSeverity.map { .init(label: "Ş", value: $0) }
                    ].compactMap { $0 })
            }
            let matrix = value.m5Score.map { score in
                NovaAnalysisScore(band: value.m5Band, value: Double(score),
                    factors: [
                        value.m5Probability.map { .init(label: "O", value: Double($0)) },
                        value.m5Severity.map { .init(label: "Ş", value: Double($0)) }
                    ].compactMap { $0 })
            }
            return .init(id: value.id, ordinal: value.ordinal ?? value.displayOrder ?? index + 1,
                title: value.title, category: value.category,
                body: value.body ?? value.description ?? "",
                measure: value.recommendation ?? value.recommendedAction,
                references: value.referencesText, audience: value.audience,
                durationLabel: value.durationMinutes == nil ? nil : RDLocalization.string(
                    "localizable.nova.analysis.field.duration", table: .localizable, fallback: "Eğitim süresi"),
                durationValue: value.durationMinutes.map { "\($0) dk" },
                photoIndices: value.sourcePhotoIndices ?? [], fineKinney: fk, matrix: matrix)
        }
    }

    @MainActor private func file(_ request: NovaAnalysisFileRequest,
                                 analysisID: UUID) async -> NovaFindingOutcome {
        guard request.companyID == nil || request.companyID == companyID else {
            return .failed(NovaNonconformityWords.failure(.denied))
        }
        do {
            let source = try await store.analysis(companyID: companyID, analysisID: analysisID)
            let itemKind = request.section == .riskAnalysis ||
                source.expertItems.first(where: { $0.id == request.item.id })?.kind == "unscored_finding"
                ? "finding" : "expert_item"
            let response = try await store.fileAnalysisItem(mutationID: UUID(), companyID: companyID,
                workplaceID: request.workplaceID, sourceScope: "workspace", analysisID: analysisID,
                itemKind: itemKind, itemID: request.item.id, severity: request.severity?.rawValue,
                openedOn: day(Date()), dueOn: nil)
            celebrate(response.successMessage)
            return response.result.created ? .opened : .alreadyOpen
        } catch {
            return .failed(RDLocalization.string("localizable.nova.bridge.outcome.failed", table: .localizable,
                fallback: "Bu bulgu için kayıt açılamadı. Aynı işlemi tekrar deneyin."))
        }
    }

    private func requestExport(_ request: NovaAnalysisReportRequest,
                               analysisID: UUID) async throws -> String {
        let analysis = try await store.analysis(companyID: companyID, analysisID: analysisID)
        let job = try await store.createExport(mutationID: UUID(), companyID: companyID,
            analysisID: analysisID, format: request.format == .excel ? "xlsx" : "pdf",
            findingIDs: analysis.riskFindings.map(\.id),
            expertItemIDs: analysis.expertItems.filter { $0.kind == "expert_recommendation" }.map(\.id),
            trainingItemIDs: analysis.trainingItems.map(\.id))
        if job.status == "succeeded" {
            return RDLocalization.string("localizable.nova.workspace.analysis.export.ready", table: .localizable,
                                         fallback: "Rapor hazırlandı.")
        }
        return RDLocalization.string("localizable.nova.workspace.analysis.export.queued", table: .localizable,
                                     fallback: "Rapor isteği alındı ve hazırlanıyor.")
    }

    private func parseDate(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func displayDate(_ date: Date?, fallback: String) -> String {
        guard let date else { return String(fallback.prefix(10)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    private func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
