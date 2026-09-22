import Foundation

/// The expert UI has one implementation. Its data boundary is either the
/// signed-in user's personal workspace or an explicitly selected organization.
/// These values describe a request; they never grant server-side authority.
struct NovaExpertAccess: Equatable {
    let identity: NovaSessionIdentity
    let workspace: NovaWorkspaceSelection?

    var storageNamespace: String {
        "\(identity.userID.uuidString.lowercased()):\(workspace?.workspaceID.uuidString.lowercased() ?? "personal")"
    }

    var workspaceID: UUID? { workspace?.workspaceID }

    /// Company ownership belongs to the organization manager. Assignment to
    /// a company authorizes its safety records, not changing its ownership data.
    var canManageCompany: Bool { workspace == nil }
    var canOperate: Bool { workspace?.canOperate ?? true }
    var usesOrganizationEntitlements: Bool { workspace?.kind == "osgb" }

    func validate(identity currentIdentity: NovaSessionIdentity?, workspace currentWorkspace: NovaWorkspaceSelection?) throws {
        guard identity == currentIdentity, workspace == currentWorkspace,
              workspace == nil || (workspace?.userID == identity.userID && workspace?.canRead == true)
        else { throw NovaPersonnelFailure.denied }
    }
}
