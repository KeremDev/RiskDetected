import Foundation

enum RDLocalizationTable { case localizable }
enum RDLocalization {
    static func string(_ key: String, table: RDLocalizationTable, fallback: String) -> String { fallback }
}

@main enum WorkspaceSessionCheck {
    static func main() {
        let user = UUID()
        let actor = NovaSessionIdentity(userID: user, sessionID: UUID())
        let first = NovaWorkspaceSelection(workspaceID: UUID(), membershipID: UUID(), userID: user,
            kind: "personal", permissionRevision: 0, workspaceVersion: 0, canRead: true, canOperate: true)
        let second = NovaWorkspaceSelection(workspaceID: UUID(), membershipID: UUID(), userID: user,
            kind: "osgb", permissionRevision: 4, workspaceVersion: 2, canRead: true, canOperate: true)
        var host = NovaSessionHost(implemented: [.companies, .findings])
        host.adopt(actor)
        let personalTicket = host.beginWorkspaceSwitch(to: first)!
        precondition(host.phase == .resolving && host.workspace == first)
        precondition(host.resolve(personalTicket, ownerID: user, enabled: [.companies]))
        let oldEpoch = host.navigation.epoch
        let oldValue = host.scope("personal", from: oldEpoch)
        let oldTicket = host.beginAvailabilityRefresh()!
        let osgbTicket = host.beginWorkspaceSwitch(to: second)!
        precondition(host.workspace == second && host.navigation.epoch != oldEpoch)
        precondition(host.resolve(oldTicket, ownerID: user, enabled: [.companies]) == false)
        precondition(host.value(from: oldValue) == nil)
        precondition(host.resolve(osgbTicket, ownerID: user, enabled: [.companies, .findings]))
        let epoch = host.navigation.epoch
        precondition(host.isCurrent(epoch, workspaceID: second.workspaceID, permissionRevision: 4))
        precondition(!host.isCurrent(epoch, workspaceID: first.workspaceID, permissionRevision: 0))
        let revised = NovaWorkspaceSelection(workspaceID: second.workspaceID, membershipID: second.membershipID,
            userID: user, kind: "osgb", permissionRevision: 5, workspaceVersion: 2,
            canRead: true, canOperate: true)
        precondition(host.beginWorkspaceSwitch(to: revised) != nil)
        precondition(!host.isCurrent(epoch, workspaceID: second.workspaceID, permissionRevision: 4))
        let foreign = NovaWorkspaceSelection(workspaceID: UUID(), membershipID: UUID(), userID: UUID(),
            kind: "osgb", permissionRevision: 0, workspaceVersion: 0, canRead: true, canOperate: true)
        let before = host.navigation.epoch
        precondition(host.beginWorkspaceSwitch(to: foreign) == nil && host.navigation.epoch == before)
        print("PASS Swift workspace session: switch, stale callback, revision and foreign-user guards")
    }
}
