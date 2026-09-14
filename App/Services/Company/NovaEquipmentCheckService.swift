import Foundation

/// Same shape as the personnel, document tracking and file library services: a
/// plain RPC closure, a session check and no SDK type in the design system.
@MainActor struct NovaEquipmentCheckService {
    typealias RPC = (String, [String: PersonnelRPCValue]) async throws -> Data
    private let rpc: RPC
    private let isSession: (NovaSessionIdentity) -> Bool

    init(rpc: @escaping RPC, isSession: @escaping (NovaSessionIdentity) -> Bool) {
        self.rpc = rpc; self.isSession = isSession
    }

    private func check(_ identity: NovaSessionIdentity) throws {
        guard isSession(identity) else { throw NovaEquipmentFailure.denied }
    }

    // MARK: transport rows

    private struct InspectionRow: Decodable {
        let id: UUID
        let performed_on: String
        let result: String
        let next_due_on: String?
        let period_months: Int?
        let inspector: String?
        let external_ref: String?
        let note: String?
        let evidence_asset_id: UUID?
    }
    private struct ItemRow: Decodable {
        let id: UUID
        var company_id: UUID?
        var company_name: String?
        let workplace_id: UUID?
        let equipment_type: String
        let serial_tag: String
        let acquired_on: String?
        let location_note: String?
        let is_archived: Bool
        let state: String
        let period_months: Int?
        let period_source: String?
        let period_needs_review: Bool?
        let period_exception_note: String?
        let period_defined_after_report: Bool
        let last_performed_on: String?
        let last_result: String?
        let last_inspector: String?
        let last_external_ref: String?
        let next_due_on: String?
        let evidence_asset_id: UUID?
        let inspections: [InspectionRow]?
    }
    private struct SuggestionRow: Decodable { let code: String; let ordinal: Int }
    private struct RuleRow: Decodable {
        let equipment_type: String
        let period_months: Int
        let period_source: String
        let needs_review: Bool
        let exception_note: String?
    }
    private struct WorkplaceRow: Decodable { let id: UUID; let name: String }
    private struct CatalogEnvelope: Decodable {
        let suggestions: [SuggestionRow]
        let rules: [RuleRow]
        let workplaces: [WorkplaceRow]
        let notice_days: Int
        let period_defaults_offered: Bool
    }
    private struct CompanyRow: Decodable { let id: UUID; let name: String; let total: Int; let counts: [String: Int] }
    private struct ListEnvelope: Decodable {
        let rows: [ItemRow]
        let companies: [CompanyRow]
        let counts: [String: Int]
        let type_counts: [String: [String: Int]]
        let total: Int
        let has_more: Bool
        let limit: Int
        let offset: Int
        let today: String
        let notice_days: Int
    }
    private struct DetailEnvelope: Decodable { let row: ItemRow }
    private struct MutationEnvelope: Decodable { let equipment_id: UUID?; let row: ItemRow? }
    private struct RuleEnvelope: Decodable { let rule: RuleRow }

    /// An unknown state word is reported as untracked rather than smoothed into
    /// the calmest answer: the expert should look at the row.
    private func item(_ row: ItemRow) -> NovaEquipmentItem {
        .init(id: row.id, companyID: row.company_id, companyName: row.company_name,
              workplaceID: row.workplace_id, workplaceName: nil,
              equipmentType: row.equipment_type, serialTag: row.serial_tag,
              acquiredOn: row.acquired_on, locationNote: row.location_note,
              isArchived: row.is_archived,
              state: NovaEquipmentState(rawValue: row.state) ?? .neverInspected,
              periodMonths: row.period_months,
              periodSource: row.period_source.flatMap(NovaEquipmentPeriodSource.init(rawValue:)),
              periodNeedsReview: row.period_needs_review,
              periodExceptionNote: row.period_exception_note,
              periodDefinedAfterReport: row.period_defined_after_report,
              lastPerformedOn: row.last_performed_on, lastResult: row.last_result,
              lastInspector: row.last_inspector, lastExternalRef: row.last_external_ref,
              nextDueOn: row.next_due_on, evidenceAssetID: row.evidence_asset_id,
              inspections: (row.inspections ?? []).map { entry in
                  .init(id: entry.id, performedOn: entry.performed_on, result: entry.result,
                        nextDueOn: entry.next_due_on, periodMonths: entry.period_months,
                        inspector: entry.inspector, externalRef: entry.external_ref,
                        note: entry.note, evidenceAssetID: entry.evidence_asset_id)
              })
    }

