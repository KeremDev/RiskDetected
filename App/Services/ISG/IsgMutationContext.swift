import Foundation

/// Transport validation only; a valid scope never grants database access.
struct IsgMutationContext: Decodable, Equatable {
    let schemaVersion: Int
    let operationID: String
    let clientMutationID: String
    let platform: String
    let clientBuild: Int
    let expectedVersion: Int64
    let scope: Scope

    struct Scope: Decodable, Equatable {
        let kind: String
        let companyID: String?
        let workplaceID: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            kind = try c.decode(String.self, forKey: Key("kind"))
            if kind == "personal" {
                guard Set(c.allKeys.map(\.stringValue)) == ["kind"] else { throw Invalid.context }
                companyID = nil
                workplaceID = nil
            } else if kind == "company" {
                guard Set(c.allKeys.map(\.stringValue)).isSubset(of: ["kind", "company_id", "workplace_id"]) else { throw Invalid.context }
                let company = try c.decode(String.self, forKey: Key("company_id"))
                guard IsgMutationContext.validID(company) else { throw Invalid.context }
                companyID = company
                if c.contains(Key("workplace_id")) {
                    let workplace = try c.decode(String.self, forKey: Key("workplace_id"))
                    guard IsgMutationContext.validID(workplace) else { throw Invalid.context }
                    workplaceID = workplace
                } else { workplaceID = nil }
            } else { throw Invalid.context }
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let allowed: Set<String> = ["schema_version", "operation_id", "client_mutation_id", "platform", "client_build", "expected_version", "scope"]
        guard Set(c.allKeys.map(\.stringValue)) == allowed else { throw Invalid.context }
        schemaVersion = try c.decode(Int.self, forKey: Key("schema_version"))
        operationID = try c.decode(String.self, forKey: Key("operation_id"))
        clientMutationID = try c.decode(String.self, forKey: Key("client_mutation_id"))
        platform = try c.decode(String.self, forKey: Key("platform"))
        clientBuild = try c.decode(Int.self, forKey: Key("client_build"))
        expectedVersion = try c.decode(Int64.self, forKey: Key("expected_version"))
        scope = try c.decode(Scope.self, forKey: Key("scope"))
        guard schemaVersion == 1, Self.validID(operationID), Self.validID(clientMutationID),
              ["ios", "android"].contains(platform), (1...2147483647).contains(clientBuild),
              (0...9007199254740991).contains(expectedVersion) else { throw Invalid.context }
    }

    private static func validID(_ value: String) -> Bool {
        value.utf8.count == 36 && value.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", options: .regularExpression) != nil
    }
    private enum Invalid: Error { case context }
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

/// Strict transport mirror of `isg_workspace_context_v1`. This is presentation state;
/// the server remains the only authorization authority.
struct IsgWorkspaceContext: Decodable, Equatable {
    let schemaVersion: Int
    let workspaceID: UUID
    let kind: String
    let name: String
    let status: String
    let timezone: String
    let workspaceVersion: Int64
    let membership: Membership
    let canRead: Bool
    let canOperate: Bool
    let canManageMembers: Bool
    let canManageBilling: Bool

    struct Membership: Decodable, Equatable {
        let membershipID: UUID
        let userID: UUID
        let role: String
        let status: String
        let isPracticingExpert: Bool
        let permissionRevision: Int64
        let membershipVersion: Int64

        enum CodingKeys: String, CodingKey, CaseIterable {
            case membershipID = "membership_id", userID = "user_id", role, status
            case isPracticingExpert = "is_practicing_expert"
            case permissionRevision = "permission_revision", membershipVersion = "membership_version"
        }

        init(from decoder: Decoder) throws {
            let raw = try decoder.container(keyedBy: IsgWorkspaceKey.self)
            guard Set(raw.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else { throw Invalid.context }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            membershipID = try c.decode(UUID.self, forKey: .membershipID)
            userID = try c.decode(UUID.self, forKey: .userID)
            role = try c.decode(String.self, forKey: .role)
            status = try c.decode(String.self, forKey: .status)
            isPracticingExpert = try c.decode(Bool.self, forKey: .isPracticingExpert)
            permissionRevision = try c.decode(Int64.self, forKey: .permissionRevision)
            membershipVersion = try c.decode(Int64.self, forKey: .membershipVersion)
        }

        private enum Invalid: Error { case context }
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version", workspaceID = "workspace_id", kind, name, status, timezone
        case workspaceVersion = "workspace_version", membership
        case canRead = "can_read", canOperate = "can_operate"
        case canManageMembers = "can_manage_members", canManageBilling = "can_manage_billing"
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: IsgWorkspaceKey.self)
        guard Set(raw.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else { throw Invalid.context }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        workspaceID = try c.decode(UUID.self, forKey: .workspaceID)
        kind = try c.decode(String.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        status = try c.decode(String.self, forKey: .status)
        timezone = try c.decode(String.self, forKey: .timezone)
        workspaceVersion = try c.decode(Int64.self, forKey: .workspaceVersion)
        membership = try c.decode(Membership.self, forKey: .membership)
        canRead = try c.decode(Bool.self, forKey: .canRead)
        canOperate = try c.decode(Bool.self, forKey: .canOperate)
        canManageMembers = try c.decode(Bool.self, forKey: .canManageMembers)
        canManageBilling = try c.decode(Bool.self, forKey: .canManageBilling)
        guard schemaVersion == 1,
              ["personal", "osgb"].contains(kind),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 200,
              !timezone.isEmpty, timezone.utf8.count <= 80,
              ["active", "pending_purchase", "admin_trial", "admin_sponsored", "suspended", "archived"].contains(status),
              (0...9007199254740991).contains(workspaceVersion),
              ["owner", "admin", "expert"].contains(membership.role),
              ["active", "suspended", "ended"].contains(membership.status),
              (0...9007199254740991).contains(membership.permissionRevision),
              (0...9007199254740991).contains(membership.membershipVersion),
              !membership.isPracticingExpert || (kind == "osgb" && membership.status == "active"),
              kind != "personal" || (membership.role == "owner" && membership.status == "active" && !membership.isPracticingExpert),
              canRead == (membership.status == "active" && ["active", "pending_purchase", "admin_trial", "admin_sponsored"].contains(status)),
              canOperate == (membership.status == "active" && ["active", "admin_trial", "admin_sponsored"].contains(status)),
              canManageMembers == (canRead && ["owner", "admin"].contains(membership.role)),
              canManageBilling == (canRead && membership.role == "owner") else { throw Invalid.context }
    }

    private enum Invalid: Error { case context }
}

private struct IsgWorkspaceKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
