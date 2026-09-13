import Foundation

struct NotebookRecord: Codable, Equatable {
    let note_id: UUID
    let title: String?
    let body: String?
    let version: Int64
    let tombstone: Bool
    let updated_at: String
    func validate() throws {
        guard (1...9007199254740991).contains(version), !updated_at.isEmpty,
              (title?.unicodeScalars.count ?? 0) <= 200, (body?.unicodeScalars.count ?? 0) <= 20000,
              !tombstone || (title == nil && body == nil) else { throw NotebookFailure.invalid }
    }
}

/// Session-bound in-memory read model. Durable drafts remain in the separate outbox.
/// Missing rows never delete data; old responses never resurrect a tombstone.
@MainActor final class NotebookReader {
    struct Snapshot { let notes: [NotebookRecord]; let drafts: [NotebookPending] }
    private struct Page: Decodable {
        let schema_version: Int; let scan_mode: String; let notes: [NotebookRecord]
        let has_more: Bool; let next_after: UUID?
    }
    private let current: () -> NotebookIdentity?
    private let read: (UUID?) async throws -> Data
    private var bound: NotebookIdentity?
    private var records = [UUID: NotebookRecord]()
    private var fetching = false
    init(current: @escaping () -> NotebookIdentity?, read: @escaping (UUID?) async throws -> Data) {
        self.current = current; self.read = read
    }
    private func check(_ identity: NotebookIdentity) throws {
        try Task.checkCancellation()
        guard current() == identity else {
            records.removeAll(); bound = nil; throw NotebookFailure.identityChanged
        }
        if bound != identity { records.removeAll(); bound = identity }
    }
    func snapshot(_ identity: NotebookIdentity, drafts: [NotebookPending]) throws -> Snapshot {
        try check(identity)
        // Keep pending edits separate, including edits blocked by a tombstone.
        return Snapshot(notes: records.values.filter { !$0.tombstone }.sorted { $0.note_id.uuidString < $1.note_id.uuidString }, drafts: drafts)
    }
    func refresh(_ identity: NotebookIdentity) async throws {
        try check(identity)
        guard !fetching else { throw NotebookFailure.busy }
        fetching = true; defer { fetching = false }
        var after: UUID? = nil
        // Bounded full scan; only publish after every page passes validation.
        var merged = records
        for _ in 0..<50 {
            let data: Data
            do { data = try await read(after) } catch { try check(identity); throw NotebookFailure.unavailable }
            try check(identity)
            guard data.count <= 2_000_000 else { throw NotebookFailure.invalid }
            let page = try JSONDecoder().decode(Page.self, from: data)
            guard page.schema_version == 1, page.scan_mode == "full_scan_restart", page.notes.count <= 20,
                  page.has_more ? page.notes.count == 20 && page.next_after == page.notes.last?.note_id : page.next_after == nil else { throw NotebookFailure.invalid }
            var previous = after?.uuidString ?? ""
            for record in page.notes {
                try record.validate()
                guard record.note_id.uuidString > previous else { throw NotebookFailure.invalid }
                previous = record.note_id.uuidString
                if let old = merged[record.note_id] {
                    if old.tombstone || record.version < old.version { continue }
                    if record.version == old.version {
                        guard record == old else { throw NotebookFailure.invalid }; continue
                    }
                }
                merged[record.note_id] = record
            }
            guard merged.count <= 1000,
                  try JSONEncoder().encode(Array(merged.values)).count <= 2_000_000 else { throw NotebookFailure.full }
            if !page.has_more { records = merged; return }
            after = page.next_after
        }
        throw NotebookFailure.full
    }
}
