import Foundation

/// Versioned company directory transport, deliberately free of SDK and credentials.
enum NovaDirectoryKind: String, CaseIterable, Codable {
    case workplaces, departments, jobs, contractors, engagements, contexts, assignments, employers
    var title: String {
        switch self {
        case .workplaces: return RDLocalization.string("localizable.nova.directory.isyerleri.ba573a76", table: .localizable, fallback: "İşyerleri")
        case .departments: return "Departmanlar"
        case .jobs: return RDLocalization.string("localizable.nova.directory.gorev.ve.unvanlar.3b6da780", table: .localizable, fallback: "Görev ve Unvanlar")
        case .contractors: return RDLocalization.string("localizable.nova.directory.dis.firmalar.0d65ea43", table: .localizable, fallback: "Dış Firmalar")
        case .engagements: return RDLocalization.string("localizable.nova.directory.isyeri.iliskileri.aaeec732", table: .localizable, fallback: "İşyeri İlişkileri")
        case .contexts: return RDLocalization.string("localizable.nova.directory.isyeri.baglam.gecmisi.68d6a76b", table: .localizable, fallback: "İşyeri Bağlam Geçmişi")
        case .assignments: return RDLocalization.string("localizable.nova.directory.gorevlendirme.gecmisi.292a5411", table: .localizable, fallback: "Görevlendirme Geçmişi")
        case .employers: return RDLocalization.string("localizable.nova.directory.personelin.isvereni.ca42577b", table: .localizable, fallback: "Personelin İşvereni")
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
    var title: String { fields["name"]?.text ?? fields["title"]?.text ?? fields["job_title_snapshot"]?.text ?? fields["jurisdiction"]?.text ?? fields["description"]?.text ?? RDLocalization.string("localizable.nova.directory.record.fallback.title", table: .localizable, fallback: "Kayıt") }
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

/// Form feedback only: the transactional RPC remains authoritative for scope,
/// concurrent edits, unloaded ancestors and overlapping history pages.
enum NovaDirectoryFormRules {
    static func isDate(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ [4, 7].contains($0.offset) || (48...57).contains($0.element) }),
              let year = Int(value.prefix(4)), let month = Int(value.dropFirst(5).prefix(2)), let day = Int(value.suffix(2)),
              year > 0, (1...12).contains(month) else { return false }
        let leap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...days[month - 1]).contains(day)
    }

    static func allowedOptions(_ rows: [NovaDirectoryRow], field: String, workplace: String?, originalID: UUID?) -> [NovaDirectoryRow] {
        var blocked = Set<UUID>()
        if field == "parent_id", let originalID {
            blocked.insert(originalID)
            // Pagination may not contain the entire tree. Reject every known
            // descendant; never pretend this replaces the server's cycle guard.
            var changed = true
            while changed {
                changed = false
                for row in rows {
                    if let text = row.fields["parent_id"]?.text, let parent = UUID(uuidString: text), blocked.contains(parent), blocked.insert(row.id).inserted { changed = true }
                }
            }
        }
        return rows.filter { row in
            if ["parent_id", "department_id"].contains(field) {
                return !row.isArchived && !blocked.contains(row.id) && row.fields["workplace_id"]?.text?.lowercased() == workplace?.lowercased()
            }
            return !row.isArchived
        }
    }

    static func selecting(_ field: String, value: String, in fields: [String: String]) -> [String: String] {
        var result = fields
        if field == "workplace_id", fields[field] != value { result["parent_id"] = ""; result["department_id"] = "" }
        result[field] = value
        return result
    }

    static func validation(kind: NovaDirectoryKind, fields: [String: String], options: [String: [NovaDirectoryRow]], originalID: UUID?) -> String? {
        let values = fields.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if [.engagements, .contexts, .assignments].contains(kind) {
            let start = values["starts_on", default: ""], end = values["ends_before", default: ""]
            if !isDate(start) { return RDLocalization.string("localizable.nova.directory.baslangic.tarihini.yyyy.aa.gg.biciminde.gecerli..ab922e2c", table: .localizable, fallback: "Başlangıç tarihini YYYY-AA-GG biçiminde geçerli bir tarih olarak girin.") }
            if kind == .engagements && !end.isEmpty {
                if !isDate(end) { return RDLocalization.string("localizable.nova.directory.bitis.tarihini.yyyy.aa.gg.biciminde.gecerli.bir..a16549c5", table: .localizable, fallback: "Bitiş tarihini YYYY-AA-GG biçiminde geçerli bir tarih olarak girin.") }
                if end <= start { return RDLocalization.string("localizable.nova.directory.bitis.haric.baslangic.tarihinden.sonra.olmali.634aae6f", table: .localizable, fallback: "Bitiş (hariç), başlangıç tarihinden sonra olmalı.") }
            }
            if let previous = values["previous_id"], !previous.isEmpty {
                guard let row = options["previous_id"]?.first(where: { $0.id.uuidString.lowercased() == previous.lowercased() }),
                      let priorStart = row.fields["starts_on"]?.text, isDate(priorStart) else { return RDLocalization.string("localizable.nova.directory.onceki.donemi.listeden.yeniden.secin.gerekirse.d.aac0579f", table: .localizable, fallback: "Önceki dönemi listeden yeniden seçin; gerekirse diğer kayıtları yükleyin.") }
                if start <= priorStart || row.fields["ends_before"]?.text.map({ start >= $0 }) == true {
                    return RDLocalization.string("localizable.nova.directory.yeni.baslangic.onceki.donemin.baslangicindan.son.9f10fbc6", table: .localizable, fallback: "Yeni başlangıç, önceki dönemin başlangıcından sonra ve varsa bitişinden önce olmalı.")
                }
            }
        }
        for key in ["parent_id", "department_id"] {
            guard let selected = values[key], !selected.isEmpty else { continue }
            let rows = options[key, default: []]
            if !allowedOptions(rows, field: key, workplace: values["workplace_id"], originalID: originalID).contains(where: { $0.id.uuidString.lowercased() == selected.lowercased() }) {
                return RDLocalization.string("localizable.nova.directory.departmani.secili.isyerinin.gecerli.listesinden..06cd2a68", table: .localizable, fallback: "Departmanı seçili işyerinin geçerli listesinden seçin; kendi alt departmanınızı üst departman yapamazsınız.")
            }
        }
        return nil
    }
}
