import Foundation

struct NotebookConflict: Decodable, Equatable {
    let conflict_id: UUID
    let base_version: Int64
    let server_version: Int64
    let incoming_title: String?
    let incoming_body: String?
    let server_title: String?
    let server_body: String?
}
struct NotebookConflictPage: Decodable {
    struct Detail: Decodable {
        let note_id: UUID; let title: String?; let body: String?; let version: Int64
        let tombstone: Bool; let updated_at: String; let conflicts: [NotebookConflict]
        var record: NotebookRecord { .init(note_id: note_id, title: title, body: body, version: version, tombstone: tombstone, updated_at: updated_at) }
    }
    let schema_version: Int; let note: Detail
    let has_more_conflicts: Bool; let next_conflict_after: UUID?
    func validate(noteID: UUID, after: UUID?) throws {
        try note.record.validate()
        guard schema_version == 1, note.note_id == noteID, note.conflicts.count <= 20,
              !note.tombstone || note.conflicts.isEmpty,
              has_more_conflicts ? note.conflicts.count == 20 && next_conflict_after == note.conflicts.last?.conflict_id : next_conflict_after == nil else { throw NotebookFailure.invalid }
        var previous = after?.uuidString ?? ""
        for conflict in note.conflicts {
            guard conflict.conflict_id.uuidString > previous, (0...9007199254740991).contains(conflict.base_version),
                  (1...note.version).contains(conflict.server_version),
                  [conflict.incoming_title, conflict.server_title].allSatisfy({ ($0?.unicodeScalars.count ?? 0) <= 200 }),
                  [conflict.incoming_body, conflict.server_body].allSatisfy({ ($0?.unicodeScalars.count ?? 0) <= 20000 }) else { throw NotebookFailure.invalid }
            previous = conflict.conflict_id.uuidString
        }
    }
}
