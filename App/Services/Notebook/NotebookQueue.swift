import Foundation

enum NotebookFailure: String, Error { case invalid, unavailable, identityChanged, full, busy }
struct NotebookIdentity: Equatable { let owner: UUID; let session: UUID }
struct NotebookMutation: Codable, Equatable {
    let mutation: UUID
    let note: UUID
    let action: String
    let expected: Int64
    let title: String?
    let body: String?
    let conflict: UUID?
    var items: [NotebookItem]? = nil
    var tags: [String]? = nil
    func validate() throws {
        if action == "organize" {
            guard (1...9007199254740990).contains(expected), title == nil, body == nil, conflict == nil,
                  let items, let tags else { throw NotebookFailure.invalid }
            try validateNotebookOrganization(items, tags); return
        }
        guard items == nil, tags == nil else { throw NotebookFailure.invalid }
        guard ["sync", "delete", "resolve"].contains(action), (0...9007199254740990).contains(expected),
              (title?.unicodeScalars.count ?? 0) <= 200, (body?.unicodeScalars.count ?? 0) <= 20000,
              (action == "resolve") == (conflict != nil),
              action == "delete" ? title == nil && body == nil : title != nil || body != nil else { throw NotebookFailure.invalid }
    }
    func arguments() throws -> Data {
        try validate()
        if action == "organize" {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(NotebookOrganizationPayload(p_mutation: mutation, p_note: note, p_expected: expected, p_items: items!, p_tags: tags!))
        }
        return try JSONSerialization.data(withJSONObject: ["p_mutation": mutation.uuidString.lowercased(),
            "p_note": note.uuidString.lowercased(), "p_action": action, "p_expected": expected,
            "p_title": title as Any? ?? NSNull(), "p_body": body as Any? ?? NSNull(),
            "p_conflict": conflict?.uuidString.lowercased() as Any? ?? NSNull()], options: [.sortedKeys])
    }
}
struct NotebookPending: Codable, Equatable {
    let intent: NotebookMutation
    var attempted: Bool = false
    var blocked: String?
    var conflictID: UUID?
}
@MainActor protocol NotebookStorage {
    func read(owner: UUID) throws -> Data?
    func write(_ data: Data, owner: UUID) throws
}
struct NotebookServerFailure: Error { let code: String }

