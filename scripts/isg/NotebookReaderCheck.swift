import Foundation

@main struct NotebookReaderCheck {
    @MainActor static func main() async throws {
        func check(_ value: Bool) { precondition(value) }
        let identity = NotebookIdentity(owner: UUID(), session: UUID()), id = UUID()
        var current = identity
        func record(_ version: Int64, _ deleted: Bool = false) -> NotebookRecord {
            .init(note_id: id, title: deleted ? nil : "Not", body: deleted ? nil : "Metin", version: version, tombstone: deleted, updated_at: "2026-09-13T00:00:00Z")
        }
        func page(_ records: [NotebookRecord]) throws -> Data {
            let rows = try JSONSerialization.jsonObject(with: JSONEncoder().encode(records))
            return try JSONSerialization.data(withJSONObject: ["schema_version":1,"scan_mode":"full_scan_restart","notes":rows,"has_more":false,"next_after":NSNull()])
        }
        var response = try page([record(2)])
        var calls = 0
        let reader = NotebookReader(current: { current }, read: { after in
            precondition(after == nil); calls += 1; return response
        })
        try await reader.refresh(identity)
        check(try reader.snapshot(identity, drafts: []).notes.first?.version == 2)
        response = try page([record(1)]); try await reader.refresh(identity)
        check(try reader.snapshot(identity, drafts: []).notes.first?.version == 2)
        response = try page([]); try await reader.refresh(identity)
        check(try reader.snapshot(identity, drafts: []).notes.count == 1)
        response = try page([record(3, true)]); try await reader.refresh(identity)
        response = try page([record(4)]); try await reader.refresh(identity)
        check(try reader.snapshot(identity, drafts: []).notes.isEmpty)
        current = NotebookIdentity(owner: UUID(), session: UUID())
        check(try reader.snapshot(current, drafts: []).notes.isEmpty)
        do { try await reader.refresh(identity); preconditionFailure() } catch {}
        precondition(calls == 5)
        let changing = NotebookReader(current: { current }, read: { _ in current = identity; return response })
        let other = current
        do { try await changing.refresh(other); preconditionFailure() } catch {}
        check(try changing.snapshot(identity, drafts: []).notes.isEmpty)
        let conflict = NotebookConflict(conflict_id: UUID(), base_version: 0, server_version: 1,
            incoming_title: "Local", incoming_body: "Local body", server_title: "Remote", server_body: "Remote body")
        let detail = NotebookConflictPage.Detail(note_id: id, title: "Current", body: "Current body", version: 2, tombstone: false, updated_at: "2026-09-13", conflicts: [conflict])
        let conflictPage = NotebookConflictPage(schema_version: 1, note: detail, has_more_conflicts: false, next_conflict_after: nil)
        try conflictPage.validate(noteID: id, after: nil)
        do { try conflictPage.validate(noteID: UUID(), after: nil); preconditionFailure() } catch {}
        do { try conflictPage.validate(noteID: id, after: conflict.conflict_id); preconditionFailure() } catch {}
        let bad = NotebookConflictPage(schema_version: 1, note: detail, has_more_conflicts: true, next_conflict_after: conflict.conflict_id)
        do { try bad.validate(noteID: id, after: nil); preconditionFailure() } catch {}
        print("NotebookReader: PASS (stale version, absence, tombstone, session isolation, late response)")
    }
}
