import Foundation

/// Presentation hint only. Mutation endpoints always recheck authority.
struct NovaWorkspaceCapability: Decodable {
    let schema_version: Int; let owner_id: UUID; let company_id: UUID?
    let company_name: String?; let is_archived: Bool?; let can_read: Bool; let can_write: Bool
    static func decode(_ data: Data, owner: UUID, company: UUID?) throws -> Self {
        guard data.count <= 16384 else { throw NovaPersonnelFailure.unavailable }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schema_version == 1, value.owner_id == owner, value.company_id == company,
              !value.can_write || (value.can_read && company != nil && value.is_archived == false),
              !value.can_read || company == nil || (value.company_name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && value.is_archived != nil),
              company != nil || (value.company_name == nil && value.is_archived == nil && !value.can_write) else { throw NovaPersonnelFailure.unavailable }
        return value
    }
}