/// One owner-bound durable outbox. No company scope, subscription check or telemetry.
/// Instantiation does not send. A caller must explicitly drive syncNext after rollout.
@MainActor final class NotebookQueue {
    typealias Send = (Data) async throws -> Data
    private struct Ledger: Codable { let schema: Int; let owner: UUID; var entries: [NotebookPending] }
    private static var sending = Set<UUID>()
    private let storage: any NotebookStorage
    private let current: () -> NotebookIdentity?
    private let send: Send
    init(storage: any NotebookStorage, current: @escaping () -> NotebookIdentity?, send: @escaping Send) {
        self.storage = storage; self.current = current; self.send = send
    }
    private func check(_ identity: NotebookIdentity) throws {
        try Task.checkCancellation()
        guard current() == identity else { throw NotebookFailure.identityChanged }
    }
    private func load(_ owner: UUID) throws -> Ledger {
        guard let data = try storage.read(owner: owner) else { return Ledger(schema: 1, owner: owner, entries: []) }
        guard data.count <= 2_000_000 else { throw NotebookFailure.invalid }
        let ledger = try JSONDecoder().decode(Ledger.self, from: data)
        guard ledger.schema == 1, ledger.owner == owner, ledger.entries.count <= 20,
              Set(ledger.entries.map { $0.intent.mutation }).count == ledger.entries.count else { throw NotebookFailure.invalid }
        for entry in ledger.entries { try entry.intent.validate() }
        return ledger
    }
    private func persist(_ ledger: Ledger) throws {
        let data = try JSONEncoder().encode(ledger)
        guard data.count <= 2_000_000 else { throw NotebookFailure.full }
        try storage.write(data, owner: ledger.owner)
    }
    func pending(_ identity: NotebookIdentity) throws -> [NotebookPending] {
        try check(identity); return try load(identity.owner).entries
    }
    func stage(_ intent: NotebookMutation, identity: NotebookIdentity) throws {
        try check(identity); try intent.validate()
        var ledger = try load(identity.owner)
        if let existing = ledger.entries.first(where: { $0.intent.mutation == intent.mutation }) {
            guard existing.intent == intent else { throw NotebookFailure.invalid }; return
        }
        guard ledger.entries.count < 20 else { throw NotebookFailure.full }
        ledger.entries.append(NotebookPending(intent: intent)); try persist(ledger)
    }
    // Explicit recovery action only; never called automatically on an RPC error.
    func discard(_ mutation: UUID, identity: NotebookIdentity) throws {
        try check(identity); guard !Self.sending.contains(identity.owner) else { throw NotebookFailure.busy }
        var ledger = try load(identity.owner)
        ledger.entries.removeAll { $0.intent.mutation == mutation }; try persist(ledger)
    }
    func resolveBlocked(_ mutation: UUID, with replacement: NotebookMutation, identity: NotebookIdentity) throws {
        try check(identity); try replacement.validate()
        guard !Self.sending.contains(identity.owner) else { throw NotebookFailure.busy }
        var ledger = try load(identity.owner)
        guard let i = ledger.entries.firstIndex(where: { $0.intent.mutation == mutation }),
              ledger.entries[i].blocked == "VERSION_CONFLICT", let conflict = ledger.entries[i].conflictID,
              replacement.action == "resolve", replacement.note == ledger.entries[i].intent.note, replacement.conflict == conflict,
              !ledger.entries.contains(where: { $0.intent.mutation == replacement.mutation }) else { throw NotebookFailure.invalid }
        ledger.entries[i] = NotebookPending(intent: replacement); try persist(ledger)
    }
    func replaceOrganization(_ mutation: UUID, with replacement: NotebookMutation, identity: NotebookIdentity) throws {
        try check(identity); try replacement.validate()
        guard !Self.sending.contains(identity.owner) else { throw NotebookFailure.busy }
        var ledger = try load(identity.owner)
        guard let i = ledger.entries.firstIndex(where: { $0.intent.mutation == mutation }),
              ledger.entries[i].blocked == "VERSION_CONFLICT", ledger.entries[i].intent.action == "organize",
              replacement.action == "organize", replacement.note == ledger.entries[i].intent.note,
              !ledger.entries.contains(where: { $0.intent.mutation == replacement.mutation }) else { throw NotebookFailure.invalid }
        ledger.entries[i] = NotebookPending(intent: replacement); try persist(ledger)
    }
    func syncNext(_ identity: NotebookIdentity) async throws -> String {
        try check(identity)
        guard !Self.sending.contains(identity.owner) else { throw NotebookFailure.busy }
        Self.sending.insert(identity.owner); defer { Self.sending.remove(identity.owner) }
        var ledger = try load(identity.owner)
        // A blocked edit must not be overtaken by a later edit to the same note.
        var blockedNotes = Set<UUID>()
        let index = ledger.entries.indices.first { i in
            let entry = ledger.entries[i]
            if entry.blocked != nil { blockedNotes.insert(entry.intent.note); return false }
            return !blockedNotes.contains(entry.intent.note)
        }
        guard let index else { return "idle" }
        ledger.entries[index].attempted = true
        let intent = ledger.entries[index].intent
        try persist(ledger) // Must succeed before network; same UUID survives restart.
        try check(identity)
        let data: Data
        do { data = try await send(intent.arguments()) }
        catch {
            try check(identity)
            if let code = (error as? NotebookServerFailure)?.code,
               ["VERSION_CONFLICT","NOTE_TOMBSTONED","IDEMPOTENCY_CONFLICT","ACCESS_DENIED","VALIDATION_ERROR","CONFLICT_ALREADY_RESOLVED"].contains(code) {
                var latest = try load(identity.owner)
                guard let i = latest.entries.firstIndex(where: { $0.intent == intent }) else { throw NotebookFailure.invalid }
                latest.entries[i].blocked = code
                if code == "VERSION_CONFLICT", intent.action == "resolve" { latest.entries[i].conflictID = intent.conflict }
                try persist(latest); return "blocked"
            }
            throw NotebookFailure.unavailable // Preserve the draft, never expose raw errors.
        }
        try check(identity)
        struct Receipt: Decodable {
            let schema_version: Int; let mutation_id: UUID; let note_id: UUID; let state: String
            let replayed: Bool; let version: Int64?; let server_version: Int64?; let conflict_id: UUID?; let both_texts_preserved: Bool?
        }
        guard data.count <= 16384 else { throw NotebookFailure.invalid }
        let ack = try JSONDecoder().decode(Receipt.self, from: data)
        guard ack.schema_version == 1, ack.mutation_id == intent.mutation, ack.note_id == intent.note else { throw NotebookFailure.invalid }
        var latest = try load(identity.owner)
        guard let i = latest.entries.firstIndex(where: { $0.intent == intent }) else { throw NotebookFailure.invalid }
        if ack.state == "conflict" {
            guard intent.action == "sync", let conflict = ack.conflict_id, let version = ack.server_version,
                  (1...9007199254740991).contains(version), ack.both_texts_preserved == true else { throw NotebookFailure.invalid }
            latest.entries[i].blocked = "VERSION_CONFLICT"; latest.entries[i].conflictID = conflict
            try persist(latest); return "conflict"
        }
        let allowed = intent.action == "organize" ? ["organized"] : intent.action == "delete" ? ["deleted"] : intent.action == "resolve" ? ["resolved"] : ["created","updated","unchanged"]
        guard allowed.contains(ack.state), let version = ack.version, (1...9007199254740991).contains(version),
              intent.action != "resolve" || ack.conflict_id == intent.conflict,
              ack.state == "deleted" || version == intent.expected + (ack.state == "unchanged" ? 0 : 1) else { throw NotebookFailure.invalid }
        latest.entries.remove(at: i); try persist(latest)
        return "committed"
    }
}

struct NotebookOrganizationPayload: Codable {
    let p_mutation: UUID; let p_note: UUID; let p_expected: Int64
    let p_items: [NotebookItem]; let p_tags: [String]
}
