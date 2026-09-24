import Foundation

/// Same shape as the other module services: a plain RPC closure, a session
/// check and no SDK type in the design system.
@MainActor struct NovaEmergencyPlanService {
    typealias RPC = (String, [String: PersonnelRPCValue]) async throws -> Data
    private let rpc: RPC
    private let isSession: (NovaSessionIdentity) -> Bool

    init(rpc: @escaping RPC, isSession: @escaping (NovaSessionIdentity) -> Bool) {
        self.rpc = rpc; self.isSession = isSession
    }

    private func check(_ identity: NovaSessionIdentity) throws {
        guard isSession(identity) else { throw NovaEmergencyFailure.denied }
    }

    // MARK: transport rows

    private struct MemberRow: Decodable {
        let full_name: String
        let role: String
        let contact: String?
    }
    private struct VersionRow: Decodable {
        let version: Int
        let state: String
        let scope: String
        let prepared_on: String
        let valid_until: String?
        let needs_review: Bool
        let review_note: String?
        let team: [MemberRow]?
        let asset_id: UUID?
        let created_at: String?
    }
    private struct AssetDownloadRow: Decodable { let bucket: String; let path: String }
    private struct PlanRow: Decodable {
        let id: UUID
        var company_id: UUID?
        var company_name: String?
        let workplace_id: UUID?
        var workplace_name: String?
        let version: Int
        let versions_total: Int
        let scope: String
        let prepared_on: String
        let valid_until: String?
        let state: String
        let notice_days: Int
        let needs_review: Bool
        let review_note: String?
        let team: [MemberRow]?
        let team_size: Int
        let asset_id: UUID?
        let asset_download: AssetDownloadRow?
        let versions: [VersionRow]?
    }
    private struct WorkplaceRow: Decodable {
        let id: UUID; let name: String; let needs_review: Bool
        let hazard_class: String?; let suggested_period_years: Int?
    }
    private struct RoleRow: Decodable { let code: String; let ordinal: Int }
    private struct SupportStaffRow: Decodable {
        let appointment_id: UUID
        let employee_id: UUID
        let full_name: String
        let workplace_id: UUID?
        let workplace_name: String?
    }
    private struct CatalogEnvelope: Decodable {
        let workplaces: [WorkplaceRow]
        let team_roles: [RoleRow]
        let support_staff: [SupportStaffRow]?
        let notice_days: Int
        let period_defaults_offered: Bool
    }
    private struct CompanyRow: Decodable { let id: UUID; let name: String; let total: Int; let counts: [String: Int] }
    private struct ListEnvelope: Decodable {
        let rows: [PlanRow]
        let companies: [CompanyRow]
        let counts: [String: Int]
        let total: Int
        let has_more: Bool
        let offset: Int
        let notice_days: Int
    }
    private struct DetailEnvelope: Decodable { let row: PlanRow }
    private struct MutationEnvelope: Decodable { let plan_id: UUID?; let row: PlanRow? }

    private func members(_ rows: [MemberRow]?) -> [NovaEmergencyMember] {
        (rows ?? []).compactMap { entry in
            guard let role = NovaEmergencyRole(rawValue: entry.role) else { return nil }
            return NovaEmergencyMember(fullName: entry.full_name, role: role, contact: entry.contact)
        }
    }

    /// An unknown state word is reported as never published rather than smoothed
    /// into the calmest answer: the expert should look at the plan.
    private func plan(_ entry: PlanRow) -> NovaEmergencyPlan {
        let state = NovaEmergencyState(rawValue: entry.state) ?? .neverPublished
        let versions: [NovaEmergencyVersion] = (entry.versions ?? []).map { version in
            NovaEmergencyVersion(version: version.version, state: version.state, scope: version.scope,
                                 preparedOn: version.prepared_on, validUntil: version.valid_until,
                                 needsReview: version.needs_review, reviewNote: version.review_note,
                                 team: members(version.team), assetID: version.asset_id,
                                 createdAt: version.created_at)
        }
        return NovaEmergencyPlan(
            id: entry.id, companyID: entry.company_id, companyName: entry.company_name,
            workplaceID: entry.workplace_id, workplaceName: entry.workplace_name,
            version: entry.version, versionsTotal: entry.versions_total,
            scope: entry.scope, preparedOn: entry.prepared_on, validUntil: entry.valid_until,
            state: state, group: NovaEmergencyGroup.of(state), noticeDays: entry.notice_days,
            needsReview: entry.needs_review, reviewNote: entry.review_note,
            team: members(entry.team), teamSize: entry.team_size,
            assetID: entry.asset_id,
            assetDownload: entry.asset_download.map { .init(bucket: $0.bucket, path: $0.path) },
            versions: versions)
    }

