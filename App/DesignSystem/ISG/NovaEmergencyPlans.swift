import Foundation

/// What a plan says about itself today. The value is always the server's: it is
/// worked out at read time from the active version's own dates.
///
/// `periodUnknown` is its own answer on purpose. A plan published with no end
/// date is a gap in the record, never a statement that it still stands.
enum NovaEmergencyState: String, CaseIterable, Identifiable, Equatable {
    case neverPublished = "never_published"
    case periodUnknown = "period_unknown"
    case expired
    case dueSoon = "due_soon"
    case valid
    var id: String { rawValue }
}

/// Four counters over five states, every state in exactly one group.
enum NovaEmergencyGroup: String, CaseIterable, Identifiable {
    case expired, untracked, current
    case dueSoon = "due_soon"
    var id: String { rawValue }

    var states: [NovaEmergencyState] {
        switch self {
        case .expired: return [.expired]
        case .untracked: return [.neverPublished, .periodUnknown]
        case .dueSoon: return [.dueSoon]
        case .current: return [.valid]
        }
    }
    var title: String {
        switch self {
        case .expired: return RDLocalization.string("localizable.nova.emergency.group.expired", table: .localizable, fallback: "Süresi doldu")
        case .untracked: return RDLocalization.string("localizable.nova.emergency.group.untracked", table: .localizable, fallback: "Takipsiz")
        case .dueSoon: return RDLocalization.string("localizable.nova.emergency.group.due", table: .localizable, fallback: "Yaklaşıyor")
        case .current: return RDLocalization.string("localizable.nova.emergency.group.current", table: .localizable, fallback: "Güncel")
        }
    }
    var footer: String {
        switch self {
        case .expired: return RDLocalization.string("localizable.nova.emergency.group.expired.footer", table: .localizable, fallback: "tarih geçti")
        case .untracked: return RDLocalization.string("localizable.nova.emergency.group.untracked.footer", table: .localizable, fallback: "süre yazılmamış")
        case .dueSoon: return RDLocalization.string("localizable.nova.emergency.group.due.footer", table: .localizable, fallback: "yaklaşan")
        case .current: return RDLocalization.string("localizable.nova.emergency.group.current.footer", table: .localizable, fallback: "yürürlükte")
        }
    }
    var symbol: String {
        switch self {
        case .expired: return "exclamationmark.triangle"
        case .untracked: return "questionmark.circle"
        case .dueSoon: return "clock"
        case .current: return "checkmark.circle"
        }
    }
    static func of(_ state: NovaEmergencyState) -> NovaEmergencyGroup {
        allCases.first { $0.states.contains(state) } ?? .untracked
    }
}

/// The roles a team entry may carry. The set lives in the schema, so the client
/// offers exactly what the server accepts and nothing else.
enum NovaEmergencyRole: String, CaseIterable, Identifiable, Equatable {
    case coordinator, fire, other
    case firstAid = "first_aid"
    case evacuation
    var id: String { rawValue }
    var title: String {
        switch self {
        case .coordinator: return RDLocalization.string("localizable.nova.emergency.role.coordinator", table: .localizable, fallback: "Koordinatör")
        case .fire: return RDLocalization.string("localizable.nova.emergency.role.fire", table: .localizable, fallback: "Yangın")
        case .firstAid: return RDLocalization.string("localizable.nova.emergency.role.firstaid", table: .localizable, fallback: "İlk yardım")
        case .evacuation: return RDLocalization.string("localizable.nova.emergency.role.evacuation", table: .localizable, fallback: "Tahliye")
        case .other: return RDLocalization.string("localizable.nova.emergency.role.other", table: .localizable, fallback: "Diğer")
        }
    }
    var symbol: String {
        switch self {
        case .coordinator: return "person.badge.shield.checkmark"
        case .fire: return "flame"
        case .firstAid: return "cross.case"
        case .evacuation: return "figure.walk.departure"
        case .other: return "person"
        }
    }
}

