import Foundation

/// Local presentation identity supplied by the trusted Auth owner, never user metadata or a URL.
/// A token refresh retains sessionID; logout/re-login must adopt the new sessionID.
struct NovaSessionIdentity: Equatable {
    let userID: UUID
    let sessionID: UUID
}

/// The selected server context, reduced to the fields needed to invalidate UI work.
/// It is a cache boundary, never an authorization decision.
struct NovaWorkspaceSelection: Equatable {
    let workspaceID: UUID
    let membershipID: UUID
    let userID: UUID
    let kind: String
    let permissionRevision: Int64
    let workspaceVersion: Int64
    let canRead: Bool
    let canOperate: Bool

    var isStructurallyValid: Bool {
        ["personal", "osgb"].contains(kind) && permissionRevision >= 0 &&
        permissionRevision <= 9_007_199_254_740_991 && workspaceVersion >= 0 &&
        workspaceVersion <= 9_007_199_254_740_991
    }
}

enum NovaHostPhase: String { case signedOut, resolving, ready, failed }

struct NovaAvailabilityTicket: Equatable {
    fileprivate let id: UUID
    fileprivate let epoch: String
    fileprivate let identity: NovaSessionIdentity
    fileprivate let workspace: NovaWorkspaceSelection?
}

/// Opaque, in-memory value. Read through the CURRENT host, not a captured host snapshot.
struct NovaScopedValue<Value> {
    fileprivate let epoch: String
    fileprivate let value: Value
}

/// Value-state reducer. Serialize all access on the UI owner (MainActor); not server authorization.
/// No Auth SDK, billing inference, persistence, token parsing, company grants or network calls.
struct NovaSessionHost {
    private(set) var identity: NovaSessionIdentity?
    private(set) var workspace: NovaWorkspaceSelection?
    private(set) var phase: NovaHostPhase = .signedOut
    private(set) var navigation = NovaNavigationState(epoch: UUID().uuidString, available: [])
    private(set) var pending: NovaAvailabilityTicket?
    private let implemented: Set<NovaDestination>

    init(implemented: Set<NovaDestination>) { self.implemented = implemented }

    /// Duplicate Auth/token-refresh events do not erase paths or invalidate an in-flight load.
    mutating func adopt(_ next: NovaSessionIdentity?) {
        guard identity != next else { return }
        identity = next
        workspace = nil
        invalidate()
        phase = next == nil ? .signedOut : .resolving
    }

    /// Explicit permission revalidation hides old content and invalidates every old callback.
    /// A retry also supersedes its predecessor even when the user/session is unchanged.
    mutating func beginAvailabilityRefresh() -> NovaAvailabilityTicket? {
        guard let identity else { return nil }
        invalidate()
        phase = .resolving
        let ticket = NovaAvailabilityTicket(id: UUID(), epoch: navigation.epoch, identity: identity, workspace: workspace)
        pending = ticket
        return ticket
    }

    /// A workspace change is an account-scope boundary: hide the previous workspace
    /// immediately and require a new availability result before rendering content.
    mutating func beginWorkspaceSwitch(to next: NovaWorkspaceSelection) -> NovaAvailabilityTicket? {
        guard let identity, next.isStructurallyValid, next.canRead,
              next.userID == identity.userID, workspace != next else { return nil }
        workspace = next
        invalidate()
        phase = .resolving
        let ticket = NovaAvailabilityTicket(id: UUID(), epoch: navigation.epoch, identity: identity, workspace: next)
        pending = ticket
        return ticket
    }

    @discardableResult
    mutating func resolve(_ ticket: NovaAvailabilityTicket, ownerID: UUID, enabled: Set<NovaDestination>) -> Bool {
        guard matches(ticket) else { return false }
        pending = nil
        guard ownerID == identity?.userID else { phase = .failed; return false }
        navigation.updateAvailability(enabled.intersection(implemented), from: navigation.epoch)
        phase = .ready
        return true
    }

    @discardableResult
    mutating func fail(_ ticket: NovaAvailabilityTicket) -> Bool {
        guard matches(ticket) else { return false }
        pending = nil
        phase = .failed
        return true
    }

    mutating func apply(_ event: NovaNavigationEvent, from epoch: String) {
        guard phase == .ready else { return }
        navigation.apply(event, from: epoch)
    }

    /// SwiftUI Binding bridge. An old child cannot replace the current account or capability set.
    mutating func acceptNavigation(_ next: NovaNavigationState, from epoch: String) {
        guard isCurrent(epoch), next.epoch == navigation.epoch,
              next.available == navigation.available else { return }
        navigation = next
    }

    func isCurrent(_ epoch: String) -> Bool { phase == .ready && epoch == navigation.epoch }

    func isCurrent(_ epoch: String, workspaceID: UUID, permissionRevision: Int64) -> Bool {
        isCurrent(epoch) && workspace?.workspaceID == workspaceID &&
        workspace?.permissionRevision == permissionRevision
    }

    /// Does NOT implement latest-request-wins within an epoch: feature loaders must also compare
    /// their own request ID, company scope and query before publishing a response.
    func scope<Value>(_ value: Value, from epoch: String) -> NovaScopedValue<Value>? {
        guard isCurrent(epoch) else { return nil }
        return NovaScopedValue(epoch: epoch, value: value)
    }

    func value<Value>(from snapshot: NovaScopedValue<Value>?) -> Value? {
        guard let snapshot, isCurrent(snapshot.epoch) else { return nil }
        return snapshot.value
    }

    private func matches(_ ticket: NovaAvailabilityTicket) -> Bool {
        phase == .resolving && pending == ticket && identity == ticket.identity &&
        workspace == ticket.workspace && navigation.epoch == ticket.epoch
    }

    private mutating func invalidate() {
        pending = nil
        navigation = NovaNavigationState(epoch: UUID().uuidString, available: [])
    }
}
