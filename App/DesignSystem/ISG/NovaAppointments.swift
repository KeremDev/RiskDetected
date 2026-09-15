import Foundation

/// Where an appointment stands today. The value is always the server's: it is
/// worked out from the appointment's own dates at read time.
///
/// Every state is its own counter; there is no group layer because nothing
/// would be grouped.
enum NovaAppointmentState: String, CaseIterable, Identifiable, Equatable {
    case active, upcoming, ended
    var id: String { rawValue }
    var title: String {
        switch self {
        case .active: return RDLocalization.string("localizable.nova.appointment.state.active", table: .localizable, fallback: "Görevde")
        case .upcoming: return RDLocalization.string("localizable.nova.appointment.state.upcoming", table: .localizable, fallback: "Başlayacak")
        case .ended: return RDLocalization.string("localizable.nova.appointment.state.ended", table: .localizable, fallback: "Sona erdi")
        }
    }
    var footer: String {
        switch self {
        case .active: return RDLocalization.string("localizable.nova.appointment.state.active.footer", table: .localizable, fallback: "yürürlükte")
        case .upcoming: return RDLocalization.string("localizable.nova.appointment.state.upcoming.footer", table: .localizable, fallback: "ileri tarihli")
        case .ended: return RDLocalization.string("localizable.nova.appointment.state.ended.footer", table: .localizable, fallback: "geçmiş")
        }
    }
    var symbol: String {
        switch self {
        case .active: return "person.badge.shield.checkmark"
        case .upcoming: return "calendar.badge.clock"
        case .ended: return "person.badge.minus"
        }
    }
}

/// The roles the schema fixes. Offered as they are, so the client can never
/// send one the server would refuse.
enum NovaAppointmentKind: String, CaseIterable, Identifiable, Equatable {
    case representative
    case supportStaff = "support_staff"
    case teamMember = "team_member"
    case firstAid = "first_aid"
    case fireTeam = "fire_team"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .representative: return RDLocalization.string("localizable.nova.appointment.kind.representative", table: .localizable, fallback: "Çalışan temsilcisi")
        case .supportStaff: return RDLocalization.string("localizable.nova.appointment.kind.support", table: .localizable, fallback: "Destek elemanı")
        case .teamMember: return RDLocalization.string("localizable.nova.appointment.kind.team", table: .localizable, fallback: "Ekip üyesi")
        case .firstAid: return RDLocalization.string("localizable.nova.appointment.kind.firstaid", table: .localizable, fallback: "İlk yardımcı")
        case .fireTeam: return RDLocalization.string("localizable.nova.appointment.kind.fire", table: .localizable, fallback: "Yangın ekibi")
        }
    }
}

/// Why this person holds the role. A representative is elected by the workers;
/// support staff are appointed by the employer. Saying which is the point.
enum NovaAppointmentBasis: String, CaseIterable, Identifiable, Equatable {
    case elected, appointed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .elected: return RDLocalization.string("localizable.nova.appointment.basis.elected", table: .localizable, fallback: "Seçimle")
        case .appointed: return RDLocalization.string("localizable.nova.appointment.basis.appointed", table: .localizable, fallback: "Atamayla")
        }
    }
    var symbol: String {
        switch self {
        case .elected: return "hand.raised"
        case .appointed: return "signature"
        }
    }
}

/// Where an appointment's attached letter actually lives, once one is filed
/// and clean.
struct NovaAppointmentAssetDownload: Equatable {
    let bucket: String
    let path: String
}

/// One appointment as the board sees it.
struct NovaAppointment: Identifiable, Equatable {
    let id: UUID
    let companyID: UUID?
    let companyName: String?
    let employeeID: UUID?
    let employeeName: String?
    let employeeArchived: Bool
    let workplaceID: UUID?
    let workplaceName: String?
    let kind: NovaAppointmentKind
    /// What the product would usually expect for this role. A suggestion for
    /// the form, never a rule.
    let usualBasis: NovaAppointmentBasis?
    let startsOn: String
    let endsBefore: String?
    let state: NovaAppointmentState
    let basis: NovaAppointmentBasis?
    let basisNote: String?
    let assetID: UUID?
    let assetDownload: NovaAppointmentAssetDownload?
    /// Nothing legal was checked, and there is nowhere to record that it was.
    let qualificationVerified: Bool
}

struct NovaAppointmentCatalogue: Equatable {
    struct Workplace: Identifiable, Equatable { let id: UUID; let name: String }
    struct Employee: Identifiable, Equatable { let id: UUID; let fullName: String }
    struct Role: Identifiable, Equatable {
        var id: String { kind.rawValue }
        let kind: NovaAppointmentKind
        let usualBasis: NovaAppointmentBasis
    }
    let roles: [Role]
    let bases: [NovaAppointmentBasis]
    let workplaces: [Workplace]
    let employees: [Employee]
    /// No approved catalogue says how many a workplace needs.
    let requiredCountKnown: Bool
    let qualificationCheckAvailable: Bool
}

