import Foundation

/// The header bell's data. Same shape as the other module services: one RPC
/// closure, a session check, and no SDK type reaching the design system.
@MainActor struct NovaNoticeService {
    typealias RPC = (String, [String: PersonnelRPCValue]) async throws -> Data
    private let rpc: RPC
    private let isSession: (NovaSessionIdentity) -> Bool

    init(rpc: @escaping RPC, isSession: @escaping (NovaSessionIdentity) -> Bool) {
        self.rpc = rpc; self.isSession = isSession
    }

    private func check(_ identity: NovaSessionIdentity) throws {
        guard isSession(identity) else { throw NovaNoticeFailure.denied }
    }

    private struct Row: Decodable {
        let notice_key: String
        let kind: String
        let destination: String
        let company_id: UUID?
        let company_name: String?
        let record_id: UUID?
        let title: String
        let due_on: String
        let days: Int
        let severity: String
        let unread: Bool
        let dismissed: Bool
    }
    private struct Envelope: Decodable {
        let rows: [Row]
        let unread: Int
        let overdue: Int
        let total: Int
        let dismissed: Int
        let has_more: Bool
        let push_delivery_claimed: Bool
        let dismiss_is_permanent: Bool
    }

    /// A row whose kind or destination this build does not know is dropped
    /// rather than shown as something it is not.
    private func entry(_ row: Row) -> NovaNoticeEntry? {
        guard let kind = NovaNoticeKind(rawValue: row.kind),
              let destination = NovaDestination(rawValue: row.destination),
              let severity = NovaNoticeSeverity(rawValue: row.severity) else { return nil }
        return NovaNoticeEntry(key: row.notice_key, kind: kind, destination: destination,
            companyID: row.company_id, companyName: row.company_name, recordID: row.record_id,
            title: row.title, dueOn: row.due_on, days: row.days, severity: severity,
            unread: row.unread, dismissed: row.dismissed)
    }

    func feed(_ identity: NovaSessionIdentity, company: UUID? = nil,
              scope: NovaNoticeScope = .active, limit: Int = 50) async throws -> NovaNoticeFeed {
        try check(identity)
        let data = try await rpc("isg_pilot_notice_feed_v1", [
            "p_company": company.map { .id($0) } ?? .null,
            "p_scope": .string(scope.rawValue),
            "p_limit": .number(Int64(limit))])
        try check(identity)
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        return NovaNoticeFeed(rows: envelope.rows.compactMap(entry), unread: envelope.unread,
            overdue: envelope.overdue, total: envelope.total, dismissed: envelope.dismissed,
            hasMore: envelope.has_more, pushDeliveryClaimed: envelope.push_delivery_claimed,
            dismissIsPermanent: envelope.dismiss_is_permanent)
    }

    private func mark(_ identity: NovaSessionIdentity, action: String, keys: [String]?) async throws {
        try check(identity)
        var payload: [String: PersonnelRPCValue] = ["p_action": .string(action)]
        // The bulk actions carry no list; sending one is refused by the server.
        if let keys { payload["p_keys"] = .array(keys.map { .string($0) }) }
        _ = try await rpc("isg_pilot_notice_mark_v1", payload)
    }

    func read(_ identity: NovaSessionIdentity, key: String) async throws {
        try await mark(identity, action: "read", keys: [key])
    }
    func readAll(_ identity: NovaSessionIdentity) async throws {
        try await mark(identity, action: "read_all", keys: nil)
    }
    /// Deleting a notice hides the situation. It never touches the record, and
    /// the notice returns when the record's date moves.
    func dismiss(_ identity: NovaSessionIdentity, key: String) async throws {
        try await mark(identity, action: "dismiss", keys: [key])
    }
    func dismissAll(_ identity: NovaSessionIdentity) async throws {
        try await mark(identity, action: "dismiss_all", keys: nil)
    }
    func restore(_ identity: NovaSessionIdentity, key: String) async throws {
        try await mark(identity, action: "restore", keys: [key])
    }
}
