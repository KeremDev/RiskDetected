import Foundation
import Supabase

@MainActor final class NotebookRepository {
    private let sdk: SupabaseClient
    init(sdk: SupabaseClient) { self.sdk = sdk }
    private struct ReadPayload: Encodable {
        let after: UUID?
        enum CodingKeys: String, CodingKey { case p_note, p_after }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeNil(forKey: .p_note)
            if let after { try c.encode(after, forKey: .p_after) } else { try c.encodeNil(forKey: .p_after) }
        }
    }
    lazy var reader = NotebookReader(current: { [weak self] in self?.identity() }, read: { [weak self] after in
        guard let self else { throw NotebookFailure.unavailable }
        return try await self.sdk.rpc("isg_notebook_read_v1", params: ReadPayload(after: after)).execute().data
    })
    func snapshot(_ identity: NotebookIdentity) throws -> NotebookReader.Snapshot {
        try reader.snapshot(identity, drafts: queue.pending(identity))
    }
    func identity() -> NotebookIdentity? {
        guard let session = sdk.auth.currentSession else { return nil }
        let parts = session.accessToken.split(separator: "."); guard parts.count == 3 else { return nil }
        var raw = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        raw += String(repeating: "=", count: (4 - raw.count % 4) % 4)
        guard let data = Data(base64Encoded: raw), let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = claims["session_id"] as? String, let sessionID = UUID(uuidString: id) else { return nil }
        return NotebookIdentity(owner: session.user.id, session: sessionID) // Correlation only; server verifies session.
    }
    private struct Payload: Codable {
        let p_mutation: UUID; let p_note: UUID; let p_action: String; let p_expected: Int64
        let p_title: String?; let p_body: String?; let p_conflict: UUID?
        enum CodingKeys: String, CodingKey { case p_mutation, p_note, p_action, p_expected, p_title, p_body, p_conflict }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(p_mutation, forKey: .p_mutation); try c.encode(p_note, forKey: .p_note)
            try c.encode(p_action, forKey: .p_action); try c.encode(p_expected, forKey: .p_expected)
            if let p_title { try c.encode(p_title, forKey: .p_title) } else { try c.encodeNil(forKey: .p_title) }
            if let p_body { try c.encode(p_body, forKey: .p_body) } else { try c.encodeNil(forKey: .p_body) }
            if let p_conflict { try c.encode(p_conflict, forKey: .p_conflict) } else { try c.encodeNil(forKey: .p_conflict) }
        }
    }
    lazy var queue = NotebookQueue(storage: NotebookKeychainStorage(), current: { [weak self] in self?.identity() }, send: { [weak self] data in
        guard let self else { throw NotebookFailure.unavailable }
        do { return try await self.sdk.rpc("isg_notebook_mutate_v1", params: JSONDecoder().decode(Payload.self, from: data)).execute().data }
        catch let error as PostgrestError {
            let codes = ["AUTH_REQUIRED","FEATURE_UNAVAILABLE","ACCESS_DENIED","VERSION_CONFLICT","NOTE_TOMBSTONED","IDEMPOTENCY_CONFLICT","VALIDATION_ERROR","CONFLICT_ALREADY_RESOLVED"]
            if ["P0001","28000"].contains(error.code ?? ""), codes.contains(error.message) { throw NotebookServerFailure(code: error.message) }
            throw NotebookFailure.unavailable
        }
    })
}