    private func read(_ arguments: [String: PersonnelRPCValue]) async throws -> Data {
        var payload: [String: PersonnelRPCValue] = [
            "p_company": .null, "p_kind": .string("list"), "p_query": .null, "p_state": .null,
            "p_workplace": .null, "p_id": .null, "p_limit": .null, "p_offset": .null]
        for (key, value) in arguments { payload[key] = value }
        return try await rpc("isg_emergency_plans_read_v1", payload)
    }

    // MARK: reads

    func catalogue(_ identity: NovaSessionIdentity, company: UUID?) async throws -> NovaEmergencyCatalogue {
        try check(identity)
        let data = try await read(["p_company": company.map { .id($0) } ?? .null,
                                   "p_kind": .string("catalog")])
        try check(identity)
        let envelope = try JSONDecoder().decode(CatalogEnvelope.self, from: data)
        return .init(workplaces: envelope.workplaces.map { .init(id: $0.id, name: $0.name, needsReview: $0.needs_review,
                     hazardClass: $0.hazard_class, suggestedPeriodYears: $0.suggested_period_years) },
                     roles: envelope.team_roles.sorted { $0.ordinal < $1.ordinal }
                        .compactMap { NovaEmergencyRole(rawValue: $0.code) },
                     supportStaff: (envelope.support_staff ?? []).map {
                        .init(id: $0.employee_id, fullName: $0.full_name, workplaceName: $0.workplace_name) },
                     noticeDays: envelope.notice_days,
                     periodDefaultsOffered: envelope.period_defaults_offered)
    }

    func board(_ identity: NovaSessionIdentity, query: NovaEmergencyQuery) async throws -> NovaEmergencyBoard {
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
        return .init(rows: envelope.rows.map(plan), counts: envelope.counts,
                     companies: envelope.companies.map { .init(id: $0.id, name: $0.name, total: $0.total,
                                                               counts: $0.counts) },
                     total: envelope.total, hasMore: envelope.has_more, offset: envelope.offset,
                     noticeDays: envelope.notice_days)
    }

    func detail(_ identity: NovaSessionIdentity, plan id: UUID) async throws -> NovaEmergencyPlan {
        try check(identity)
        let data = try await read(["p_kind": .string("detail"), "p_id": .id(id)])
        try check(identity)
        return plan(try JSONDecoder().decode(DetailEnvelope.self, from: data).row)
    }

    // MARK: writes

    /// Publishing is the only write. There is no edit: correcting a plan means
    /// publishing the next version, and the one before it keeps everything.
    func publish(_ identity: NovaSessionIdentity, company: UUID,
                 draft: NovaEmergencyPlanDraft) async throws -> NovaEmergencyPlan? {
        guard !draft.team.isEmpty else {
            throw NovaEmergencyFailure.validation
        }
        var payload: [String: PersonnelRPCValue] = [
            "workplace_id": draft.workplaceID.map(PersonnelRPCValue.id) ?? .null,
            "scope": .string(draft.scope.trimmingCharacters(in: .whitespacesAndNewlines)),
            "prepared_on": .string(draft.preparedOn),
            // Only the three keys the server's snapshot check accepts.
            "team": .array(draft.team.map { member in
                var entry: [String: PersonnelRPCValue] = [
                    "full_name": .string(member.fullName), "role": .string(member.role.rawValue)]
                if let contact = member.contact, !contact.isEmpty { entry["contact"] = .string(contact) }
                return .object(entry)
            })]
        if let plan = draft.planID { payload["plan_id"] = .id(plan) }
        if NovaDayField.date(draft.validUntil) != nil { payload["valid_until"] = .string(draft.validUntil) }
        if let asset = draft.assetID { payload["asset_id"] = .id(asset) }
        let note = draft.reviewNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { payload["review_note"] = .string(note) }
        try check(identity)
        return try await NovaModuleMutationJournal.run(function: "isg_emergency_plans_mutate_v1", identity: identity,
            company: company, action: "publish_plan", payload: payload, rpc: rpc,
            validate: { try check(identity) }, decode: { data in
                return try JSONDecoder().decode(MutationEnvelope.self, from: data).row.map(plan)
            })
    }
}
