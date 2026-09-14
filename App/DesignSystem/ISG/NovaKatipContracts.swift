import Foundation

/// Where a contract stands today. The value is always the server's: it comes
/// from the contract's own dates and its archived flag at read time.
enum NovaKatipState: String, CaseIterable, Identifiable, Equatable {
    case upcoming, active, expiring, expired, archived
    var id: String { rawValue }
    var title: String {
        switch self {
        case .upcoming: return RDLocalization.string("localizable.nova.katip.state.upcoming", table: .localizable, fallback: "Başlayacak")
        case .active: return RDLocalization.string("localizable.nova.katip.state.active", table: .localizable, fallback: "Yürürlükte")
        case .expiring: return RDLocalization.string("localizable.nova.katip.state.expiring", table: .localizable, fallback: "Bitiyor")
        case .expired: return RDLocalization.string("localizable.nova.katip.state.expired", table: .localizable, fallback: "Süresi doldu")
        case .archived: return RDLocalization.string("localizable.nova.katip.state.archived", table: .localizable, fallback: "Arşivlendi")
        }
    }
}

/// Four counters over five states, every state in exactly one group.
enum NovaKatipGroup: String, CaseIterable, Identifiable {
    case expired, expiring, current, archived
    var id: String { rawValue }
    var states: [NovaKatipState] {
        switch self {
        case .expired: return [.expired]
        case .expiring: return [.expiring]
        case .current: return [.upcoming, .active]
        case .archived: return [.archived]
        }
    }
    var title: String {
        switch self {
        case .expired: return RDLocalization.string("localizable.nova.katip.group.expired", table: .localizable, fallback: "Süresi doldu")
        case .expiring: return RDLocalization.string("localizable.nova.katip.group.expiring", table: .localizable, fallback: "Bitiyor")
        case .current: return RDLocalization.string("localizable.nova.katip.group.current", table: .localizable, fallback: "Yürürlükte")
        case .archived: return RDLocalization.string("localizable.nova.katip.group.archived", table: .localizable, fallback: "Arşiv")
        }
    }
    var footer: String {
        switch self {
        case .expired: return RDLocalization.string("localizable.nova.katip.group.expired.footer", table: .localizable, fallback: "tarih geçti")
        case .expiring: return RDLocalization.string("localizable.nova.katip.group.expiring.footer", table: .localizable, fallback: "yaklaşan")
        case .current: return RDLocalization.string("localizable.nova.katip.group.current.footer", table: .localizable, fallback: "sürüyor")
        case .archived: return RDLocalization.string("localizable.nova.katip.group.archived.footer", table: .localizable, fallback: "kapatıldı")
        }
    }
    var symbol: String {
        switch self {
        case .expired: return "exclamationmark.triangle"
        case .expiring: return "clock"
        case .current: return "doc.text"
        case .archived: return "archivebox"
        }
    }
    static func of(_ state: NovaKatipState) -> NovaKatipGroup {
        allCases.first { $0.states.contains(state) } ?? .current
    }
}

/// Whether the contract has an end at all. The schema derives it, so an open
/// ended contract is never shown as a fixed term one whose date is missing.
enum NovaKatipTerm: String, Equatable {
    case openEnded = "open_ended"
    case fixedTerm = "fixed_term"
    var title: String {
        switch self {
        case .openEnded: return RDLocalization.string("localizable.nova.katip.term.open", table: .localizable, fallback: "Süresiz")
        case .fixedTerm: return RDLocalization.string("localizable.nova.katip.term.fixed", table: .localizable, fallback: "Süreli")
        }
    }
}

/// One contract as the board sees it.
struct NovaKatipContract: Identifiable, Equatable {
    let id: UUID
    let companyID: UUID?
    let companyName: String?
    let workplaceID: UUID?
    let workplaceName: String?
    let counterparty: String
    let expertContact: String
    let scope: String
    let startsOn: String
    let endsBefore: String?
    let term: NovaKatipTerm
    let state: NovaKatipState
    let group: NovaKatipGroup
    let noticeDays: Int
    /// What the contract itself declares. Never a measurement, never compared
    /// to a requirement.
    let declaredMonthlyMinutes: Int?
    let declaredNote: String?
    /// No approved catalogue says how much service time is required.
    let requiredServiceTimeKnown: Bool
    let contractStored: Bool
    let contractLocation: String?
    /// The column can only ever be false.
    let officialIntegration: Bool
    let officialSubmissionMade: Bool
    var fileEntryID: UUID? = nil
    var documentVersion: Int64 = 0
    var documentTitle: String? = nil
}

struct NovaKatipCatalogue: Equatable {
    struct Workplace: Identifiable, Equatable { let id: UUID; let name: String }
    let workplaces: [Workplace]
    let noticeDays: Int
    let officialIntegration: Bool
    let officialStatusChecked: Bool
    let credentialCollection: Bool
    let requiredServiceTimeKnown: Bool
    let contractStorageAvailable: Bool
}

struct NovaKatipBoard: Equatable {
    struct CompanyTally: Identifiable, Equatable {
        let id: UUID
        let name: String
        let total: Int
        let counts: [String: Int]
    }
    let rows: [NovaKatipContract]
    let counts: [String: Int]
    let companies: [CompanyTally]
    let total: Int
    let hasMore: Bool
    let offset: Int
    let noticeDays: Int
    func count(_ group: NovaKatipGroup) -> Int {
        group.states.reduce(0) { $0 + (counts[$1.rawValue] ?? 0) }
    }
    var needsAttention: Int { count(.expired) + count(.expiring) }
}

