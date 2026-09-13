import Foundation

@MainActor final class MemoryNotebook: NotebookStorage {
    var values = [UUID: Data](); var fail = false
    func read(owner: UUID) throws -> Data? { values[owner] }
    func write(_ data: Data, owner: UUID) throws { if fail { throw NotebookFailure.unavailable }; values[owner] = data }
}
@main struct NotebookQueueCheck {
    @MainActor static func main() async throws {
        let identity = NotebookIdentity(owner: UUID(), session: UUID())
        func draft() -> NotebookMutation { .init(mutation: UUID(), note: UUID(), action: "sync", expected: 0, title: "Başlık", body: "Taslak", conflict: nil) }
        func ack(_ intent: NotebookMutation) throws -> Data { try JSONSerialization.data(withJSONObject: ["schema_version":1,"mutation_id":intent.mutation.uuidString,"note_id":intent.note.uuidString,"state":"created","version":1,"replayed":false]) }
        var checks = 0
        func check(_ value: Bool, line: UInt = #line) { precondition(value, "Check failed at line \(line)"); checks += 1 }
        let store = MemoryNotebook(), intent = draft(); var sent = [Data]()
        let queue = NotebookQueue(storage: store, current: { identity }, send: { data in sent.append(data); check(store.values[identity.owner] != nil); throw NotebookFailure.unavailable })
        try queue.stage(intent, identity: identity); try queue.stage(intent, identity: identity)
        check(try queue.pending(identity).count == 1)
        do { _ = try await queue.syncNext(identity); preconditionFailure() } catch {}
        let reopened = NotebookQueue(storage: store, current: { identity }, send: { data in sent.append(data); return try ack(intent) })
        check(try reopened.pending(identity).first?.attempted == true)
        check(try await reopened.syncNext(identity) == "committed"); check(sent[0] == sent[1]); check(try reopened.pending(identity).isEmpty)
        let failing = MemoryNotebook(); let stopped = NotebookQueue(storage: failing, current: { identity }, send: { _ in preconditionFailure("Network before durable write") })
        try stopped.stage(draft(), identity: identity); failing.fail = true
        do { _ = try await stopped.syncNext(identity); preconditionFailure() } catch { check(true) }
        var current = identity; let other = NotebookIdentity(owner: UUID(), session: UUID()); let accountStore = MemoryNotebook(); let accountIntent = draft()
        let changing = NotebookQueue(storage: accountStore, current: { current }, send: { _ in current = other; return try ack(accountIntent) })
        try changing.stage(accountIntent, identity: identity)
        do { _ = try await changing.syncNext(identity); preconditionFailure() } catch { check(true) }
        check(try changing.pending(other).isEmpty); current = identity; check(try changing.pending(identity).first?.intent == accountIntent)
        accountStore.values[other.owner] = accountStore.values[identity.owner]; current = other
        do { _ = try changing.pending(other); preconditionFailure() } catch { check(true) }
        let conflictStore = MemoryNotebook(), conflictIntent = draft(), conflict = UUID()
        let blocked = NotebookQueue(storage: conflictStore, current: { identity }, send: { _ in
            try JSONSerialization.data(withJSONObject: ["schema_version":1,"mutation_id":conflictIntent.mutation.uuidString,"note_id":conflictIntent.note.uuidString,"state":"conflict","server_version":2,"conflict_id":conflict.uuidString,"both_texts_preserved":true,"replayed":false])
        })
        try blocked.stage(conflictIntent, identity: identity)
        check(try await blocked.syncNext(identity) == "conflict"); check(try await blocked.syncNext(identity) == "idle")
        check(try blocked.pending(identity).first?.intent.body == "Taslak")
        let replacement = NotebookMutation(mutation: UUID(), note: conflictIntent.note, action: "resolve", expected: 2, title: "Merge", body: "Merged", conflict: conflict)
        try blocked.resolveBlocked(conflictIntent.mutation, with: replacement, identity: identity)
        check(try blocked.pending(identity).first?.intent == replacement)
        for code in ["NOTE_TOMBSTONED","VERSION_CONFLICT","ACCESS_DENIED","VALIDATION_ERROR","IDEMPOTENCY_CONFLICT"] {
            let q = NotebookQueue(storage: MemoryNotebook(), current: { identity }, send: { _ in throw NotebookServerFailure(code: code) })
            let d = draft(); try q.stage(d, identity: identity); check(try await q.syncNext(identity) == "blocked"); check(try q.pending(identity).first?.intent.body == d.body)
        }
        let full = NotebookQueue(storage: MemoryNotebook(), current: { identity }, send: { _ in preconditionFailure() })
        for _ in 0..<20 { try full.stage(draft(), identity: identity) }
        do { try full.stage(draft(), identity: identity); preconditionFailure() } catch { check(try full.pending(identity).count == 20) }
        let args = try JSONSerialization.jsonObject(with: intent.arguments()) as! [String: Any]
        check(Set(args.keys) == Set(["p_mutation","p_note","p_action","p_expected","p_title","p_body","p_conflict"]))
        check(args["p_conflict"] is NSNull)
        let organization = NotebookMutation(mutation: UUID(), note: UUID(), action: "organize", expected: 1, title: nil, body: nil, conflict: nil,
            items: [.init(item_id: UUID(), text: "Task", done: true)], tags: ["Tag"])
        let orgStore = MemoryNotebook()
        let orgQueue = NotebookQueue(storage: orgStore, current: { identity }, send: { _ in throw NotebookServerFailure(code: "VERSION_CONFLICT") })
        try orgQueue.stage(organization, identity: identity)
        check(try await orgQueue.syncNext(identity) == "blocked")
        var orgReplacement = organization
        orgReplacement = .init(mutation: UUID(), note: organization.note, action: "organize", expected: 3, title: nil, body: nil, conflict: nil, items: organization.items, tags: organization.tags)
        try orgQueue.replaceOrganization(organization.mutation, with: orgReplacement, identity: identity)
        check(try orgQueue.pending(identity).first?.intent == orgReplacement)
        let orgArgs = try JSONSerialization.jsonObject(with: organization.arguments()) as! [String: Any]
        check(Set(orgArgs.keys) == Set(["p_mutation", "p_note", "p_expected", "p_items", "p_tags"]))
        let racing = NotebookQueue(storage: MemoryNotebook(), current: { identity }, send: { _ in throw NotebookServerFailure(code: "VERSION_CONFLICT") })
        try racing.stage(replacement, identity: identity); _ = try await racing.syncNext(identity)
        check(try racing.pending(identity).first?.conflictID == conflict)
        print("NotebookQueue: \(checks) checks PASS; memory storage / fake RPC; not device persistence evidence")
    }
}
