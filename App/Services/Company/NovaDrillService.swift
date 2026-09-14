import Foundation

/// Same shape as the other module services: a plain RPC closure, a session
/// check and no SDK type in the design system.
@MainActor struct NovaDrillService {
    typealias RPC = (String, [String: PersonnelRPCValue]) async throws -> Data
    private let rpc: RPC
    private let isSession: (NovaSessionIdentity) -> Bool

    init(rpc: @escaping RPC, isSession: @escaping (NovaSessionIdentity) -> Bool) {
        self.rpc = rpc; self.isSession = isSession
    }

    private func check(_ identity: NovaSessionIdentity) throws {
        guard isSession(identity) else { throw NovaDrillFailure.denied }
    }

    // MARK: transport rows

    private struct ParticipantRow: Decodable { let id: UUID; let full_name: String }
    private struct DrillRow: Decodable {
        let id: UUID
        var company_id: UUID?
        var company_name: String?
        let workplace_id: UUID?
        var workplace_name: String?
        let plan_id: UUID
        let plan_version: Int
        let plan_scope: String?
        let plan_version_superseded: Bool
        let planned_on: String
        let performed_on: String?
        let state: String
        let notice_days: Int
        let performed: Bool
        let observation: String?
        let improvement: String?
        let cancelled_reason: String?
        let participants: [ParticipantRow]?
        let participant_count: Int
        let participants_snapshotted: Bool
    }
    private struct PlanOptionRow: Decodable {
        let plan_id: UUID
        let version: Int
        let scope: String
        let workplace_id: UUID
        let workplace_name: String
        let valid_until: String?
    }
    private struct EmployeeRow: Decodable { let id: UUID; let full_name: String }
    private struct CatalogEnvelope: Decodable {
        let plans: [PlanOptionRow]
        let employees: [EmployeeRow]
        let notice_days: Int
        let period_defaults_offered: Bool
    }
    private struct CompanyRow: Decodable { let id: UUID; let name: String; let total: Int; let counts: [String: Int] }
    private struct ListEnvelope: Decodable {
        let rows: [DrillRow]
        let companies: [CompanyRow]
        let counts: [String: Int]
        let total: Int
        let has_more: Bool
        let offset: Int
        let notice_days: Int
    }
    private struct DetailEnvelope: Decodable { let row: DrillRow }
    private struct MutationEnvelope: Decodable { let drill_id: UUID?; let row: DrillRow? }

    /// An unknown state word is reported as overdue rather than smoothed into
    /// the calmest answer: the expert should look at the drill.
    private func drill(_ entry: DrillRow) -> NovaDrill {
        let state = NovaDrillState(rawValue: entry.state) ?? .overdue
        return NovaDrill(
            id: entry.id, companyID: entry.company_id, companyName: entry.company_name,
            workplaceID: entry.workplace_id, workplaceName: entry.workplace_name,
            planID: entry.plan_id, planVersion: entry.plan_version, planScope: entry.plan_scope,
            planVersionSuperseded: entry.plan_version_superseded,
            plannedOn: entry.planned_on, performedOn: entry.performed_on,
            state: state, group: NovaDrillGroup.of(state), noticeDays: entry.notice_days,
            performed: entry.performed, observation: entry.observation,
            improvement: entry.improvement, cancelledReason: entry.cancelled_reason,
            participants: (entry.participants ?? []).map { .init(id: $0.id, fullName: $0.full_name) },
            participantCount: entry.participant_count,
            participantsSnapshotted: entry.participants_snapshotted)
    }

    private func read(_ arguments: [String: PersonnelRPCValue]) async throws -> Data {
        var payload: [String: PersonnelRPCValue] = [
            "p_company": .null, "p_kind": .string("list"), "p_query": .null, "p_state": .null,
            "p_workplace": .null, "p_id": .null, "p_limit": .null, "p_offset": .null]
        for (key, value) in arguments { payload[key] = value }
        return try await rpc("isg_drills_read_v1", payload)
    }

    // MARK: reads