    private static func states(_ raw: [String: Int]) -> [NovaEquipmentState: Int] {
        var result: [NovaEquipmentState: Int] = [:]
        for (key, value) in raw {
            guard let state = NovaEquipmentState(rawValue: key) else { continue }
            result[state] = value
        }
        return result
    }

    private func read(_ arguments: [String: PersonnelRPCValue]) async throws -> Data {
        var payload: [String: PersonnelRPCValue] = [
            "p_company": .null, "p_kind": .string("list"), "p_query": .null, "p_state": .null,
            "p_workplace": .null, "p_type": .null, "p_id": .null, "p_limit": .null, "p_offset": .null]
        for (key, value) in arguments { payload[key] = value }
        return try await rpc("isg_equipment_checks_read_v1", payload)
    }

    // MARK: reads

    /// The type names the client may offer, the periods this company has set and
    /// its workplaces. The names arrive without periods on purpose.
    func catalogue(_ identity: NovaSessionIdentity,
                   company: UUID?) async throws -> (suggestions: [String],
                                                    rules: [NovaEquipmentRule],
                                                    workplaces: [NovaDocumentWorkplace],
                                                    noticeDays: Int) {
        try check(identity)
        let data = try await read(["p_company": company.map { .id($0) } ?? .null,
                                   "p_kind": .string("catalog")])
        try check(identity)
        let envelope = try JSONDecoder().decode(CatalogEnvelope.self, from: data)
        return (envelope.suggestions.sorted { $0.ordinal < $1.ordinal }.map(\.code),
                envelope.rules.map { rule in
                    .init(equipmentType: rule.equipment_type, periodMonths: rule.period_months,
                          source: NovaEquipmentPeriodSource(rawValue: rule.period_source) ?? .unapprovedFixture,
                          needsReview: rule.needs_review, exceptionNote: rule.exception_note)
                },
                envelope.workplaces.map { .init(id: $0.id, name: $0.name) },
                envelope.notice_days)
    }

    /// The whole account in one call. Not scoped to a company, so it checks the
    /// signed-in session itself on both sides of the call.
    func board(_ identity: NovaSessionIdentity, query: NovaEquipmentQuery = .init()) async throws -> NovaEquipmentBoard {
        try check(identity)
        let trimmed = query.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try await read([
            "p_company": query.company.map { .id($0) } ?? .null,
            "p_query": trimmed.isEmpty ? .null : .string(trimmed),
            "p_state": query.state.map { .string($0) } ?? .null,
            "p_workplace": query.workplace.map { .id($0) } ?? .null,
            "p_type": query.equipmentType.map { .string($0) } ?? .null,
            "p_limit": .number(Int64(query.limit)), "p_offset": .number(Int64(query.offset))])
        try check(identity)
        let envelope = try JSONDecoder().decode(ListEnvelope.self, from: data)
        return .init(counts: Self.states(envelope.counts),
                     companies: envelope.companies.map { entry in
                         .init(id: entry.id, name: entry.name, total: entry.total,
                               counts: Self.states(entry.counts))
                     },
                     typeCounts: envelope.type_counts.mapValues(Self.states),
                     rows: envelope.rows.map(item),
                     total: envelope.total, hasMore: envelope.has_more,
                     limit: envelope.limit, offset: envelope.offset,
                     today: envelope.today, noticeDays: envelope.notice_days)
    }

    func detail(_ identity: NovaSessionIdentity, equipment: UUID) async throws -> NovaEquipmentItem {
        try check(identity)
        let data = try await read(["p_kind": .string("detail"), "p_id": .id(equipment)])
        try check(identity)
        return item(try JSONDecoder().decode(DetailEnvelope.self, from: data).row)
    }

    // MARK: writes

    private func mutate(company: UUID, action: String, payload: [String: PersonnelRPCValue],
                        operationID: UUID = UUID(), mutationID: UUID = UUID()) async throws -> Data {
        try await rpc("isg_equipment_checks_mutate_v1", [
            "p_company": .id(company), "p_action": .string(action),
            "p_operation": .id(operationID), "p_mutation": .id(mutationID),
            "p_payload": .object(payload)])
    }

