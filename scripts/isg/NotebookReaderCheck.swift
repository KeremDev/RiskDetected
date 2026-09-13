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
        print("NotebookReader: PASS (stale version, absence, tombstone, session isolation, late response)")
    }
}
