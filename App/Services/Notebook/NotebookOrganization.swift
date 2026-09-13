import Foundation

struct NotebookItem: Codable, Equatable {
    let item_id: UUID
    var text: String
    var done: Bool
}
struct NotebookOrganization: Codable {
    let schema_version: Int; let note_id: UUID; let version: Int64; let tombstone: Bool
    let items: [NotebookItem]; let tags: [String]
    func validate(_ id: UUID) throws {
        guard schema_version == 1, note_id == id, (1...9007199254740991).contains(version),
              !tombstone || (items.isEmpty && tags.isEmpty) else { throw NotebookFailure.invalid }
        try validateNotebookOrganization(items, tags)
    }
}
func validateNotebookOrganization(_ items: [NotebookItem], _ tags: [String]) throws {
    guard items.count <= 500, tags.count <= 30, Set(items.map(\.item_id)).count == items.count,
          items.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.text.unicodeScalars.count <= 1000 }),
          tags.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.unicodeScalars.count <= 60 }),
          Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count == tags.count else { throw NotebookFailure.invalid }
}