    private static func trimmed(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    func register(_ identity: NovaSessionIdentity, company: UUID,
                  draft: NovaEquipmentDraft) async throws -> NovaEquipmentItem {
        try check(identity)
        guard draft.isReady, let type = draft.equipmentType, let workplace = draft.workplaceID else {
            throw NovaEquipmentFailure.validation
        }
        var payload: [String: PersonnelRPCValue] = [
            "workplace_id": .id(workplace), "equipment_type": .string(type),
            "serial_tag": .string(draft.serialTag.trimmingCharacters(in: .whitespacesAndNewlines))]
        payload["acquired_on"] = Self.trimmed(draft.acquiredOn).map { .string($0) } ?? .null
        payload["location_note"] = Self.trimmed(draft.locationNote).map { .string($0) } ?? .null
        let data = try await mutate(company: company, action: "register_equipment", payload: payload)
        try check(identity)
        guard let row = try JSONDecoder().decode(MutationEnvelope.self, from: data).row else {
            throw NovaEquipmentFailure.unavailable
        }
        return item(row)
    }

    func update(_ identity: NovaSessionIdentity, equipment: NovaEquipmentItem,
                draft: NovaEquipmentDraft) async throws -> NovaEquipmentItem {
        try check(identity)
        guard let company = equipment.companyID else { throw NovaEquipmentFailure.denied }
        var payload: [String: PersonnelRPCValue] = ["equipment_id": .id(equipment.id)]
        if let workplace = draft.workplaceID { payload["workplace_id"] = .id(workplace) }
        payload["serial_tag"] = .string(draft.serialTag.trimmingCharacters(in: .whitespacesAndNewlines))
        payload["acquired_on"] = Self.trimmed(draft.acquiredOn).map { .string($0) } ?? .null
        payload["location_note"] = Self.trimmed(draft.locationNote).map { .string($0) } ?? .null
        let data = try await mutate(company: company, action: "update_equipment", payload: payload)
        try check(identity)
        guard let row = try JSONDecoder().decode(MutationEnvelope.self, from: data).row else {
            throw NovaEquipmentFailure.unavailable
        }
        return item(row)
    }

    func archive(_ identity: NovaSessionIdentity, equipment: NovaEquipmentItem) async throws {
        try check(identity)
        guard let company = equipment.companyID else { throw NovaEquipmentFailure.denied }
        _ = try await mutate(company: company, action: "archive_equipment",
                             payload: ["equipment_id": .id(equipment.id)])
    }

    /// The period for one equipment type. The source always travels with it, so
    /// a duration can never appear on screen without saying where it came from.
    func setRule(_ identity: NovaSessionIdentity, company: UUID,
                 draft: NovaEquipmentRuleDraft) async throws -> NovaEquipmentRule {
        try check(identity)
        guard draft.isReady, let type = draft.equipmentType, let months = draft.monthsValue else {
            throw NovaEquipmentFailure.validation
        }
        var payload: [String: PersonnelRPCValue] = [
            "equipment_type": .string(type), "period_months": .number(Int64(months)),
            "period_source": .string(draft.source.rawValue)]
        payload["exception_note"] = Self.trimmed(draft.exceptionNote).map { .string($0) } ?? .null
        let data = try await mutate(company: company, action: "set_rule", payload: payload)
        try check(identity)
        let rule = try JSONDecoder().decode(RuleEnvelope.self, from: data).rule
        return .init(equipmentType: rule.equipment_type, periodMonths: rule.period_months,
                     source: NovaEquipmentPeriodSource(rawValue: rule.period_source) ?? .unapprovedFixture,
                     needsReview: rule.needs_review, exceptionNote: rule.exception_note)
    }

    /// One report. The next due date is the server's: it comes from the type's
    /// period, and a report with no period behind it gets none.
    func recordInspection(_ identity: NovaSessionIdentity, equipment: NovaEquipmentItem,
                          draft: NovaEquipmentInspectionDraft,
                          mutationID: UUID = UUID()) async throws -> NovaEquipmentItem {
        try check(identity)
        guard let company = equipment.companyID else { throw NovaEquipmentFailure.denied }
        guard draft.isReady else { throw NovaEquipmentFailure.validation }
        var payload: [String: PersonnelRPCValue] = [
            "equipment_id": .id(equipment.id),
            "performed_on": .string(draft.performedOn.trimmingCharacters(in: .whitespacesAndNewlines)),
            "result": .string(draft.result)]
        payload["inspector"] = Self.trimmed(draft.inspector).map { .string($0) } ?? .null
        payload["external_ref"] = Self.trimmed(draft.externalRef).map { .string($0) } ?? .null
        payload["note"] = Self.trimmed(draft.note).map { .string($0) } ?? .null
        payload["evidence_asset_id"] = draft.evidenceAssetID.map { .id($0) } ?? .null
        let data = try await mutate(company: company, action: "record_inspection",
                                    payload: payload, mutationID: mutationID)
        try check(identity)
        guard let row = try JSONDecoder().decode(MutationEnvelope.self, from: data).row else {
            throw NovaEquipmentFailure.unavailable
        }
        return item(row)
    }
}