/// One person frozen into a plan. Changing personnel later never edits a
/// published plan: this is a snapshot, not a link.
struct NovaEmergencyMember: Identifiable, Equatable {
    var id: String { fullName + role.rawValue }
    let fullName: String
    let role: NovaEmergencyRole
    let contact: String?
}

/// One version of a plan, with the team, dates and scope it was published with.
struct NovaEmergencyVersion: Identifiable, Equatable {
    var id: Int { version }
    let version: Int
    let state: String
    let scope: String
    let preparedOn: String
    let validUntil: String?
    let needsReview: Bool
    let reviewNote: String?
    let team: [NovaEmergencyMember]
    let createdAt: Date?
    var isActive: Bool { state == "active" }
}

/// One plan as the board sees it: the version that stands today.
struct NovaEmergencyPlan: Identifiable, Equatable {
    let id: UUID
    let companyID: UUID?
    let companyName: String?
    let workplaceID: UUID?
    let workplaceName: String?
    let version: Int
    let versionsTotal: Int
    let scope: String
    let preparedOn: String
    let validUntil: String?
    let state: NovaEmergencyState
    let group: NovaEmergencyGroup
    let noticeDays: Int
    /// Forced by the absence of a written basis. Nothing on this side can set
    /// it, and the server has no field for it either.
    let needsReview: Bool
    let reviewNote: String?
    let team: [NovaEmergencyMember]
    let teamSize: Int
    let versions: [NovaEmergencyVersion]
}

struct NovaEmergencyCatalogue: Equatable {
    struct Workplace: Identifiable, Equatable { let id: UUID; let name: String; let needsReview: Bool }
    let workplaces: [Workplace]
    let roles: [NovaEmergencyRole]
    let noticeDays: Int
    /// The product proposes no renewal period, because no approved catalogue
    /// exists. Whatever date the expert writes is stored as the expert's.
    let periodDefaultsOffered: Bool
}

struct NovaEmergencyBoard: Equatable {
    struct CompanyTally: Identifiable, Equatable {
        let id: UUID
        let name: String
        let total: Int
        let counts: [String: Int]
    }
    let rows: [NovaEmergencyPlan]
    let counts: [String: Int]
    let companies: [CompanyTally]
    let total: Int
    let hasMore: Bool
    let offset: Int
    let noticeDays: Int
    func count(_ group: NovaEmergencyGroup) -> Int {
        group.states.reduce(0) { $0 + (counts[$1.rawValue] ?? 0) }
    }
    var needsAttention: Int { count(.expired) + count(.dueSoon) + count(.untracked) }
}

struct NovaEmergencyQuery: Equatable {
    var company: UUID?
    var state: String?
    var workplace: UUID?
    var search: String = ""
    var limit: Int = 10
    var offset: Int = 0
}

/// What the expert fills in to publish a plan or renew one. There is no edit
/// draft: correcting a plan means publishing the next version.
struct NovaEmergencyPlanDraft: Equatable {
    /// Empty means a new plan; set means the next version of that plan.
    var planID: UUID?
    var workplaceID: UUID?
    var scope: String = ""
    var preparedOn: String = ""
    var validUntil: String = ""
    var reviewNote: String = ""
    var team: [NovaEmergencyMember] = []
    var isRenewal: Bool { planID != nil }
}

