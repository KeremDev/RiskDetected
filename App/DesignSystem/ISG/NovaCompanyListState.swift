import Foundation

/// Authorized service output projected for display. Ownership is checked again defensively;
/// this model never grants backend access and contains no credentials or persisted cache.
struct NovaOwnedCompany: Equatable {
    let id: UUID
    let ownerID: UUID
    let name: String
    let detail: String
    let isArchived: Bool
    var progressCompleted: Int = 0
    var progressTotal: Int = 8
    var logoPath: String? = nil
}

enum NovaCompanyListPhase: String { case idle, loading, loaded, failed }
struct NovaCompanyListContent {
    let phase: NovaCompanyListPhase
    let requestID: UUID?
    let rows: [NovaOwnedCompany]
    var includeArchived = false
    static let idle = Self(phase: .idle, requestID: nil, rows: [])
}
struct NovaCompanyListTicket: Equatable {
    fileprivate let id: UUID
    fileprivate let epoch: String
    fileprivate let ownerID: UUID
    fileprivate let includeArchived: Bool
}

/// MainActor-owned value state. Always supply the current host, not a pre-await snapshot.
struct NovaCompanyListState {
    private(set) var pending: NovaCompanyListTicket?
    private var snapshot: NovaScopedValue<NovaCompanyListContent>?

    mutating func begin(host: NovaSessionHost, includeArchived: Bool = false) -> NovaCompanyListTicket? {
        pending = nil
        snapshot = nil
        guard allowed(host), let owner = host.identity?.userID else { return nil }
        let ticket = NovaCompanyListTicket(id: UUID(), epoch: host.navigation.epoch, ownerID: owner, includeArchived: includeArchived)
        pending = ticket
        snapshot = host.scope(.init(phase: .loading, requestID: ticket.id, rows: [], includeArchived: ticket.includeArchived), from: ticket.epoch)
        return ticket
    }

    @discardableResult
    mutating func complete(_ ticket: NovaCompanyListTicket, rows: [NovaOwnedCompany], host: NovaSessionHost) -> Bool {
        guard matches(ticket, host) else { return false }
        let valid = Set(rows.map(\.id)).count == rows.count && rows.allSatisfy {
            $0.ownerID == ticket.ownerID && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        pending = nil
        snapshot = host.scope(.init(phase: valid ? .loaded : .failed, requestID: ticket.id,
            rows: valid ? rows.filter { ticket.includeArchived || !$0.isArchived } : [], includeArchived: ticket.includeArchived), from: ticket.epoch)
        return true
    }

    @discardableResult
    mutating func fail(_ ticket: NovaCompanyListTicket, host: NovaSessionHost) -> Bool {
        guard matches(ticket, host) else { return false }
        pending = nil
        snapshot = host.scope(.init(phase: .failed, requestID: ticket.id, rows: [], includeArchived: ticket.includeArchived), from: ticket.epoch)
        return true
    }

    mutating func cancel(_ ticket: NovaCompanyListTicket, host: NovaSessionHost) {
        guard matches(ticket, host) else { return }
        pending = nil
        snapshot = nil
    }

    func content(host: NovaSessionHost, includeArchived: Bool = false) -> NovaCompanyListContent {
        guard allowed(host), let current = host.value(from: snapshot), current.includeArchived == includeArchived else { return .idle }
        return current
    }

    /// Also rejects a tap from the previous list render after a same-session refresh.
    func select(_ id: UUID, requestID: UUID?, host: NovaSessionHost, includeArchived: Bool = false) -> NovaOwnedCompany? {
        let current = content(host: host, includeArchived: includeArchived)
        guard current.phase == .loaded, let requestID, current.requestID == requestID else { return nil }
        return current.rows.first { $0.id == id }
    }

    private func allowed(_ host: NovaSessionHost) -> Bool {
        host.phase == .ready && host.navigation.available.contains(.companies)
    }
    private func matches(_ ticket: NovaCompanyListTicket, _ host: NovaSessionHost) -> Bool {
        pending == ticket && allowed(host) && host.isCurrent(ticket.epoch) && host.identity?.userID == ticket.ownerID
    }
}
