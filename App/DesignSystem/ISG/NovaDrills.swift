import Foundation

/// What a drill says about itself today. The value is always the server's.
///
/// A planned date that has passed reads `overdue`. It is deliberately never
/// `performed`: a date going by is not a drill being held.
enum NovaDrillState: String, CaseIterable, Identifiable, Equatable {
    case overdue, scheduled, performed, cancelled
    case dueSoon = "due_soon"
    var id: String { rawValue }
}

/// Four counters over five states, every state in exactly one group.
enum NovaDrillGroup: String, CaseIterable, Identifiable {
    case overdue, scheduled, closed
    case dueSoon = "due_soon"
    var id: String { rawValue }

    var states: [NovaDrillState] {
        switch self {
        case .overdue: return [.overdue]
        case .dueSoon: return [.dueSoon]
        case .scheduled: return [.scheduled]
        case .closed: return [.performed, .cancelled]
        }
    }
    var title: String {
        switch self {
        case .overdue: return RDLocalization.string("localizable.nova.drill.group.overdue", table: .localizable, fallback: "Geçti")
        case .dueSoon: return RDLocalization.string("localizable.nova.drill.group.due", table: .localizable, fallback: "Yaklaşıyor")
        case .scheduled: return RDLocalization.string("localizable.nova.drill.group.scheduled", table: .localizable, fallback: "Planlı")
        case .closed: return RDLocalization.string("localizable.nova.drill.group.closed", table: .localizable, fallback: "Kapandı")
        }
    }
    var footer: String {
        switch self {
        case .overdue: return RDLocalization.string("localizable.nova.drill.group.overdue.footer", table: .localizable, fallback: "yapılmadı")
        case .dueSoon: return RDLocalization.string("localizable.nova.drill.group.due.footer", table: .localizable, fallback: "yaklaşan")
        case .scheduled: return RDLocalization.string("localizable.nova.drill.group.scheduled.footer", table: .localizable, fallback: "ileri tarihli")
        case .closed: return RDLocalization.string("localizable.nova.drill.group.closed.footer", table: .localizable, fallback: "yapıldı / iptal")
        }
    }
    var symbol: String {
        switch self {
        case .overdue: return "exclamationmark.triangle"
        case .dueSoon: return "clock"
        case .scheduled: return "calendar"
        case .closed: return "checkmark.circle"
        }
    }
    static func of(_ state: NovaDrillState) -> NovaDrillGroup {
        allCases.first { $0.states.contains(state) } ?? .scheduled
    }
}

/// One person who was there, as they were named at the time. Changing the
/// personnel register afterwards never edits a performed drill.
struct NovaDrillParticipant: Identifiable, Equatable {
    let id: UUID
    let fullName: String
}

/// One drill: what it rehearsed, when, and what came out of it.
struct NovaDrill: Identifiable, Equatable {
    let id: UUID
    let companyID: UUID?
    let companyName: String?
    let workplaceID: UUID?
    let workplaceName: String?
    let planID: UUID
    /// The plan version this drill rehearsed, pinned when it was planned.
    let planVersion: Int
    let planScope: String?
    /// Whether the plan has moved on since. The drill is never re-pointed.
    let planVersionSuperseded: Bool
    let plannedOn: String
    let performedOn: String?
    let state: NovaDrillState
    let group: NovaDrillGroup
    let noticeDays: Int
    /// Read from the record, never inferred from a date going by.
    let performed: Bool
    let observation: String?
    let improvement: String?
    let cancelledReason: String?
    let participants: [NovaDrillParticipant]
    let participantCount: Int
    let participantsSnapshotted: Bool
}

/// A plan that can be rehearsed: published, in force, and this account's.
struct NovaDrillPlanOption: Identifiable, Equatable {
    var id: UUID { planID }
    let planID: UUID
    let version: Int
    let scope: String
    let workplaceID: UUID
    let workplaceName: String
    let validUntil: String?
}

struct NovaDrillCatalogue: Equatable {
    struct Employee: Identifiable, Equatable { let id: UUID; let fullName: String }
    let plans: [NovaDrillPlanOption]
    let employees: [Employee]
    let noticeDays: Int
    /// The product proposes no drill period: no approved catalogue exists.
    let periodDefaultsOffered: Bool
}

struct NovaDrillBoard: Equatable {
    struct CompanyTally: Identifiable, Equatable {
        let id: UUID
        let name: String
        let total: Int
        let counts: [String: Int]
    }
    let rows: [NovaDrill]
    let counts: [String: Int]
    let companies: [CompanyTally]
    let total: Int
    let hasMore: Bool
    let offset: Int
    let noticeDays: Int
    func count(_ group: NovaDrillGroup) -> Int {
        group.states.reduce(0) { $0 + (counts[$1.rawValue] ?? 0) }
    }
    var needsAttention: Int { count(.overdue) + count(.dueSoon) }
}

struct NovaDrillQuery: Equatable {
    var company: UUID?
    var state: String?
    var workplace: UUID?
    var search: String = ""
    var limit: Int = 10
    var offset: Int = 0
}

/// What the expert fills in to plan a drill.
struct NovaDrillPlanDraft: Equatable {
    var planID: UUID?
    var plannedOn: String = ""
}

