import Foundation

/// Versioned company directory transport, deliberately free of SDK and credentials.
enum NovaDirectoryKind: String, CaseIterable, Codable {
    case workplaces, departments, jobs, contractors, engagements, contexts, assignments, employers
    var title: String {
        switch self {
        case .workplaces: return "İşyerleri"
        case .departments: return "Departmanlar"
        case .jobs: return "Görev ve Unvanlar"
        case .contractors: return "Dış Firmalar"
        case .engagements: return "İşyeri İlişkileri"
        case .contexts: return "İşyeri Bağlam Geçmişi"
        case .assignments: return "Görevlendirme Geçmişi"
        case .employers: return "Personelin İşvereni"
        }
    }
    var symbol: String {
        switch self {
        case .workplaces: return "building.2"
        case .departments: return "point.3.connected.trianglepath.dotted"
        case .jobs: return "briefcase"
        case .contractors, .engagements: return "building.2.crop.circle"
        case .contexts: return "clock.arrow.circlepath"
        case .assignments, .employers: return "person.crop.rectangle"
        }
    }
    var isCatalog: Bool { [.workplaces, .departments, .jobs, .contractors].contains(self) }
}
enum NovaDirectoryValue: Codable, Equatable {
    case string(String), number(Int64), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .number(v) }
        else { self = .string(try c.decode(String.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .null: try c.encodeNil(); case .string(let v): try c.encode(v); case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v) }
    }
    var text: String? { if case .string(let text) = self { return text }; return nil }
    var integer: Int64? { if case .number(let value) = self { return value }; return nil }
    var flag: Bool? { if case .bool(let value) = self { return value }; return nil }
}
struct NovaDirectoryRow: Identifiable, Equatable {
    let id: UUID
    let fields: [String: NovaDirectoryValue]
    var title: String { fields["name"]?.text ?? fields["title"]?.text ?? fields["job_title_snapshot"]?.text ?? fields["jurisdiction"]?.text ?? fields["description"]?.text ?? "Kayıt" }
    var version: Int64 { fields["version"]?.integer ?? 0 }
    var isArchived: Bool { fields["is_archived"]?.flag == true }
}
struct NovaDirectoryPage { let rows: [NovaDirectoryRow]; let next: UUID?; let parentVersion: Int64? }
struct NovaDirectoryIntent: Codable, Equatable {
    let scope: NovaPersonnelScope
    let kind: NovaDirectoryKind
    let operationID: UUID
    let mutationID: UUID
    let entityID: UUID?
    let expectedVersion: Int64
    let body: [String: NovaDirectoryValue]
}
struct NovaDirectoryCommit { let operationID: UUID; let entityID: UUID; let version: Int64 }
@MainActor struct NovaDirectoryClient {
    let read: (NovaPersonnelScope, NovaDirectoryKind, UUID?, UUID?, Bool) async throws -> NovaDirectoryPage
    let save: (NovaDirectoryIntent) async throws -> NovaDirectoryCommit
    let pending: (NovaPersonnelScope) async throws -> NovaDirectoryIntent?
}
