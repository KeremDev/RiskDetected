import Foundation
import Supabase

/// "Senin İçin" reads and card events. Calls go through NovaExpertTransport, so
/// an organization session reaches the same endpoints through isg_expert_rpc_v1.
@MainActor struct NovaForYouService {
    /// The card set this build can word. A card added later carries a higher
    /// "since" and the server never sends it to this build.
    static let contract = 1
    private let expertTicket = NovaExpertTransport.shared.capture()
    let identity: NovaSessionIdentity

    /// Unfinished work that lives only on this device. Only these four fields
    /// leave the device; the draft itself does not.
    struct LocalDraft: Encodable, Equatable {
        let kind: String
        let ref: String
        var company_id: UUID?
        let updated_at: String
    }

    /// The Keychain account for this user and workspace: queued events and
    /// cached answers never cross into another session scope.
    var namespace: String { expertTicket?.access.storageNamespace ?? "\(identity.userID.uuidString.lowercased()):personal" }

    func load(local: [LocalDraft], routes: [String]) async throws -> NovaForYouFeed {
        struct Client: Encodable { let contract: Int; let routes: [String] }
        struct Args: Encodable { let p_local: [LocalDraft]; let p_client: Client }
        try check()
        let data = try await NovaExpertTransport.shared.execute("isg_home_feed_v1",
            params: Args(p_local: local, p_client: .init(contract: Self.contract, routes: routes)), ticket: expertTicket)
        try check()
        guard data.count <= 1_048_576 else { throw NovaPersonnelFailure.unavailable }
        let feed = try JSONDecoder().decode(NovaForYouFeed.self, from: data)
        guard feed.schema_version == 1 else { throw NovaPersonnelFailure.unavailable }
        return feed
    }

    func send(_ event: NovaForYouEvent) async throws {
        try check()
        let moment = NovaForYouEvent.timestamp(event.occurredAt)
        if let feature = event.feature {
            struct Args: Encodable { let p_feature: String; let p_occurred_at: String }
            _ = try await NovaExpertTransport.shared.execute("isg_feature_usage_v1",
                params: Args(p_feature: feature, p_occurred_at: moment), ticket: expertTicket)
        } else {
            struct Args: Encodable { let p_action: String; let p_cards: [String]; let p_event: UUID; let p_occurred_at: String }
            _ = try await NovaExpertTransport.shared.execute("isg_home_card_action_v1",
                params: Args(p_action: event.action, p_cards: event.cards, p_event: event.id, p_occurred_at: moment), ticket: expertTicket)
        }
        try check()
    }

    private func check() throws {
        try Task.checkCancellation()
        guard novaCurrentSessionIdentity() == identity else { throw NovaPersonnelFailure.denied }
    }
}

/// One card event or feature use, with its own id and the moment it happened.
/// The server applies a repeated or late delivery without harm, so the queue
/// can always resend.
struct NovaForYouEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let occurredAt: Date
    let action: String
    let cards: [String]
    let feature: String?

    static func card(_ action: String, _ cards: [String], at moment: Date = Date()) -> Self {
        .init(id: UUID(), occurredAt: moment, action: action, cards: cards, feature: nil)
    }
    static func use(_ feature: String, at moment: Date = Date()) -> Self {
        .init(id: UUID(), occurredAt: moment, action: "feature", cards: [], feature: feature)
    }
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// Events wait here until the server confirms them: written first, sent next,
/// removed on the answer. Per user and workspace, device-only Keychain, at most
/// 50 events; events older than 30 days are dropped because the server would
/// ignore them anyway.
@MainActor final class NovaForYouOutbox {
    static let shared = NovaForYouOutbox()
    private let storage = KeychainPersonnelPendingStorage(service: "com.riskdetected.foryou.outbox.v1", maximumBytes: 65_536)
    private var flushing = Set<String>()
    private static var recorded = Set<String>()

    private func read(_ namespace: String) -> [NovaForYouEvent] {
        guard let data = try? storage.read(account: namespace) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([NovaForYouEvent].self, from: data)) ?? []
    }

    private func write(_ events: [NovaForYouEvent], _ namespace: String) {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        let kept = Array(events.filter { $0.occurredAt >= cutoff }.suffix(50))
        if kept.isEmpty { try? storage.remove(account: namespace); return }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(kept) { try? storage.write(data, account: namespace) }
    }

    func add(_ event: NovaForYouEvent, namespace: String) {
        write(read(namespace) + [event], namespace)
    }

    func pending(_ namespace: String) -> [NovaForYouEvent] { read(namespace) }

    /// Sends in the order the events happened. A refused event (malformed for
    /// this server) is dropped; a network or session failure stops the pass
    /// and everything from there waits for the next one.
    func flush(_ service: NovaForYouService) async {
        let namespace = service.namespace
        guard flushing.insert(namespace).inserted else { return }
        defer { flushing.remove(namespace) }
        for event in read(namespace).sorted(by: { $0.occurredAt < $1.occurredAt }) {
            do {
                try await service.send(event)
            } catch let error as PostgrestError where error.message == "VALIDATION_ERROR" {
                // The server will never accept it; keeping it would block the queue.
            } catch {
                return
            }
            write(read(namespace).filter { $0.id != event.id }, namespace)
        }
    }

    /// Records the use of a feature that leaves no record of its own (the
    /// on-device wizards, the sample form libraries, statistics, Evrak
    /// Takibi). Queued first, so a failed request is retried later.
    static func recordUse(_ feature: String) {
        guard let identity = novaCurrentSessionIdentity() else { return }
        let service = NovaForYouService(identity: identity)
        // The server only needs to know the feature was used; once per app
        // session and scope is enough.
        guard recorded.insert("\(service.namespace)|\(feature)").inserted else { return }
        shared.add(.use(feature), namespace: service.namespace)
        Task { await shared.flush(service) }
    }
}

/// Unfinished work that exists only on this device, in this session's scope.
@MainActor enum NovaLocalDraftDigest {
    static func collect(identity: NovaSessionIdentity, personal: Bool) -> [NovaForYouService.LocalDraft] {
        var drafts: [NovaForYouService.LocalDraft] = []
        if let stamp = try? NovaEducationService(identity: identity).newDraftStamp() {
            drafts.append(.init(kind: "training_draft", ref: stamp.ref.uuidString.lowercased(),
                company_id: stamp.companyID, updated_at: NovaForYouEvent.timestamp(stamp.updatedAt)))
        }
        // A company create interrupted while it was being sent. The intent has
        // its own mutation id; it keeps no edit time, and it is the most urgent
        // kind of unfinished work, so it is described as current.
        if personal, let intent = try? NovaPilotCompanyService.live().pending(identity: identity) {
            drafts.append(.init(kind: "company_create", ref: intent.mutationID.uuidString.lowercased(),
                company_id: nil, updated_at: NovaForYouEvent.timestamp(Date())))
        }
        return drafts
    }
}
