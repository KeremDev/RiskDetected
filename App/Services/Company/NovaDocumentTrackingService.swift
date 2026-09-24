import Foundation

/// Same shape as the personnel and nonconformity services: a plain RPC closure,
/// a scope check and no SDK type in the design system.
@MainActor struct NovaDocumentTrackingService {
    typealias RPC = (String, [String: PersonnelRPCValue]) async throws -> Data
    private let rpc: RPC
    private let isCurrent: (NovaPersonnelScope) -> Bool
    /// The portfolio spans every company, so it has no workspace scope to check.
    /// It verifies the signed-in session itself instead, on both sides of the call.
    private let isSession: (NovaSessionIdentity) -> Bool

    init(rpc: @escaping RPC, isCurrent: @escaping (NovaPersonnelScope) -> Bool,
         isSession: @escaping (NovaSessionIdentity) -> Bool) {
        self.rpc = rpc; self.isCurrent = isCurrent; self.isSession = isSession
    }

    private func check(_ scope: NovaPersonnelScope) throws {
        guard isCurrent(scope) else { throw NovaDocumentFailure.denied }
    }
    private func check(_ identity: NovaSessionIdentity) throws {
        guard isSession(identity) else { throw NovaDocumentFailure.denied }
    }

    // MARK: transport rows

    private struct CopyRow: Decodable {
        let id: UUID
        let issued_on: String
        let valid_until: String?
        let document_no: String?
        let location_note: String?
        let recorded_at: String?
    }
    private struct ObligationRow: Decodable {
        let id: UUID
        var company_id: UUID?
        var company_name: String?
        let workplace_id: UUID?
        let kind_code: String
        let title: String
        let basis: String
        let legal_ref: String?
        let validity_days: Int?
        let notice_days: Int
        let responsible_contact: String?
        let note: String?
        let is_archived: Bool
        let version: Int
        let status: String
        let latest_issued_on: String?
        let latest_valid_until: String?
        let records: [CopyRow]
        let file_stored: Bool
    }
    private struct KindRow: Decodable { let code: String; let ordinal: Int; let default_validity_days: Int? }
    private struct WorkplaceRow: Decodable { let id: UUID; let name: String }
    private struct ListEnvelope: Decodable {
        let rows: [ObligationRow]
        let today: String
        let counts: [String: Int]
        let file_storage_available: Bool
    }
    private struct KindEnvelope: Decodable { let rows: [KindRow] }
    private struct WorkplaceEnvelope: Decodable { let rows: [WorkplaceRow] }
    private struct MutationEnvelope: Decodable { let row: ObligationRow }

    /// The status is the server's answer for today. An unknown word is not
    /// silently downgraded to a calm one: it is reported as missing so the
    /// expert looks at the row rather than trusting a guess.
    private func obligation(_ row: ObligationRow) -> NovaDocumentObligation {
        .init(id: row.id, companyID: row.company_id, companyName: row.company_name,
              workplaceID: row.workplace_id, kindCode: row.kind_code, title: row.title,
              basis: NovaDocumentBasis(rawValue: row.basis) ?? .expert, legalRef: row.legal_ref,
              validityDays: row.validity_days, noticeDays: row.notice_days,
              responsibleContact: row.responsible_contact, note: row.note,
              isArchived: row.is_archived, version: row.version,
              status: NovaDocumentStatus(rawValue: row.status) ?? .missing,
              latestIssuedOn: row.latest_issued_on, latestValidUntil: row.latest_valid_until,
              copies: row.records.map { copy in
                  .init(id: copy.id, issuedOn: copy.issued_on, validUntil: copy.valid_until,
                        documentNo: copy.document_no, locationNote: copy.location_note,
                        recordedAt: copy.recorded_at)
              },
              fileStored: row.file_stored)
    }

    private struct CompanyRow: Decodable { let id: UUID; let name: String; let total: Int; let counts: [String: Int] }
    private struct PortfolioEnvelope: Decodable {
        let rows: [ObligationRow]
        let companies: [CompanyRow]
        let counts: [String: Int]
        let kind_counts: [String: [String: Int]]
        let total: Int
        let has_more: Bool
        let today: String
        let file_storage_available: Bool
    }