    /// The plans in force that a drill may rehearse, and the people who could
    /// have taken part. An empty plan list is the honest answer: a drill has
    /// nowhere to point without one.
    func catalogue(_ identity: NovaSessionIdentity, company: UUID?) async throws -> NovaDrillCatalogue {
        try check(identity)
        let data = try await read(["p_company": company.map { .id($0) } ?? .null,
                                   "p_kind": .string("catalog")])
        try check(identity)
        let envelope = try JSONDecoder().decode(CatalogEnvelope.self, from: data)
        return .init(plans: envelope.plans.map { .init(planID: $0.plan_id, version: $0.version,
                                                       scope: $0.scope, workplaceID: $0.workplace_id,
                                                       workplaceName: $0.workplace_name,
                                                       validUntil: $0.valid_until) },
                     employees: envelope.employees.map { .init(id: $0.id, fullName: $0.full_name) },
                     noticeDays: envelope.notice_days,
                     periodDefaultsOffered: envelope.period_defaults_offered)
    }

    func board(_ identity: NovaSessionIdentity, query: NovaDrillQuery) async throws -> NovaDrillBoard {
        try check(identity)
        let needle = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try await read([
            "p_company": query.company.map { .id($0) } ?? .null,
            "p_kind": .string("list"),
            "p_query": needle.isEmpty ? .null : .string(needle),
            "p_state": query.state.map { .string($0) } ?? .null,
            "p_workplace": query.workplace.map { .id($0) } ?? .null,
            "p_limit": .number(Int64(query.limit)), "p_offset": .number(Int64(query.offset))])
        try check(identity)
        let envelope = try JSONDecoder().decode(ListEnvelope.self, from: data)
        return .init(rows: envelope.rows.map(drill), counts: envelope.counts,
                     companies: envelope.companies.map { .init(id: $0.id, name: $0.name, total: $0.total,
                                                               counts: $0.counts) },
                     total: envelope.total, hasMore: envelope.has_more, offset: envelope.offset,
                     noticeDays: envelope.notice_days)
    }

    func detail(_ identity: NovaSessionIdentity, drill id: UUID) async throws -> NovaDrill {
        try check(identity)
        let data = try await read(["p_kind": .string("detail"), "p_id": .id(id)])
        try check(identity)
        return drill(try JSONDecoder().decode(DetailEnvelope.self, from: data).row)
    }

    // MARK: writes

    private func mutate(_ identity: NovaSessionIdentity, company: UUID, action: String,
                        payload: [String: PersonnelRPCValue]) async throws -> NovaDrill? {
        try check(identity)
        return try await NovaModuleMutationJournal.run(function: "isg_drills_mutate_v1", identity: identity,
            company: company, action: action, payload: payload, rpc: rpc,
            validate: { try check(identity) }, decode: { data in
                return try JSONDecoder().decode(MutationEnvelope.self, from: data).row.map(drill)
            })
    }

    /// Planning names a plan, never a version: the server pins the one in force
    /// so a drill cannot be aimed at a version the expert did not see.
    func plan(_ identity: NovaSessionIdentity, company: UUID,
              draft: NovaDrillPlanDraft) async throws -> NovaDrill? {
        guard let plan = draft.planID, NovaDayField.date(draft.plannedOn) != nil else {
            throw NovaDrillFailure.validation
        }
        return try await mutate(identity, company: company, action: "plan_drill",
                                payload: ["plan_id": .id(plan), "planned_on": .string(draft.plannedOn)])
    }

    func record(_ identity: NovaSessionIdentity, company: UUID,
                draft: NovaDrillResultDraft) async throws -> NovaDrill? {
        guard let drill = draft.drillID, !draft.participants.isEmpty,
              NovaDayField.date(draft.performedOn) != nil else { throw NovaDrillFailure.validation }
        var payload: [String: PersonnelRPCValue] = [
            "drill_id": .id(drill), "performed_on": .string(draft.performedOn),
            "participants": .array(draft.participants.map { .string($0.uuidString) })]
        let observation = draft.observation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !observation.isEmpty { payload["observation"] = .string(observation) }
        let improvement = draft.improvement.trimmingCharacters(in: .whitespacesAndNewlines)
        if !improvement.isEmpty { payload["improvement"] = .string(improvement) }
        return try await mutate(identity, company: company, action: "record_result", payload: payload)
    }

    /// Only a planned drill can be withdrawn, and only with a reason.
    func cancel(_ identity: NovaSessionIdentity, company: UUID, drill id: UUID,
                reason: String) async throws -> NovaDrill? {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NovaDrillFailure.validation }
        return try await mutate(identity, company: company, action: "cancel_drill",
                                payload: ["drill_id": .id(id), "reason": .string(trimmed)])
    }
}