/// What the expert fills in to record what happened.
struct NovaDrillResultDraft: Equatable {
    var drillID: UUID?
    var planScope: String = ""
    var performedOn: String = ""
    var participants: Set<UUID> = []
    var observation: String = ""
    var improvement: String = ""
}

enum NovaDrillFailure: Error, Equatable {
    case denied, planRequired, featureUnavailable, moduleUnavailable, validation, conflict
    case performedInFuture, participantOutOfScope, alreadyPerformed
    case unavailable
    var message: String {
        switch self {
        case .denied: return RDLocalization.string("localizable.nova.drill.error.denied", table: .localizable,
            fallback: "Bu kayda erişim yok.")
        case .planRequired: return RDLocalization.string("localizable.nova.drill.error.plan", table: .localizable,
            fallback: "Bu işlem için Plus veya Pro aboneliği gerekiyor.")
        case .featureUnavailable: return RDLocalization.string("localizable.nova.drill.error.feature", table: .localizable,
            fallback: "Modüller henüz açık değil.")
        case .moduleUnavailable: return RDLocalization.string("localizable.nova.drill.error.module", table: .localizable,
            fallback: "Tatbikat modülü henüz açık değil.")
        case .validation: return RDLocalization.string("localizable.nova.drill.error.validation", table: .localizable,
            fallback: "Girilen bilgiler eksik veya birbiriyle uyumsuz.")
        case .conflict: return RDLocalization.string("localizable.nova.drill.error.conflict", table: .localizable,
            fallback: "Kayıt bu sırada başka bir yerden değişti. Yenileyip tekrar deneyin.")
        case .performedInFuture: return RDLocalization.string("localizable.nova.drill.error.future", table: .localizable,
            fallback: "Tatbikat tarihi bugünden ileri olamaz.")
        case .participantOutOfScope: return RDLocalization.string("localizable.nova.drill.error.participant", table: .localizable,
            fallback: "Katılımcılardan biri bu firmanın personeli değil.")
        case .alreadyPerformed: return RDLocalization.string("localizable.nova.drill.error.performed", table: .localizable,
            fallback: "Yapılmış tatbikat iptal edilemez veya yeniden yazılamaz.")
        case .unavailable: return RDLocalization.string("localizable.nova.drill.error.unavailable", table: .localizable,
            fallback: "Kayıt alınamadı. Bağlantıyı kontrol edip tekrar deneyin.")
        }
    }
}

enum NovaDrillWords {
    static func state(_ value: NovaDrillState) -> String {
        switch value {
        case .overdue: return RDLocalization.string("localizable.nova.drill.state.overdue", table: .localizable, fallback: "Tarihi geçti")
        case .dueSoon: return RDLocalization.string("localizable.nova.drill.state.due", table: .localizable, fallback: "Yaklaşıyor")
        case .scheduled: return RDLocalization.string("localizable.nova.drill.state.scheduled", table: .localizable, fallback: "Planlandı")
        case .performed: return RDLocalization.string("localizable.nova.drill.state.performed", table: .localizable, fallback: "Yapıldı")
        case .cancelled: return RDLocalization.string("localizable.nova.drill.state.cancelled", table: .localizable, fallback: "İptal edildi")
        }
    }
    /// Why the row reads the way it does. Every state has a reason.
    static func explain(_ drill: NovaDrill) -> String {
        switch drill.state {
        case .overdue: return RDLocalization.string("localizable.nova.drill.explain.overdue", table: .localizable,
            fallback: "Planlanan tarih geçti ve tatbikat kaydı girilmedi.")
        case .dueSoon: return RDLocalization.string("localizable.nova.drill.explain.due", table: .localizable,
            fallback: "Planlanan tarih uyarı penceresinin içinde.")
        case .scheduled: return RDLocalization.string("localizable.nova.drill.explain.scheduled", table: .localizable,
            fallback: "İleri bir tarihe planlandı. Planlamak yapmak değildir.")
        case .performed: return String(format: RDLocalization.string("localizable.nova.drill.explain.performed",
            table: .localizable, fallback: "%d katılımcıyla yapıldı."), drill.participantCount)
        case .cancelled: return drill.cancelledReason ?? RDLocalization.string(
            "localizable.nova.drill.explain.cancelled", table: .localizable, fallback: "Bu tatbikattan vazgeçildi.")
        }
    }
    /// The sentence the board carries at the top.
    static let planningIsNotPerforming = RDLocalization.string("localizable.nova.drill.planning.note", table: .localizable,
        fallback: "Planlamak yapmak değildir. Tarihi geçen tatbikat yapılmış sayılmaz; kaydı siz girersiniz.")
    /// The sentence the result form carries.
    static let snapshotNote = RDLocalization.string("localizable.nova.drill.snapshot.note", table: .localizable,
        fallback: "Katılımcılar kaydettiğiniz andaki adlarıyla donar. Personel kaydı sonradan değişse de bu tatbikat değişmez.")
    /// The sentence beside a pinned plan version.
    static let pinnedNote = RDLocalization.string("localizable.nova.drill.pinned.note", table: .localizable,
        fallback: "Tatbikat, prova ettiği plan sürümüne sabitlidir. Sonradan yayımlanan plan bu kaydı taşımaz.")
}