    private static func statuses(_ raw: [String: Int]) -> [NovaDocumentStatus: Int] {
        var result: [NovaDocumentStatus: Int] = [:]
        for (key, value) in raw {
            guard let status = NovaDocumentStatus(rawValue: key) else { continue }
            result[status] = value
        }
        return result
    }

    // MARK: reads

    /// The whole account in one call. This read is not scoped to a company, so
    /// it checks the session identity itself rather than a workspace scope.
    func portfolio(_ identity: NovaSessionIdentity, query: String = "", status: NovaDocumentStatus? = nil,
                   company: UUID? = nil, kinds: [String]? = nil,
                   limit: Int = 10, offset: Int = 0) async throws -> NovaDocumentPortfolio {
        try check(identity)
        var args: [String: PersonnelRPCValue] = [
            "p_query": query.isEmpty ? .null : .string(query),
            "p_status": status.map { .string($0.rawValue) } ?? .null,
            "p_company": company.map { .id($0) } ?? .null,
            "p_limit": .number(Int64(limit)), "p_offset": .number(Int64(offset))]
        args["p_kinds"] = kinds.map { .array($0.map { value in .string(value) }) } ?? .null
        let data = try await rpc("isg_document_portfolio_v1", args)
        try check(identity)
        let envelope = try JSONDecoder().decode(PortfolioEnvelope.self, from: data)
        return .init(counts: Self.statuses(envelope.counts),
                     companies: envelope.companies.map { entry in
                         .init(id: entry.id, name: entry.name, total: entry.total,
                               counts: Self.statuses(entry.counts))
                     },
                     kindCounts: envelope.kind_counts.mapValues(Self.statuses),
                     rows: envelope.rows.map(obligation),
                     total: envelope.total, hasMore: envelope.has_more, today: envelope.today,
                     fileStorageAvailable: envelope.file_storage_available)
    }

    func board(_ scope: NovaPersonnelScope, query: String = "") async throws -> NovaDocumentBoard {
        try check(scope)
        let data = try await rpc("isg_document_tracking_read_v1", [
            "p_company": .id(scope.companyID), "p_kind": .string("list"),
            "p_query": .string(query), "p_status": .null, "p_workplace": .null, "p_id": .null])
        try check(scope)
        let envelope = try JSONDecoder().decode(ListEnvelope.self, from: data)
        var counts: [NovaDocumentStatus: Int] = [:]
        for (key, value) in envelope.counts {
            guard let status = NovaDocumentStatus(rawValue: key) else { continue }
            counts[status] = value
        }
        return .init(rows: envelope.rows.map(obligation), counts: counts, today: envelope.today,
                     fileStorageAvailable: envelope.file_storage_available)
    }

    func detail(_ scope: NovaPersonnelScope, obligation id: UUID) async throws -> NovaDocumentObligation {
        try check(scope)
        let data = try await rpc("isg_document_tracking_read_v1", [
            "p_company": .id(scope.companyID), "p_kind": .string("detail"),
            "p_query": .null, "p_status": .null, "p_workplace": .null, "p_id": .id(id)])
        try check(scope)
        return obligation(try JSONDecoder().decode(MutationEnvelope.self, from: data).row)
    }

    func kinds(_ scope: NovaPersonnelScope) async throws -> [NovaDocumentKind] {
        try check(scope)
        let data = try await rpc("isg_document_tracking_read_v1", [
            "p_company": .id(scope.companyID), "p_kind": .string("kinds"),
            "p_query": .null, "p_status": .null, "p_workplace": .null, "p_id": .null])
        try check(scope)
        return try JSONDecoder().decode(KindEnvelope.self, from: data).rows
            .map { .init(code: $0.code, ordinal: $0.ordinal, defaultValidityDays: $0.default_validity_days) }
    }

    func workplaces(_ scope: NovaPersonnelScope) async throws -> [NovaDocumentWorkplace] {
        try check(scope)
        let data = try await rpc("isg_document_tracking_read_v1", [
            "p_company": .id(scope.companyID), "p_kind": .string("workplaces"),
            "p_query": .null, "p_status": .null, "p_workplace": .null, "p_id": .null])
        try check(scope)
        return try JSONDecoder().decode(WorkplaceEnvelope.self, from: data).rows
            .map { .init(id: $0.id, name: $0.name) }
    }

    // MARK: writes

