import Foundation
import UIKit
import CryptoKit

/// Tenant data adapter for the original analysis UI. No views or navigation live here.
@MainActor struct NovaExpertAnalysisBackend {
    let ticket: NovaExpertTransport.Ticket
    let store: IsgWorkspaceStore
    static func current() throws -> Self? {
        let transport = NovaExpertTransport.shared
        let ticket = transport.capture()
        guard let store = try transport.organizationStore(ticket: ticket), let ticket else { return nil }
        return .init(ticket: ticket, store: store)
    }
    func call<T: Decodable>(_ action: String, _ payload: [String: PersonnelRPCValue] = [:], as: T.Type = T.self) async throws -> T {
        let data = try await NovaExpertTransport.shared.execute("isg_expert_analysis_v1",
            params: ["p_action": PersonnelRPCValue.string(action), "p_payload": .object(payload)], ticket: ticket)
        return try JSONDecoder().decode(T.self, from: data)
    }
    struct Ack: Decodable { let id: UUID? }
    struct Snapshot: Decodable {
        struct Header: Decodable { let id: UUID; let title: String; let created_at: String; let primary_method: String }
        struct Photo: Decodable { let asset_id: UUID; let name: String }
        let company_id: UUID; let company_name: String
        let analysis: Header
        let risk_findings: [IsgWorkspaceAnalysisItem]
        let expert_items: [IsgWorkspaceAnalysisItem]
        let training_items: [IsgWorkspaceAnalysisItem]
        let photos: [Photo]
        let feedback: [String: String]
    }
    func snapshot(_ id: UUID) async throws -> Snapshot {
        try await call("detail", ["analysis_id": .id(id)])
    }
    func source(_ record: UUID) async throws -> UUID {
        let value: Snapshot = try await call("source", ["record_id": .id(record)])
        return value.analysis.id
    }
    func detail(_ id: UUID, method: RiskMethod) async throws -> NovaAnalysisDetailData {
        let value = try await snapshot(id)
        func items(_ rows: [IsgWorkspaceAnalysisItem]) -> [NovaAnalysisItem] {
            rows.enumerated().map { index, row in
                var item = NovaAnalysisItem(id: row.id, ordinal: row.ordinal ?? row.displayOrder ?? index + 1,
                    title: row.title, category: row.category, body: row.body ?? row.description ?? "",
                    measure: row.recommendation ?? row.recommendedAction, references: row.referencesText)
                item.audience = row.audience
                item.durationValue = row.durationMinutes.map { "\($0) dk" }
                item.photoIndices = row.sourcePhotoIndices ?? []
                item.reaction = NovaAnalysisReaction(rawValue: value.feedback[row.id.uuidString.lowercased()] ?? "none") ?? .none
                if row.isScored == true {
                    item.fineKinney = .init(band: row.fkBand, value: row.fkScore, factors: [
                        row.fkProbability.map { .init(label: "O", value: $0) },
                        row.fkFrequency.map { .init(label: "F", value: $0) },
                        row.fkSeverity.map { .init(label: RDLocalization.string("analysis.nova.expert.analysis.backend.s.41edf94f", table: .analysis, fallback: "Ş"), value: $0) }].compactMap { $0 })
                    item.matrix = .init(band: row.m5Band, value: row.m5Score.map(Double.init), factors: [
                        row.m5Probability.map { .init(label: "O", value: Double($0)) },
                        row.m5Severity.map { .init(label: RDLocalization.string("analysis.nova.expert.analysis.backend.s.5c33fb21", table: .analysis, fallback: "Ş"), value: Double($0)) }].compactMap { $0 })
                }
                return item
            }
        }
        return .init(analysisID: id, title: value.analysis.title, createdOn: NovaAnalysisWorkspace.day(value.analysis.created_at),
            methodLabel: method.label, method: method == .matrix5x5 ? .matrix5x5 : .fineKinney,
            companyID: value.company_id, companyName: value.company_name, sections: [
                .init(kind: .riskAnalysis, items: items(value.risk_findings), isTeaser: false),
                .init(kind: .expertRecommendations, items: items(value.expert_items), isTeaser: false),
                .init(kind: .trainingRecommendations, items: items(value.training_items), isTeaser: false),
                .init(kind: .approvedNotebook, items: [], isTeaser: false)
            ], isProjectionMissing: false, photoCount: value.photos.count)
    }
    func photos(_ id: UUID) async throws -> [UIImage] {
        let value = try await snapshot(id)
        var images: [UIImage] = []
        for photo in value.photos {
            let bytes = try await store.downloadAsset(photo.asset_id, filename: photo.name)
            try NovaExpertTransport.shared.validate(ticket)
            guard let image = UIImage(data: bytes) else { throw NovaPersonnelFailure.unavailable }
            images.append(image)
        }
        return images
    }
    func summaries(method: RiskMethod, limit: Int, offset: Int) async throws -> (rows: [NovaAnalysisSummary], hasMore: Bool) {
        struct Row: Decodable {
            let id: UUID; let title: String; let created_at: String; let company_name: String
            let finding_count: Int; let highest_band_fk: String?; let highest_band_m5: String?
            let created_by_user_id: UUID?
        }
        struct Page: Decodable { let rows: [Row]; let has_more: Bool }
        let page: Page = try await call("list", ["limit": .number(Int64(limit)), "offset": .number(Int64(offset))])
        return (page.rows.map { .init(id: $0.id, title: $0.title, createdOn: NovaAnalysisWorkspace.day($0.created_at),
            companyName: $0.company_name, findingCount: $0.finding_count,
            highestBand: method == .fineKinney ? $0.highest_band_fk : $0.highest_band_m5,
            isReviewed: true, createdAt: NovaAnalysisWorkspace.date($0.created_at), createdBy: $0.created_by_user_id) }, page.has_more)
    }
    func reports(limit: Int, offset: Int = 0) async throws -> (rows: [NovaAnalysisReportEntry], hasMore: Bool) {
        struct Row: Decodable {
            let id: UUID; let analysis_id: UUID; let title: String; let company_name: String
            let format: String; let file_name: String; let created_at: String; let file_size: Int?
            let asset_id: UUID?; let download_bucket: String?; let download_path: String?
        }
        struct Page: Decodable { let rows: [Row]; let has_more: Bool? }
        let page: Page = try await call("reports", ["limit": .number(Int64(limit)), "offset": .number(Int64(offset))])
        // Older pilot deployments returned only `rows` and ignored offset.
        // Read one expanded page there so the UI never repeats the first ten.
        if page.has_more == nil && offset > 0 {
            let expanded: Page = try await call("reports", ["limit": .number(Int64(min(offset + limit, 100))), "offset": .number(0)])
            let sliced = Array(expanded.rows.dropFirst(offset).prefix(limit))
            return (sliced.map { .init(id: $0.id, title: $0.title, fileName: $0.file_name,
                createdOn: NovaAnalysisWorkspace.day($0.created_at), companyName: $0.company_name,
                format: $0.format, methodLabel: "", kindLabel: "İSG Analizi", fileSize: $0.file_size,
                analysisID: $0.analysis_id, createdAt: NovaAnalysisWorkspace.date($0.created_at),
                assetID: $0.asset_id, downloadBucket: $0.download_bucket, downloadPath: $0.download_path) },
                expanded.rows.count > offset + limit)
        }
        return (page.rows.map { .init(id: $0.id, title: $0.title, fileName: $0.file_name,
            createdOn: NovaAnalysisWorkspace.day($0.created_at), companyName: $0.company_name,
            format: $0.format, methodLabel: "", kindLabel: "İSG Analizi", fileSize: $0.file_size,
            analysisID: $0.analysis_id, createdAt: NovaAnalysisWorkspace.date($0.created_at),
            assetID: $0.asset_id, downloadBucket: $0.download_bucket, downloadPath: $0.download_path) },
            page.has_more ?? (page.rows.count == limit))
    }
    func mutate(_ action: String, analysis: UUID, item: UUID? = nil,
                extra: [String: PersonnelRPCValue] = [:]) async throws {
        var payload = extra
        payload["analysis_id"] = .id(analysis)
        if let item { payload["item_id"] = .id(item) }
        let _: Ack = try await call(action, payload)
    }
    func edit(_ change: NovaAnalysisFindingEdit) async throws {
        var values: [String: PersonnelRPCValue] = [:]
        for (key, text) in [("title", change.title), ("category", change.category), ("body", change.body),
                            ("measure", change.measure), ("references", change.references)] {
            if let text { values[key] = .string(text) }
        }
        if change.score.isComplete {
            if change.score.method == .fineKinney {
                if let v = change.score.probability { values["fk_probability"] = .string(String(v)) }
                if let v = change.score.frequency { values["fk_frequency"] = .string(String(v)) }
                if let v = change.score.severity { values["fk_severity"] = .string(String(v)) }
            } else if change.score.method == .matrix5x5 {
                if let v = change.score.matrixProbability { values["m5_probability"] = .number(Int64(v)) }
                if let v = change.score.matrixSeverity { values["m5_severity"] = .number(Int64(v)) }
            }
        }
        try await mutate("edit", analysis: change.analysisID, item: change.findingID, extra: values)
    }
    func run(company: UUID?, images: [UIImage], focuses: [String], sector: String?,
             progress: @escaping @MainActor (AnalysisProgressUpdate) -> Void) async throws -> UUID {
        guard let company, !images.isEmpty, images.count <= 20 else { throw NovaPersonnelFailure.validation }
        let files = NovaFileLibraryService.live()
        var assets: [UUID] = []
        progress(.uploadingPhotos)
        for (index, image) in images.enumerated() {
            try NovaExpertTransport.shared.validate(ticket)
            let scale = min(1, 2048 / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            guard let bytes = normalized.jpegData(compressionQuality: 0.85) else { throw NovaPersonnelFailure.validation }
            var draft = NovaFileDraft()
            draft.title = "Analiz fotoğrafı \(index + 1)"; draft.category = "inspection_report"
            draft.fileName = "analiz-\(UUID().uuidString).jpg"; draft.fileExtension = "jpg"
            draft.bytes = bytes.count
            draft.sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let entry = try await files.file(ticket.access.identity, company: company, draft: draft, data: bytes)
            guard entry.state.isFiled, let asset = entry.assetID else { throw NovaFileFailure.inspectionUnavailable }
            assets.append(asset)
        }
        progress(.creatingAnalysis)
        let started: Ack = try await call("submit", ["company_id": .id(company), "mutation_id": .id(UUID()),
            "asset_ids": .array(assets.map(PersonnelRPCValue.id)), "focus_ids": .array(focuses.map(PersonnelRPCValue.string)),
            "sector": sector.map(PersonnelRPCValue.string) ?? .null])
        guard let id = started.id else { throw NovaPersonnelFailure.unavailable }
        for _ in 0..<180 {
            try NovaExpertTransport.shared.validate(ticket)
            let job = try await store.photoAnalysisJob(companyID: company, jobID: id)
            if let analysis = job.analysisID, job.status == "succeeded" { return analysis }
            if ["failed", "cancelled"].contains(job.status) { throw NovaPersonnelFailure.unavailable }
            progress(job.status == "running" ? .analyzing : .queued)
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw NovaPersonnelFailure.unavailable
    }
    func report(_ request: NovaAnalysisReportRequest) async throws -> String {
        struct Envelope: Decodable { let id: UUID?; let row: Job?; struct Job: Decodable { let id: UUID } }
        let value = try await snapshot(request.analysisID)
        let result: Envelope = try await call("export", ["analysis_id": .id(request.analysisID),
            "mutation_id": .id(UUID()), "format": .string(request.format == .pdf ? "pdf" : "xlsx"),
            "method": .string(request.method.rawValue), "attach_company": .bool(request.companyID != nil)])
        guard let jobID = result.id ?? result.row?.id else { throw NovaPersonnelFailure.unavailable }
        for _ in 0..<90 {
            try NovaExpertTransport.shared.validate(ticket)
            let job = try await store.export(companyID: value.company_id, jobID: jobID)
            if job.status == "succeeded" { return "\(value.analysis.title).\(request.format == .pdf ? "pdf" : "xlsx")" }
            if ["failed", "cancelled"].contains(job.status) { throw NovaPersonnelFailure.unavailable }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw NovaPersonnelFailure.unavailable
    }

    func file(_ request: NovaAnalysisFileRequest, analysis: UUID) async throws -> Bool {
        struct Receipt: Decodable { let nonconformity_id: UUID; let created: Bool }
        let value = try await snapshot(analysis)
        guard request.companyID == nil || request.companyID == value.company_id else { throw NovaPersonnelFailure.denied }
        let kind: String
        if request.section == .trainingRecommendations { kind = "training_item" }
        else if request.section.isScored || value.expert_items.contains(where: { $0.id == request.item.id && $0.kind == "unscored_finding" }) { kind = "finding" }
        else { kind = "expert_item" }
        let result: Receipt = try await call("file", ["analysis_id": .id(analysis), "item_id": .id(request.item.id),
            "workplace_id": request.workplaceID.map(PersonnelRPCValue.id) ?? .null, "mutation_id": .id(UUID()), "item_kind": .string(kind),
            "record_kind": .string(request.recordKind.rawValue),
            "severity": (request.severity?.rawValue ?? request.band).map(PersonnelRPCValue.string) ?? .null])
        let scope = NovaPersonnelScope(ownerID: ticket.access.identity.userID, sessionID: ticket.access.identity.sessionID,
            companyID: value.company_id, epoch: "analysis-filing:\(value.company_id.uuidString.lowercased())")
        let rows = try await NovaNonconformityService.live(identity: ticket.access.identity).list(scope)
        guard rows.contains(where: { $0.id == result.nonconformity_id }) else { throw NovaPersonnelFailure.unavailable }
        return result.created
    }
}