struct NovaAppointmentBoard: Equatable {
    struct CompanyTally: Identifiable, Equatable {
        let id: UUID
        let name: String
        let total: Int
        let counts: [String: Int]
    }
    let rows: [NovaAppointment]
    let counts: [String: Int]
    let companies: [CompanyTally]
    let total: Int
    let hasMore: Bool
    let offset: Int
    func count(_ state: NovaAppointmentState) -> Int { counts[state.rawValue] ?? 0 }
    var needsAttention: Int { count(.upcoming) }
}

struct NovaAppointmentQuery: Equatable {
    var company: UUID?
    var state: String?
    var workplace: UUID?
    var role: String?
    var search: String = ""
    var limit: Int = 10
    var offset: Int = 0
}

/// What the expert fills in to record an appointment.
struct NovaAppointmentDraft: Equatable {
    var employeeID: UUID?
    var workplaceID: UUID?
    var kind: NovaAppointmentKind = .representative
    var basis: NovaAppointmentBasis = .elected
    var startsOn: String = ""
    var endsBefore: String = ""
    var basisNote: String = ""
    var assetID: UUID?
}

/// What the expert fills in to end one, or to correct the date they ended it.
struct NovaAppointmentEndDraft: Equatable {
    var appointmentID: UUID?
    var employeeName: String = ""
    var startsOn: String = ""
    var endsBefore: String = ""
    var isCorrection: Bool = false
}

enum NovaAppointmentFailure: Error, Equatable {
    case denied, planRequired, featureUnavailable, moduleUnavailable, validation, conflict
    case overlap, basisRequired
    case unavailable
    var message: String {
        switch self {
        case .denied: return RDLocalization.string("localizable.nova.appointment.error.denied", table: .localizable,
            fallback: "Bu kayda erişim yok.")
        case .planRequired: return RDLocalization.string("localizable.nova.appointment.error.plan", table: .localizable,
            fallback: "Bu işlem için Plus veya Pro aboneliği gerekiyor.")
        case .featureUnavailable: return RDLocalization.string("localizable.nova.appointment.error.feature", table: .localizable,
            fallback: "Modüller henüz açık değil.")
        case .moduleUnavailable: return RDLocalization.string("localizable.nova.appointment.error.module", table: .localizable,
            fallback: "Atama modülü henüz açık değil.")
        case .validation: return RDLocalization.string("localizable.nova.appointment.error.validation", table: .localizable,
            fallback: "Girilen bilgiler eksik veya birbiriyle uyumsuz.")
        case .conflict: return RDLocalization.string("localizable.nova.appointment.error.conflict", table: .localizable,
            fallback: "Kayıt bu sırada başka bir yerden değişti. Yenileyip tekrar deneyin.")
        case .overlap: return RDLocalization.string("localizable.nova.appointment.error.overlap", table: .localizable,
            fallback: "Aynı kişi aynı görevi aynı işyerinde çakışan tarihlerde üstlenemez.")
        case .basisRequired: return RDLocalization.string("localizable.nova.appointment.error.basis", table: .localizable,
            fallback: "Görevin seçimle mi atamayla mı verildiğini belirtin.")
        case .unavailable: return RDLocalization.string("localizable.nova.appointment.error.unavailable", table: .localizable,
            fallback: "Kayıt alınamadı. Bağlantıyı kontrol edip tekrar deneyin.")
        }
    }
}

enum NovaAppointmentWords {
    /// Why the row reads the way it does. Every state has a reason.
    static func explain(_ entry: NovaAppointment) -> String {
        switch entry.state {
        case .active: return entry.endsBefore.map {
            String(format: RDLocalization.string("localizable.nova.appointment.explain.active.until",
                table: .localizable, fallback: "%@ tarihine kadar görevde."), $0)
        } ?? RDLocalization.string("localizable.nova.appointment.explain.active", table: .localizable,
            fallback: "Bitiş tarihi girilmemiş; görev sürüyor.")
        case .upcoming: return String(format: RDLocalization.string("localizable.nova.appointment.explain.upcoming",
            table: .localizable, fallback: "%@ tarihinde başlayacak."), entry.startsOn)
        case .ended: return String(format: RDLocalization.string("localizable.nova.appointment.explain.ended",
            table: .localizable, fallback: "%@ tarihinde sona erdi."), entry.endsBefore ?? entry.startsOn)
        }
    }
    /// The sentence the board carries at the top.
    static let noQualificationNote = RDLocalization.string("localizable.nova.appointment.qualification.note",
        table: .localizable,
        fallback: "Görevi üstlenmek yeterli olmak demek değildir. Uygulama hiçbir yasal şartı doğrulamaz ve kimseye yeterli etiketi koymaz.")
    /// The sentence the board carries beside the counters.
    static let noRequiredCountNote = RDLocalization.string("localizable.nova.appointment.count.note",
        table: .localizable,
        fallback: "Ürün bir işyeri için kaç kişi gerektiğini söylemez; onaylanmış bir sayı kataloğu yok.")
}
