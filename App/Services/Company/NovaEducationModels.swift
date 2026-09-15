import Foundation

struct NovaEducationPackage: Codable {
    struct Topic: Codable { let code: String; let group_code: String; let legal_label: String; let legal_item: String }
    struct Preset: Codable, Identifiable {
        struct G4: Codable { struct Topic: Codable { let local_key: String; let title: String; let instruction_minutes: Int }; let topics: [Topic]; let budget_instruction_minutes: Int }
        let code: String; let label: String; let cycle: String; let hazard_class: String
        let minimum_lesson_units: Int; let default_instruction_minutes: Int; let default_break_minutes: Int
        let renewal_interval_months: Int; let topic_instruction_minutes: [String: Int]; let group4: G4
        let minutes_origin: String
        var id: String { code }
    }
    let package_key: String; let content_version: Int; let topics: [Topic]; let presets: [Preset]
    func preset(cycle: String, hazard: String) -> Preset? {
        presets.first { $0.cycle == cycle && $0.hazard_class == (hazard == "high" ? "very_hazardous" : hazard == "medium" ? "hazardous" : hazard) }
    }
    func topics(cycle: String, hazard: String) -> [NovaEducationTopic] {
        guard let p = preset(cycle: cycle, hazard: hazard) else {
            return [.init(code: "CUSTOM-1", group: "G4", title: cycle == "onboarding" ? "İşe ve göreve özgü uygulamalar" : "Eğitim konusu", instruction_minutes: cycle == "onboarding" ? 120 : 60)]
        }
        return topics.map { .init(code: $0.code, group: $0.group_code, title: $0.legal_label, instruction_minutes: p.topic_instruction_minutes[$0.code] ?? 0) }
            + p.group4.topics.map { .init(code: $0.local_key, group: "G4", title: $0.title, instruction_minutes: $0.instruction_minutes) }
    }
}
struct NovaEducationTopic: Codable, Equatable, Identifiable {
    var code: String; var group: String; var title: String; var instruction_minutes: Int
    var method = "face_to_face"; var trainer_ids: [String] = []; var parent_code: String?; var legal_title: String?
    var id: String { code }
}
struct NovaEducationTrainer: Codable, Equatable, Identifiable {
    var id = UUID().uuidString; var name = ""; var title = ""
}
struct NovaEducationPerson: Codable, Equatable, Identifiable {
    var id: UUID; var name: String?; var job_title = ""; var department: String?
}
struct NovaEducationLesson: Codable, Equatable, Identifiable {
    struct Allocation: Codable, Equatable { var topic_code: String; var minutes: Int }
    var id = UUID().uuidString; var starts_at: String; var instruction_minutes: Int; var break_minutes = 15
    var allocations: [Allocation]
}
struct NovaEducationDay: Codable, Equatable, Identifiable {
    var id = UUID(); var starts: Date; var lessonCount = 8; var extraBreakAfter = 4; var extraBreakMinutes = 0
}
struct NovaEducationScope: Codable, Equatable, Identifiable {
    var id = UUID(); var company_id: UUID; var workplace_id: UUID
    var logo_path: String?; var company_name: String?; var workplace_name: String?; var hazard_class: String?
    var group_name = "Genel"; var cycle = "initial"; var context_note = ""; var legal_name = ""
    var employer_name = ""; var employer_capacity = "representative"; var location = ""; var renewal_months = 0
    var topics: [NovaEducationTopic] = []; var lessons: [NovaEducationLesson] = []; var participants: [NovaEducationPerson] = []
    var draft_days: [NovaEducationDay]?
    var preset_code: String?; var starts_at: String?; var ends_at: String?; var held_on: String?; var valid_until: String?
    var instruction_minutes: Int?; var break_minutes: Int?; var lesson_units: Int?; var group4_minutes: Int?; var issues: [String]?
    var net: Int { topics.reduce(0) { $0 + $1.instruction_minutes } }
    var group4: Int { topics.filter { $0.group == "G4" }.reduce(0) { $0 + $1.instruction_minutes } }
    var breakTotal: Int { lessons.reduce(0) { $0 + $1.break_minutes } }
    static let cycles: [(String,String)] = [("initial","İlk Temel Eğitim"),("periodic_repeat","Tekrar Temel Eğitimi"),("onboarding","İşe Başlama Eğitimi"),("knowledge_refresh","Bilgi Yenileme"),("additional","İlave Eğitim"),("workplace_specific","Yeni İşyerine Özgü Eğitim"),("custom","Özel Eğitim")]
    var cycleName: String { Self.cycles.first { $0.0 == cycle }?.1 ?? cycle }
}
struct NovaEducationRecord: Codable, Equatable {
    var schema_version = 1; var completion_basis = "expert_record"; var provider_name = ""
    var trainers: [NovaEducationTrainer] = []; var scopes: [NovaEducationScope] = []
}
struct NovaEducationDraft: Codable, Equatable {
    var action = "save"; var id: UUID?; var expected_version: Int64 = 0
    var title = "Temel İSG Eğitimi"; var provider_name = ""; var notes = ""
    var trainers: [NovaEducationTrainer] = []; var scopes: [NovaEducationScope] = []
}
struct NovaEducationContext: Decodable {
    struct Certificate: Decodable, Identifiable { let document_id: UUID; let revision: Int; let scope_id: UUID; let person_id: UUID; let source_session_revision: Int64; var id: String { "\(document_id)-\(revision)" } }
    let certificates: [Certificate]
    struct Workplace: Decodable, Identifiable { let id: UUID; let company_id: UUID; let name: String; let hazard_class: String }
    struct Curriculum: Decodable, Identifiable { let id: UUID; let company_id: UUID; let workplace_id: UUID; let scope_key: String; let education: NovaEducationCurriculum }
    let schema_version: Int; let owner_id: UUID; let row: NovaTrainingSession?
    let package: NovaEducationPackage; let workplaces: [Workplace]; let curricula: [Curriculum]
    let catalog_enabled: Bool; let certificate_enabled: Bool
}
struct NovaEducationCurriculum: Codable {
    var topics: [NovaEducationTopic]; var context_note: String; var cycle: String; var group_name: String; var hazard_class: String
}
struct NovaEducationCertificate: Codable {
    struct Snapshot: Codable {
        let schema_version: Int; let template_version: Int; let theme_version: Int; let completion_basis: String
        let source_session_id: UUID; let source_session_revision: Int64; let person: NovaEducationPerson
        let scope: NovaEducationCertificateScope; let trainers: [NovaEducationTrainer]; let provider_name: String
        let logo_png_base64: String?
        let title: String; let issued_on: String; let is_draft: Bool; let number: String; let revision: Int; let document_type: String
    }
    let schema_version: Int; let owner_id: UUID; let ready: Bool; let issues: [String]; let document_id: UUID?; let revision: Int?
    let snapshot: Snapshot; let snapshot_hash: String?
}
// The server intentionally leaves other participants out of a personal certificate.
struct NovaEducationCertificateScope: Codable {
    let id: UUID; let company_id: UUID; let workplace_id: UUID; let legal_name: String; let company_name: String; let workplace_name: String
    let hazard_class: String; let cycle: String; let context_note: String; let topics: [NovaEducationTopic]; let lessons: [NovaEducationLesson]
    let employer_name: String; let employer_capacity: String; let location: String
    let instruction_minutes: Int; let break_minutes: Int; let lesson_units: Int; let held_on: String; let valid_until: String?
}
enum NovaEducationClock {
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Istanbul")!; return c }
    static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    static func date(_ value: String) -> Date? {
        let f = ISO8601DateFormatter(); if let d = f.date(from: value) { return d }
        f.formatOptions.insert(.withFractionalSeconds); return f.date(from: value)
    }
    static func day(_ date: Date) -> String { let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = Locale(identifier:"en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    static func initialDays(minutes: Int, basic: Bool) -> [NovaEducationDay] {
        let count = basic ? max(1,minutes / 45) : 1; let dayCount = (count + 7) / 8
        let first = calendar.date(byAdding: .day, value: -dayCount, to: Date())!
        return (0..<dayCount).map { n in .init(starts: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: calendar.date(byAdding: .day,value:n,to:first)!)!, lessonCount: min(8,count - n * 8)) }
    }
    static func days(from lessons: [NovaEducationLesson]) -> [NovaEducationDay] {
        let groups = Dictionary(grouping: lessons) { day(date($0.starts_at) ?? Date()) }
        return groups.keys.sorted().compactMap { key in
            guard let list = groups[key]?.sorted(by: { $0.starts_at < $1.starts_at }), let first = list.first, let start = date(first.starts_at) else { return nil }
            return .init(starts: start, lessonCount: list.count)
        }
    }
    static func distribute(topics: [NovaEducationTopic], days: [NovaEducationDay], basic: Bool) -> [NovaEducationLesson] {
        let positive = topics.filter { $0.instruction_minutes > 0 }; let total = positive.reduce(0) { $0 + $1.instruction_minutes }
        let n = days.reduce(0) { $0 + max(0,$1.lessonCount) }; guard total > 0,n > 0,n <= 200 else { return [] }
        var t = 0; var left = positive[0].instruction_minutes; var output: [NovaEducationLesson] = []; var used = 0
        for day in days.sorted(by: {$0.starts < $1.starts}) {
            var start = day.starts
            for local in 0..<max(0,day.lessonCount) {
                let ordinal = output.count
                let amount = ordinal == n - 1 ? total-used : min(basic ? 45 : total/n,max(0,total-used))
                guard amount > 0 else { continue }
                var remaining = amount; var allocations: [NovaEducationLesson.Allocation] = []
                while remaining > 0 && t < positive.count {
                    let m = min(remaining,left); allocations.append(.init(topic_code:positive[t].code,minutes:m)); remaining -= m; left -= m
                    if left == 0 { t += 1; if t < positive.count { left = positive[t].instruction_minutes } }
                }
                let rest = (basic ? 15 : 0) + (local + 1 == day.extraBreakAfter ? day.extraBreakMinutes : 0)
                output.append(.init(starts_at:iso(start),instruction_minutes:amount,break_minutes:rest,allocations:allocations))
                used += amount; start = start.addingTimeInterval(Double(amount+rest)*60)
            }
        }
        return output
    }
}

/// The steps the accordion asks for, in the order they are asked. A step is
/// finished only when it carries what the record needs — the same rule the
/// manual nonconformity form uses for its own accordion.
enum NovaEducationStep: String, CaseIterable, Identifiable {
    case info, trainers, scopes
    var id: String { rawValue }
}

extension NovaEducationDraft {
    private func filled(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func isComplete(_ step: NovaEducationStep) -> Bool {
        switch step {
        case .info: return filled(title)
        case .trainers: return trainers.contains { filled($0.name) }
        case .scopes: return scopes.contains { !$0.participants.isEmpty }
        }
    }
    var completedCount: Int { NovaEducationStep.allCases.filter { isComplete($0) }.count }
    var progress: Double { Double(completedCount) / Double(NovaEducationStep.allCases.count) }
    /// The next step after this one that is still unfinished, so a finished
    /// step can open the next one instead of leaving the expert to hunt.
    func nextIncomplete(after step: NovaEducationStep) -> NovaEducationStep? {
        let all = NovaEducationStep.allCases
        guard let at = all.firstIndex(of: step) else { return nil }
        return all[(at + 1)...].first { !isComplete($0) }
    }
}