struct NovaKatipQuery: Equatable {
    var company: UUID?
    var state: String?
    var workplace: UUID?
    var search: String = ""
    var limit: Int = 10
    var offset: Int = 0
}

/// What the expert fills in to record a contract.
struct NovaKatipDraft: Equatable {
    var workplaceID: UUID?
    var counterparty: String = ""
    var expertContact: String = ""
    var scope: String = ""
    var startsOn: String = ""
    var endsBefore: String = ""
    var declaredMonthlyMinutes: String = ""
    var declaredNote: String = ""
    var contractLocation: String = ""
}

/// What the expert fills in to end one, or to correct that date.
struct NovaKatipEndDraft: Equatable {
    var contractID: UUID?
    var counterparty: String = ""
    var startsOn: String = ""
    var endsBefore: String = ""
    var isCorrection: Bool = false
}

enum NovaKatipFailure: Error, Equatable {
    case denied, planRequired, featureUnavailable, moduleUnavailable, validation, conflict
    case endsBeforeStart, archived
    case unavailable
    var message: String {
        switch self {
        case .denied: return RDLocalization.string("localizable.nova.katip.error.denied", table: .localizable,
            fallback: "Bu kayda erişim yok.")
        case .planRequired: return RDLocalization.string("localizable.nova.katip.error.plan", table: .localizable,
            fallback: "Bu işlem için Plus veya Pro aboneliği gerekiyor.")
        case .featureUnavailable: return RDLocalization.string("localizable.nova.katip.error.feature", table: .localizable,
            fallback: "Modüller henüz açık değil.")
        case .moduleUnavailable: return RDLocalization.string("localizable.nova.katip.error.module", table: .localizable,
            fallback: "İSG-KATİP sözleşme modülü henüz açık değil.")
        case .validation: return RDLocalization.string("localizable.nova.katip.error.validation", table: .localizable,
            fallback: "Girilen bilgiler eksik veya birbiriyle uyumsuz.")
        case .conflict: return RDLocalization.string("localizable.nova.katip.error.conflict", table: .localizable,
            fallback: "Kayıt bu sırada başka bir yerden değişti. Yenileyip tekrar deneyin.")
        case .endsBeforeStart: return RDLocalization.string("localizable.nova.katip.error.ends", table: .localizable,
            fallback: "Bitiş tarihi başlangıçtan önce olamaz.")
        case .archived: return RDLocalization.string("localizable.nova.katip.error.archived", table: .localizable,
            fallback: "Arşivlenmiş sözleşmenin tarihleri değiştirilemez.")
        case .unavailable: return RDLocalization.string("localizable.nova.katip.error.unavailable", table: .localizable,
            fallback: "Kayıt alınamadı. Bağlantıyı kontrol edip tekrar deneyin.")
        }
    }
}

enum NovaKatipWords {
    /// Declared minutes, shown the way a person would say them.
    static func service(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if rest == 0 {
            return String(format: RDLocalization.string("localizable.nova.katip.service.hours",
                table: .localizable, fallback: "ayda %d saat"), hours)
        }
        return String(format: RDLocalization.string("localizable.nova.katip.service.hoursminutes",
            table: .localizable, fallback: "ayda %d saat %d dakika"), hours, rest)
    }
    /// Why the row reads the way it does. Every state has a reason.
    static func explain(_ entry: NovaKatipContract) -> String {
        switch entry.state {
        case .upcoming: return String(format: RDLocalization.string("localizable.nova.katip.explain.upcoming",
            table: .localizable, fallback: "%@ tarihinde başlayacak."), entry.startsOn)
        case .active: return entry.term == .openEnded
            ? RDLocalization.string("localizable.nova.katip.explain.open", table: .localizable,
                fallback: "Süresiz sözleşme; bitiş tarihi yok.")
            : String(format: RDLocalization.string("localizable.nova.katip.explain.active",
                table: .localizable, fallback: "%@ tarihine kadar yürürlükte."), entry.endsBefore ?? "")
        case .expiring: return String(format: RDLocalization.string("localizable.nova.katip.explain.expiring",
            table: .localizable, fallback: "%@ tarihinde bitiyor."), entry.endsBefore ?? "")
        case .expired: return String(format: RDLocalization.string("localizable.nova.katip.explain.expired",
            table: .localizable, fallback: "%@ tarihinde sona erdi."), entry.endsBefore ?? "")
        case .archived: return RDLocalization.string("localizable.nova.katip.explain.archived", table: .localizable,
            fallback: "Bu sözleşme arşivlendi.")
        }
    }
    /// The sentence the screen carries at the top and again on every record.
    static let noIntegrationNote = RDLocalization.string("localizable.nova.katip.integration.note",
        table: .localizable,
        fallback: "Uygulama İSG-KATİP üzerinde işlem yapmaz, sorgu çekmez ve şifre istemez. Burası yalnız sizin kendi sözleşme kaydınızdır.")
    /// The sentence beside the declared service time.
    static let declaredNote = RDLocalization.string("localizable.nova.katip.declared.note", table: .localizable,
        fallback: "Bu süre sözleşmenin beyanıdır. Ürün gereken süreyi bilmez ve yeterli olup olmadığını söylemez.")
    /// The sentence beside the document location.
    static let documentNote = RDLocalization.string("localizable.nova.katip.document.note", table: .localizable,
        fallback: "Sözleşme belgesi uygulamada saklanmaz. Burada yalnız aslının nerede tutulduğunu not edersiniz.")
}
