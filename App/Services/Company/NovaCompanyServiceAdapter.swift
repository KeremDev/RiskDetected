import Foundation
import Supabase

struct NovaPilotCompanySummary: Decodable, Identifiable {
    let id: UUID
    let owner_id: UUID
    let name: String
    let hazard_class: String
    let is_archived: Bool
    let sector: String?
    let email: String?
    let declared_employee_count: Int?
    let responsible_employee_id: UUID?
    let personnel_count: Int
    let workplace_count: Int
    let department_count: Int
    let finding_count: Int?
    let document_count: Int?
    let completion_score: Double?
    var responsible_name: String? = nil
    var responsible_phone: String? = nil
    var responsible_email: String? = nil
}

@MainActor func loadNovaPilotOverview(identity: NovaSessionIdentity, companyID: UUID? = nil) async throws -> [NovaPilotCompanySummary] {
    func check() throws {
        try Task.checkCancellation()
        guard novaCurrentSessionIdentity() == identity else { throw NovaPersonnelFailure.denied }
    }
    try check()
    let data = try await NovaExpertTransport.shared.execute("isg_pilot_overview_v2",
        params: ["p_company": PersonnelRPCValue.id(companyID)], ticket: NovaExpertTransport.shared.capture())
    try check()
    guard data.count <= 1_048_576 else { throw NovaPersonnelFailure.unavailable }
    struct Response: Decodable {
        let schema_version: Int; let owner_id: UUID; let company_id: UUID?; let companies: [NovaPilotCompanySummary]
    }
    let response = try JSONDecoder().decode(Response.self, from: data)
    guard response.schema_version == 2, response.owner_id == identity.userID, response.company_id == companyID,
          Set(response.companies.map(\.id)).count == response.companies.count,
          response.companies.allSatisfy({ $0.owner_id == identity.userID && (companyID == nil || $0.id == companyID) &&
              $0.personnel_count >= 0 && $0.workplace_count >= 0 && $0.department_count >= 0 && ["low", "medium", "high"].contains($0.hazard_class) })
    else { throw NovaPersonnelFailure.denied }
    return response.companies
}

/// Production composition adapter, deliberately outside the offline design/test targets.
/// The existing service remains the only query path; server RLS remains authoritative.
@MainActor
func loadNovaOwnedCompanies(includeArchived: Bool) async throws -> [NovaOwnedCompany] {
    try await CompanyService.shared.listCompanies(includeArchived: includeArchived).map { company in
        let address = company.address?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = [address?.isEmpty == false ? address : nil, company.hazardClass.title]
            .compactMap { $0 }.joined(separator: " · ")
        let progressCompleted = [company.address, company.city, company.phone, company.naceCode,
            company.workplaceRegistryNo, company.department, company.contactPerson,
            company.defaultResponsible].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.count
        return NovaOwnedCompany(id: company.id, ownerID: company.userID, name: company.name,
            detail: detail, isArchived: company.isArchived, progressCompleted: progressCompleted, progressTotal: 8)
    }
}

/// Account identity only chooses presentation; every company is checked by the server.
@MainActor func novaCurrentSessionIdentity() -> NovaSessionIdentity? {
    guard let session = SupabaseService.shared.client.auth.currentSession,
          let sessionID = NovaPersonnelService.sessionID(session.accessToken) else { return nil }
    return .init(userID: session.user.id, sessionID: sessionID)
}

extension NovaPilotCompanyService {
    @MainActor static func live() -> NovaPilotCompanyService {
        .init(rpc: { name, args in
            try await NovaExpertTransport.shared.execute(name, params: args, ticket: NovaExpertTransport.shared.capture())
        }, currentIdentity: novaCurrentSessionIdentity,
        storage: KeychainPersonnelPendingStorage(service: "com.riskdetected.pilot.company.pending.v1"))
    }
}

/// Existing owned-list query is read-only. Do not publish any row until its pilot
/// origin/grant AND the current session have been verified. Any partial failure fails closed.
@MainActor func loadNovaPilotCompanies(identity: NovaSessionIdentity, includeArchived: Bool) async throws -> [NovaOwnedCompany] {
    func check() throws {
        try Task.checkCancellation()
        guard novaCurrentSessionIdentity() == identity else { throw NovaPersonnelFailure.denied }
    }
    try check()
    let candidates = try await loadNovaOwnedCompanies(includeArchived: includeArchived)
    try check()
    var result: [NovaOwnedCompany] = []
    for row in candidates {
        guard row.ownerID == identity.userID else { throw NovaPersonnelFailure.denied }
        let data = try await NovaExpertTransport.shared.execute("isg_workspace_availability_v1", params: ["p_company": PersonnelRPCValue.id(row.id)], ticket: NovaExpertTransport.shared.capture())
        try check()
        let capability = try NovaWorkspaceCapability.decode(data, owner: identity.userID, company: row.id)
        if capability.can_read {
            result.append(.init(id: row.id, ownerID: row.ownerID, name: capability.company_name ?? row.name,
                detail: row.detail, isArchived: capability.is_archived ?? row.isArchived,
                progressCompleted: 0, progressTotal: 8))
        }
    }
    // Also recheck the account gate, including the zero-company case.
    let data = try await NovaExpertTransport.shared.execute("isg_workspace_availability_v1", params: ["p_company": PersonnelRPCValue.null], ticket: NovaExpertTransport.shared.capture())
    try check()
    guard try NovaWorkspaceCapability.decode(data, owner: identity.userID, company: nil).can_read else { throw NovaPersonnelFailure.denied }
    return result
}