    /// The operation and mutation identifiers travel with every write, so a
    /// retry returns the first answer instead of filing a second row.
    private func mutate(_ scope: NovaPersonnelScope, action: String,
                        payload: [String: PersonnelRPCValue],
                        operationID: UUID = UUID(), mutationID: UUID = UUID()) async throws -> NovaDocumentObligation {
        try check(scope)
        let data = try await rpc("isg_document_tracking_mutate_v1", [
            "p_company": .id(scope.companyID), "p_action": .string(action),
            "p_operation": .id(operationID), "p_mutation": .id(mutationID),
            "p_payload": .object(payload)])
        try check(scope)
        let row = obligation(try JSONDecoder().decode(MutationEnvelope.self, from: data).row)
        NotificationCenter.default.post(name: Notification.Name("isgada.records.changed"), object: scope.ownerID)
        return row
    }

    private static func trimmed(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Only the fields the form actually carries are sent. A legal basis never
    /// travels without the reference, because the form will not offer it.
    private static func body(_ draft: NovaDocumentDraft, includeKind: Bool) -> [String: PersonnelRPCValue] {
        var payload: [String: PersonnelRPCValue] = [
            "title": .string(draft.title.trimmingCharacters(in: .whitespacesAndNewlines)),
            "basis": .string(draft.basis.rawValue),
            "notice_days": .number(Int64(draft.noticeValue))]
        if includeKind, let kind = draft.kindCode { payload["kind_code"] = .string(kind) }
        payload["workplace_id"] = draft.workplaceID.map { .id($0) } ?? .null
        payload["legal_ref"] = trimmed(draft.legalRef).map { .string($0) } ?? .null
        payload["validity_days"] = draft.validityValue.map { .number(Int64($0)) } ?? .null
        payload["responsible_contact"] = trimmed(draft.responsibleContact).map { .string($0) } ?? .null
        payload["note"] = trimmed(draft.note).map { .string($0) } ?? .null
        return payload
    }

    func add(_ scope: NovaPersonnelScope, draft: NovaDocumentDraft) async throws -> NovaDocumentObligation {
        try await mutate(scope, action: "add_obligation", payload: Self.body(draft, includeKind: true))
    }

    func update(_ scope: NovaPersonnelScope, obligation entry: NovaDocumentObligation,
                draft: NovaDocumentDraft) async throws -> NovaDocumentObligation {
        var payload = Self.body(draft, includeKind: false)
        payload["obligation_id"] = .id(entry.id)
        payload["expected_version"] = .number(Int64(entry.version))
        return try await mutate(scope, action: "update_obligation", payload: payload)
    }

    func archive(_ scope: NovaPersonnelScope, obligation entry: NovaDocumentObligation) async throws {
        _ = try await mutate(scope, action: "archive_obligation", payload: [
            "obligation_id": .id(entry.id), "expected_version": .number(Int64(entry.version))])
    }

    /// The copy is keyed by its own mutation identifier, so pressing save twice
    /// records one copy and replays the answer for the second press.
    func recordCopy(_ scope: NovaPersonnelScope, obligation entry: NovaDocumentObligation,
                    draft: NovaDocumentCopyDraft, mutationID: UUID = UUID()) async throws -> NovaDocumentObligation {
        var payload: [String: PersonnelRPCValue] = [
            "obligation_id": .id(entry.id),
            "issued_on": .string(draft.issuedOn.trimmingCharacters(in: .whitespacesAndNewlines))]
        // An empty end date is left out entirely so the obligation's own period
        // decides, instead of being sent as a null the server has to interpret.
        if let until = Self.trimmed(draft.validUntil) { payload["valid_until"] = .string(until) }
        payload["document_no"] = Self.trimmed(draft.documentNo).map { .string($0) } ?? .null
        payload["location_note"] = Self.trimmed(draft.locationNote).map { .string($0) } ?? .null
        return try await mutate(scope, action: "record_copy", payload: payload, mutationID: mutationID)
    }

    func removeCopy(_ scope: NovaPersonnelScope, obligation entry: NovaDocumentObligation,
                    copy: NovaDocumentCopy) async throws -> NovaDocumentObligation {
        try await mutate(scope, action: "remove_copy", payload: [
            "obligation_id": .id(entry.id), "record_id": .id(copy.id)])
    }
}
