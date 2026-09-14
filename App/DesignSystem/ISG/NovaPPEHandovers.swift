import Foundation

/// What a handover says about itself. The value is always the server's: it is
/// counted from the returns at read time, so nothing on this side adds up
/// quantities of its own.
///
/// There is no group layer here on purpose: every state is already its own
/// counter, so grouping would only restate them.
enum NovaPPEState: String, CaseIterable, Identifiable, Equatable {
    case outstanding, partial, closed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .outstanding: return RDLocalization.string("localizable.nova.ppe.state.outstanding", table: .localizable, fallback: "Zimmette")
        case .partial: return RDLocalization.string("localizable.nova.ppe.state.partial", table: .localizable, fallback: "Kısmen iade")
        case .closed: return RDLocalization.string("localizable.nova.ppe.state.closed", table: .localizable, fallback: "Kapandı")
        }
    }
    var footer: String {
        switch self {
        case .outstanding: return RDLocalization.string("localizable.nova.ppe.state.outstanding.footer", table: .localizable, fallback: "hiç iade yok")
        case .partial: return RDLocalization.string("localizable.nova.ppe.state.partial.footer", table: .localizable, fallback: "bir kısmı dönmedi")
        case .closed: return RDLocalization.string("localizable.nova.ppe.state.closed.footer", table: .localizable, fallback: "tamamı iade")
        }
    }
    var symbol: String {
        switch self {
        case .outstanding: return "shippingbox"
        case .partial: return "arrow.uturn.backward"
        case .closed: return "checkmark.circle"
        }
    }
}

/// The units the server accepts. Offered as they are, so the client can never
/// send one the server would refuse.
enum NovaPPEUnit: String, CaseIterable, Identifiable, Equatable {
    case piece, pair, set, metre, litre
    var id: String { rawValue }
    var title: String {
        switch self {
        case .piece: return RDLocalization.string("localizable.nova.ppe.unit.piece", table: .localizable, fallback: "Adet")
        case .pair: return RDLocalization.string("localizable.nova.ppe.unit.pair", table: .localizable, fallback: "Çift")
        case .set: return RDLocalization.string("localizable.nova.ppe.unit.set", table: .localizable, fallback: "Takım")
        case .metre: return RDLocalization.string("localizable.nova.ppe.unit.metre", table: .localizable, fallback: "Metre")
        case .litre: return RDLocalization.string("localizable.nova.ppe.unit.litre", table: .localizable, fallback: "Litre")
        }
    }
}

/// What state a returned item came back in.
enum NovaPPECondition: String, CaseIterable, Identifiable, Equatable {
    case reusable, worn, damaged, lost
    var id: String { rawValue }
    var title: String {
        switch self {
        case .reusable: return RDLocalization.string("localizable.nova.ppe.condition.reusable", table: .localizable, fallback: "Kullanılabilir")
        case .worn: return RDLocalization.string("localizable.nova.ppe.condition.worn", table: .localizable, fallback: "Yıpranmış")
        case .damaged: return RDLocalization.string("localizable.nova.ppe.condition.damaged", table: .localizable, fallback: "Hasarlı")
        case .lost: return RDLocalization.string("localizable.nova.ppe.condition.lost", table: .localizable, fallback: "Kayıp")
        }
    }
    var symbol: String {
        switch self {
        case .reusable: return "checkmark.circle"
        case .worn: return "exclamationmark.circle"
        case .damaged: return "xmark.octagon"
        case .lost: return "questionmark.circle"
        }
    }
}

/// One return filed against a handover.
struct NovaPPEReturn: Identifiable, Equatable {
    let id: UUID
    let quantity: Double
    let returnedOn: String
    let condition: NovaPPECondition
    let note: String?
}

/// One handover, with what came back against it.
struct NovaPPEHandover: Identifiable, Equatable {
    let id: UUID
    let companyID: UUID?
    let companyName: String?
    let employeeID: UUID?
    let employeeName: String?
    let employeeArchived: Bool
    let item: String
    let quantity: Double
    let unit: NovaPPEUnit
    let handedOn: String
    let externalRef: String?
    let state: NovaPPEState
    /// Counted from the returns at read time, never stored.
    let returnedQuantity: Double
    let outstanding: Double
    let lostQuantity: Double
    /// The product holds no file, so this is always false. What is kept is the
    /// expert's own note of where the signed form is.
    let signedCopyStored: Bool
    let signedCopyLocation: String?
    let returns: [NovaPPEReturn]
}

struct NovaPPECatalogue: Equatable {
    struct Employee: Identifiable, Equatable { let id: UUID; let fullName: String }
    let employees: [Employee]
    let units: [NovaPPEUnit]
    let conditions: [NovaPPECondition]
    /// No fixed equipment list ships: naming one would read as a statement of
    /// what the law requires, and no such list has been approved.
    let itemCatalogueOffered: Bool
    let signedCopyStorageAvailable: Bool
}

struct NovaPPEBoard: Equatable {
    struct CompanyTally: Identifiable, Equatable {
        let id: UUID
        let name: String
        let total: Int
        let counts: [String: Int]
    }
    let rows: [NovaPPEHandover]
    let counts: [String: Int]
    let companies: [CompanyTally]
    let total: Int
    let hasMore: Bool
    let offset: Int
    func count(_ state: NovaPPEState) -> Int { counts[state.rawValue] ?? 0 }
    var needsAttention: Int { count(.outstanding) + count(.partial) }
}