enum NovaEmergencyFailure: Error, Equatable {
    case denied, planRequired, featureUnavailable, moduleUnavailable, validation, conflict
    case preparedInFuture, roleUnknown
    case unavailable
    var message: String {
        switch self {
        case .denied: return RDLocalization.string("localizable.nova.emergency.error.denied", table: .localizable,
            fallback: "Bu kayda erişim yok.")
        case .planRequired: return RDLocalization.string("localizable.nova.emergency.error.plan", table: .localizable,
            fallback: "Bu işlem için Plus veya Pro aboneliği gerekiyor.")
        case .featureUnavailable: return RDLocalization.string("localizable.nova.emergency.error.feature", table: .localizable,
            fallback: "Modüller henüz açık değil.")
        case .moduleUnavailable: return RDLocalization.string("localizable.nova.emergency.error.module", table: .localizable,
            fallback: "Acil durum planları modülü henüz açık değil.")
        case .validation: return RDLocalization.string("localizable.nova.emergency.error.validation", table: .localizable,
            fallback: "Girilen bilgiler eksik veya birbiriyle uyumsuz.")
        case .conflict: return RDLocalization.string("localizable.nova.emergency.error.conflict", table: .localizable,
            fallback: "Kayıt bu sırada başka bir yerden değişti. Yenileyip tekrar deneyin.")
        case .preparedInFuture: return RDLocalization.string("localizable.nova.emergency.error.future", table: .localizable,
            fallback: "Hazırlanma tarihi bugünden ileri olamaz.")
        case .roleUnknown: return RDLocalization.string("localizable.nova.emergency.error.role", table: .localizable,
            fallback: "Ekip görevi tanınmadı.")
        case .unavailable: return RDLocalization.string("localizable.nova.emergency.error.unavailable", table: .localizable,
            fallback: "Kayıt alınamadı. Bağlantıyı kontrol edip tekrar deneyin.")
        }
    }
}

enum NovaEmergencyWords {
    static func state(_ value: NovaEmergencyState) -> String {
        switch value {
        case .neverPublished: return RDLocalization.string("localizable.nova.emergency.state.never", table: .localizable, fallback: "Plan yok")
        case .periodUnknown: return RDLocalization.string("localizable.nova.emergency.state.unknown", table: .localizable, fallback: "Süre yazılmamış")
        case .expired: return RDLocalization.string("localizable.nova.emergency.state.expired", table: .localizable, fallback: "Süresi doldu")
        case .dueSoon: return RDLocalization.string("localizable.nova.emergency.state.due", table: .localizable, fallback: "Yaklaşıyor")
        case .valid: return RDLocalization.string("localizable.nova.emergency.state.valid", table: .localizable, fallback: "Yürürlükte")
        }
    }
    /// Why the row reads the way it does. Every state has a reason.
    static func explain(_ plan: NovaEmergencyPlan) -> String {
        switch plan.state {
        case .neverPublished: return RDLocalization.string("localizable.nova.emergency.explain.never", table: .localizable,
            fallback: "Bu işyeri için yayımlanmış plan yok.")
        case .periodUnknown: return RDLocalization.string("localizable.nova.emergency.explain.unknown", table: .localizable,
            fallback: "Plan var ama geçerlilik bitişi yazılmamış. Tarih girilene kadar takip üretilmez.")
        case .expired: return RDLocalization.string("localizable.nova.emergency.explain.expired", table: .localizable,
            fallback: "Geçerlilik tarihi geçti.")
        case .dueSoon: return RDLocalization.string("localizable.nova.emergency.explain.due", table: .localizable,
            fallback: "Geçerlilik tarihi uyarı penceresinin içinde.")
        case .valid: return RDLocalization.string("localizable.nova.emergency.explain.valid", table: .localizable,
            fallback: "Plan yürürlükte.")
        }
    }
    /// The sentence the screen carries wherever a date is shown.
    static let periodAttribution = RDLocalization.string("localizable.nova.emergency.period.note", table: .localizable,
        fallback: "Ürün yenileme süresi önermez. Yazdığınız tarih uzmanın kendi kararı olarak kaydedilir.")
    /// The sentence beside the review flag.
    static let reviewNote = RDLocalization.string("localizable.nova.emergency.review.note", table: .localizable,
        fallback: "Dayanağını yazmadığınız plan gözden geçirilecek olarak işaretlenir. Bu işaret elle kaldırılamaz.")
    /// The sentence the renewal form carries.
    static let renewalNote = RDLocalization.string("localizable.nova.emergency.renewal.note", table: .localizable,
        fallback: "Yenileme yeni bir sürüm açar. Önceki sürüm kendi ekibi, tarihleri ve kapsamıyla kayıtta kalır.")
}
