import Foundation
import Supabase

@MainActor final class NotebookRepository {
    private let sdk: SupabaseClient
    init(sdk: SupabaseClient) { self.sdk = sdk }
    private struct ReadPayload: Encodable {
        var note: UUID? = nil
        let after: UUID?
        enum CodingKeys: String, CodingKey { case p_note, p_after }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if let note { try c.encode(note, forKey: .p_note) } else { try c.encodeNil(forKey: .p_note) }
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
    func organization(_ note: UUID, identity expected: NotebookIdentity) async throws -> NotebookOrganization {
        guard identity() == expected else { throw NotebookFailure.identityChanged }
        struct Params: Encodable { let p_note: UUID }
        let data = try await sdk.rpc("isg_notebook_organization_v1", params: Params(p_note: note)).execute().data
        try Task.checkCancellation()
        guard identity() == expected, data.count <= 2_000_000 else { throw NotebookFailure.identityChanged }
        let value = try JSONDecoder().decode(NotebookOrganization.self, from: data); try value.validate(note); return value
    }
    private struct ReminderReadPayload: Encodable {
        let p_after: UUID?
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            if let p_after { try values.encode(p_after, forKey: .p_after) }
            else { try values.encodeNil(forKey: .p_after) }
        }
        enum CodingKeys: String, CodingKey { case p_after }
    }
    func reminders(_ expected: NotebookIdentity) async throws -> [NotebookReminder] {
        guard identity() == expected else { throw NotebookFailure.identityChanged }
        var result: [NotebookReminder] = []
        var after: UUID?
        for _ in 0..<50 {
            let data = try await sdk.rpc("isg_notebook_reminders_v1", params: ReminderReadPayload(p_after: after)).execute().data
            try Task.checkCancellation()
            guard identity() == expected, data.count <= 2_000_000 else { throw NotebookFailure.identityChanged }
            let page = try JSONDecoder().decode(NotebookReminderPage.self, from: data)
            try page.validate(after: after)
            result.append(contentsOf: page.reminders)
            guard result.count <= 1_000 else { throw NotebookFailure.full }
            guard page.has_more else { return result }
            after = page.next_after
        }
        throw NotebookFailure.full
    }
    @discardableResult
    func createReminder(title: String, recurrence: NotebookReminderRecurrence, dueAt: Date,
                        note: UUID? = nil, identity expected: NotebookIdentity) async throws -> UUID {
        guard identity() == expected, dueAt > Date(),
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.unicodeScalars.count <= 200 else { throw NotebookFailure.invalid }
        let zone = TimeZone.current
        let day = DateFormatter(); day.calendar = Calendar(identifier: .gregorian); day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = zone; day.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter(); time.calendar = Calendar(identifier: .gregorian); time.locale = Locale(identifier: "en_US_POSIX")
        time.timeZone = zone; time.dateFormat = "HH:mm:ss"
        let payload = NotebookReminderMutationPayload(mutation: UUID(), action: "create", reminder: nil,
            note: note, occurrence: nil, expected: 0, title: title, recurrence: recurrence,
            localTime: time.string(from: dueAt), startsOn: day.string(from: dueAt), timezone: zone.identifier,
            snoozedUntil: nil, installation: NotificationService.shared.serverPushInstallationID)
        let receipt = try await reminderMutation(payload, identity: expected)
        guard receipt.state == "active", receipt.delivery_strategy == "server_push",
              let reminder = receipt.reminder_id else { throw NotebookFailure.invalid }
        return reminder
    }
    func settleReminder(_ action: String, reminder: NotebookReminder,
                        occurrence: NotebookReminderOccurrence? = nil, snoozedUntil: Date? = nil,
                        identity expected: NotebookIdentity) async throws {
        guard ["complete", "snooze", "cancel"].contains(action), reminder.state == "active",
              (action == "cancel") == (occurrence == nil),
              (action == "snooze") == (snoozedUntil != nil) else { throw NotebookFailure.invalid }
        let payload = NotebookReminderMutationPayload(mutation: UUID(), action: action, reminder: reminder.reminder_id,
            note: nil, occurrence: occurrence?.occurrence_id, expected: reminder.series_version, title: nil,
            recurrence: nil, localTime: nil, startsOn: nil, timezone: nil,
            snoozedUntil: snoozedUntil.map(NotebookReminderDate.string), installation: nil)
        _ = try await reminderMutation(payload, identity: expected)
    }
    private struct ReminderReceipt: Decodable {
        let schema_version: Int
        let mutation_id: UUID
        let reminder_id: UUID?
        let state: String
        let delivery_strategy: String?
    }
    private func reminderMutation(_ payload: NotebookReminderMutationPayload,
                                  identity expected: NotebookIdentity) async throws -> ReminderReceipt {
        guard identity() == expected else { throw NotebookFailure.identityChanged }
        do {
            let data = try await sdk.rpc("isg_notebook_reminder_mutate_v1", params: payload).execute().data
            try Task.checkCancellation()
            guard identity() == expected, data.count <= 16_384 else { throw NotebookFailure.identityChanged }
            let value = try JSONDecoder().decode(ReminderReceipt.self, from: data)
            guard value.schema_version == 1, value.mutation_id == payload.mutation else { throw NotebookFailure.invalid }
            return value
        } catch let error as PostgrestError {
            let codes = ["AUTH_REQUIRED", "FEATURE_UNAVAILABLE", "ACCESS_DENIED", "VERSION_CONFLICT",
                         "IDEMPOTENCY_CONFLICT", "VALIDATION_ERROR", "DEVICE_UNAVAILABLE"]
            if ["P0001", "28000"].contains(error.code ?? ""), codes.contains(error.message) {
                throw NotebookServerFailure(code: error.message)
            }
            throw NotebookFailure.unavailable
        }
    }
    func conflict(_ pending: NotebookPending, identity expected: NotebookIdentity) async throws -> (NotebookRecord, NotebookConflict) {
        guard identity() == expected, let wanted = pending.conflictID else { throw NotebookFailure.identityChanged }
        var after: UUID?; var version: Int64?
        for _ in 0..<50 {
            let data = try await sdk.rpc("isg_notebook_read_v1", params: ReadPayload(note: pending.intent.note, after: after)).execute().data
            try Task.checkCancellation()
            guard identity() == expected else { throw NotebookFailure.identityChanged }
            guard data.count <= 2_000_000 else { throw NotebookFailure.invalid }
            let page = try JSONDecoder().decode(NotebookConflictPage.self, from: data)
            try page.validate(noteID: pending.intent.note, after: after)
            guard !page.note.tombstone else { throw NotebookServerFailure(code: "NOTE_TOMBSTONED") }
            if let version, version != page.note.version { throw NotebookFailure.unavailable }
            version = page.note.version
            if let match = page.note.conflicts.first(where: { $0.conflict_id == wanted }) { return (page.note.record, match) }
            guard page.has_more_conflicts else { throw NotebookServerFailure(code: "CONFLICT_ALREADY_RESOLVED") }
            after = page.next_conflict_after
        }
        throw NotebookFailure.full
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
        do {
            if let value = try? JSONDecoder().decode(NotebookOrganizationPayload.self, from: data) {
                return try await self.sdk.rpc("isg_notebook_organize_v1", params: value).execute().data
            }
            return try await self.sdk.rpc("isg_notebook_mutate_v1", params: JSONDecoder().decode(Payload.self, from: data)).execute().data
        }
        catch let error as PostgrestError {
            let codes = ["AUTH_REQUIRED","FEATURE_UNAVAILABLE","ACCESS_DENIED","VERSION_CONFLICT","NOTE_TOMBSTONED","IDEMPOTENCY_CONFLICT","VALIDATION_ERROR","CONFLICT_ALREADY_RESOLVED"]
            if ["P0001","28000"].contains(error.code ?? ""), codes.contains(error.message) { throw NotebookServerFailure(code: error.message) }
            throw NotebookFailure.unavailable
        }
    })
}