struct NovaPPEQuery: Equatable {
    var company: UUID?
    var state: String?
    var employee: UUID?
    var search: String = ""
    var limit: Int = 10
    var offset: Int = 0
}

/// What the expert fills in to record a handover.
struct NovaPPEHandoverDraft: Equatable {
    var employeeID: UUID?
    var item: String = ""
    var quantity: String = "1"
    var unit: NovaPPEUnit = .piece
    var handedOn: String = ""
    var externalRef: String = ""
    /// Where the signed form is kept. The product holds no file.
    var signedCopyLocation: String = ""
}

/// What the expert fills in to record a return.
struct NovaPPEReturnDraft: Equatable {
    var handoverID: UUID?
    var item: String = ""
    var outstanding: Double = 0
    var unit: NovaPPEUnit = .piece
    var quantity: String = ""
    var returnedOn: String = ""
    var condition: NovaPPECondition = .reusable
    var note: String = ""
}

enum NovaPPEFailure: Error, Equatable {
    case denied, planRequired, featureUnavailable, moduleUnavailable, validation, conflict
    case handedInFuture, returnedInFuture, returnBeforeHandover, returnExceedsHandover
    case unavailable
    var message: String {
        switch self {
        case .denied: return RDLocalization.string("localizable.nova.ppe.error.denied", table: .localizable,
            fallback: "Bu kayda erişim yok.")
        case .planRequired: return RDLocalization.string("localizable.nova.ppe.error.plan", table: .localizable,
            fallback: "Bu işlem için Plus veya Pro aboneliği gerekiyor.")
        case .featureUnavailable: return RDLocalization.string("localizable.nova.ppe.error.feature", table: .localizable,
            fallback: "Modüller henüz açık değil.")
        case .moduleUnavailable: return RDLocalization.string("localizable.nova.ppe.error.module", table: .localizable,
            fallback: "KKD zimmet modülü henüz açık değil.")
        case .validation: return RDLocalization.string("localizable.nova.ppe.error.validation", table: .localizable,
            fallback: "Girilen bilgiler eksik veya birbiriyle uyumsuz.")
        case .conflict: return RDLocalization.string("localizable.nova.ppe.error.conflict", table: .localizable,
            fallback: "Kayıt bu sırada başka bir yerden değişti. Yenileyip tekrar deneyin.")
        case .handedInFuture: return RDLocalization.string("localizable.nova.ppe.error.handed", table: .localizable,
            fallback: "Zimmet tarihi bugünden ileri olamaz.")
        case .returnedInFuture: return RDLocalization.string("localizable.nova.ppe.error.returned", table: .localizable,
            fallback: "İade tarihi bugünden ileri olamaz.")
        case .returnBeforeHandover: return RDLocalization.string("localizable.nova.ppe.error.before", table: .localizable,
            fallback: "İade tarihi zimmet tarihinden önce olamaz.")
        case .returnExceedsHandover: return RDLocalization.string("localizable.nova.ppe.error.exceeds", table: .localizable,
            fallback: "İade miktarı zimmetten fazla olamaz.")
        case .unavailable: return RDLocalization.string("localizable.nova.ppe.error.unavailable", table: .localizable,
            fallback: "Kayıt alınamadı. Bağlantıyı kontrol edip tekrar deneyin.")
        }
    }
}

enum NovaPPEWords {
    /// Quantities come back as decimals; a whole number is shown as one.
    static func amount(_ value: Double, _ unit: NovaPPEUnit) -> String {
        let rounded = (value * 1000).rounded() / 1000
        let text = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.3f", rounded).replacingOccurrences(of: ".", with: ",")
        return text + " " + unit.title
    }
    /// Why the row reads the way it does. Every state has a reason.
    static func explain(_ handover: NovaPPEHandover) -> String {
        switch handover.state {
        case .outstanding: return String(format: RDLocalization.string("localizable.nova.ppe.explain.outstanding",
            table: .localizable, fallback: "%@ hâlâ zimmette."),
            amount(handover.outstanding, handover.unit))
        case .partial: return String(format: RDLocalization.string("localizable.nova.ppe.explain.partial",
            table: .localizable, fallback: "%@ iade edildi, %@ hâlâ zimmette."),
            amount(handover.returnedQuantity, handover.unit), amount(handover.outstanding, handover.unit))
        case .closed: return RDLocalization.string("localizable.nova.ppe.explain.closed", table: .localizable,
            fallback: "Tamamı iade edildi.")
        }
    }
    /// The sentence the screen carries wherever the signed form is mentioned.
    static let signedCopyNote = RDLocalization.string("localizable.nova.ppe.signed.note", table: .localizable,
        fallback: "İmzalı zimmet formu uygulamada saklanmaz. Burada yalnız aslının nerede tutulduğunu not edersiniz.")
    /// The sentence the item field carries.
    static let noCatalogueNote = RDLocalization.string("localizable.nova.ppe.catalogue.note", table: .localizable,
        fallback: "Ürün hazır KKD listesi göndermez; ekipmanı siz adlandırırsınız.")
}
