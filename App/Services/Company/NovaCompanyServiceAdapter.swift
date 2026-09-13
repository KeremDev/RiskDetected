import Foundation

/// Production composition adapter, deliberately outside the offline design/test targets.
/// The existing service remains the only query path; server RLS remains authoritative.
@MainActor
func loadNovaOwnedCompanies(includeArchived: Bool) async throws -> [NovaOwnedCompany] {
    try await CompanyService.shared.listCompanies(includeArchived: includeArchived).map { company in
        let address = company.address?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = [address?.isEmpty == false ? address : nil, company.hazardClass.title]
            .compactMap { $0 }.joined(separator: " · ")
        return NovaOwnedCompany(id: company.id, ownerID: company.userID, name: company.name,
            detail: detail, isArchived: company.isArchived)
    }
}
