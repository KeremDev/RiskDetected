import Foundation

/// What kind of record a notice came from. The server names the kind; the
/// client owns every word shown for it, so no Turkish copy lives in SQL.
enum NovaNoticeKind: String, CaseIterable, Identifiable, Equatable {
    case katipContract = "katip_contract"
    case appointment
    case emergencyPlan = "emergency_plan"
    case drill
    case annualWorkItem = "annual_work_item"
    case board
    case boardDecision = "board_decision"
    case riskAssessment = "risk_assessment"
    case equipment
    case document
    var id: String { rawValue }
    var title: String {
        switch self {
        case .katipContract: return RDLocalization.string("localizable.nova.notice.kind.katip", table: .localizable, fallback: "İSG-KATİP sözleşmesi")
        case .appointment: return RDLocalization.string("localizable.nova.notice.kind.appointment", table: .localizable, fallback: "Atama")
        case .emergencyPlan: return RDLocalization.string("localizable.nova.notice.kind.emergency", table: .localizable, fallback: "Acil durum planı")
        case .drill: return RDLocalization.string("localizable.nova.notice.kind.drill", table: .localizable, fallback: "Tatbikat")
        case .annualWorkItem: return RDLocalization.string("localizable.nova.notice.kind.annual", table: .localizable, fallback: "Yıllık plan işi")
        case .board: return RDLocalization.string("localizable.nova.notice.kind.board", table: .localizable, fallback: "Kurul toplantısı")
        case .boardDecision: return RDLocalization.string("localizable.nova.notice.kind.decision", table: .localizable, fallback: "Kurul kararı")
        case .riskAssessment: return RDLocalization.string("localizable.nova.notice.kind.risk", table: .localizable, fallback: "Risk değerlendirmesi")
        case .equipment: return RDLocalization.string("localizable.nova.notice.kind.equipment", table: .localizable, fallback: "Periyodik kontrol")
        case .document: return RDLocalization.string("localizable.nova.notice.kind.document", table: .localizable, fallback: "Evrak")
        }
    }
    var symbol: String {
        switch self {
        case .katipContract: return "doc.text.magnifyingglass"
        case .appointment: return "person.badge.shield.checkmark"
        case .emergencyPlan: return "light.beacon.max"
        case .drill: return "figure.run"
        case .annualWorkItem: return "calendar"
        case .board: return "person.3"
        case .boardDecision: return "checkmark.seal"
        case .riskAssessment: return "shield.lefthalf.filled"
        case .equipment: return "checkmark.shield"
        case .document: return "doc.text"
        }
    }
}

/// How late the situation is. The server computes it from the record's own
/// date; the client never re-decides it.
enum NovaNoticeSeverity: String, Equatable {
    case overdue, soon
    var status: NovaStatus { self == .overdue ? .danger : .warning }
    var tone: NovaColorToken { self == .overdue ? .statusDangerInk : .statusWarningInk }
}

/// One situation that is due. Nothing here is stored server side: the row is
/// rebuilt from the record every time the bell is opened.
struct NovaNoticeEntry: Identifiable, Equatable {
    let key: String
    let kind: NovaNoticeKind
    let destination: NovaDestination
    let companyID: UUID?
    let companyName: String?
    let recordID: UUID?
    let title: String
    let dueOn: String
    let days: Int
    let severity: NovaNoticeSeverity
    let unread: Bool
    let dismissed: Bool
    var id: String { key }
}

struct NovaNoticeFeed: Equatable {
    let rows: [NovaNoticeEntry]
    let unread: Int
    let overdue: Int
    let total: Int
    let dismissed: Int
    let hasMore: Bool
    /// The two sentences this feature is built around, carried on every answer
    /// so the client can never drift from them.
    let pushDeliveryClaimed: Bool
    let dismissIsPermanent: Bool
    static let empty = NovaNoticeFeed(rows: [], unread: 0, overdue: 0, total: 0, dismissed: 0,
                                      hasMore: false, pushDeliveryClaimed: false,
                                      dismissIsPermanent: false)
}

enum NovaNoticeScope: String, CaseIterable, Identifiable {
    case active, unread, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .active: return RDLocalization.string("localizable.nova.notice.scope.active", table: .localizable, fallback: "Açık")
        case .unread: return RDLocalization.string("localizable.nova.notice.scope.unread", table: .localizable, fallback: "Okunmamış")
        case .all: return RDLocalization.string("localizable.nova.notice.scope.all", table: .localizable, fallback: "Gizlenenler dahil")
        }
    }
}

enum NovaNoticeFailure: Error, Equatable {
    case denied, featureUnavailable, validation, notFound, unavailable
    var message: String {
        switch self {
        case .denied: return RDLocalization.string("localizable.nova.notice.error.denied", table: .localizable,
            fallback: "Bu bildirimlere erişim yok.")
        case .featureUnavailable: return RDLocalization.string("localizable.nova.notice.error.feature", table: .localizable,
            fallback: "Bildirimler henüz açık değil.")
        case .validation: return RDLocalization.string("localizable.nova.notice.error.validation", table: .localizable,
            fallback: "İstek geçersiz.")
        case .notFound: return RDLocalization.string("localizable.nova.notice.error.gone", table: .localizable,
            fallback: "Bu bildirim artık geçerli değil. Liste yenilendi.")
        case .unavailable: return RDLocalization.string("localizable.nova.notice.error.unavailable", table: .localizable,
            fallback: "Bildirimler alınamadı. Bağlantıyı kontrol edip tekrar deneyin.")
        }
    }
}

enum NovaNoticeWords {
    /// Why the row is on the list. Overdue and upcoming read differently on
    /// purpose; neither invents a date.
    static func explain(_ entry: NovaNoticeEntry) -> String {
        switch entry.severity {
        case .overdue:
            return String(format: RDLocalization.string("localizable.nova.notice.explain.overdue",
                table: .localizable, fallback: "%1$@ tarihini %2$d gün geçti."), entry.dueOn, -entry.days)
        case .soon:
            if entry.days == 0 {
                return String(format: RDLocalization.string("localizable.nova.notice.explain.today",
                    table: .localizable, fallback: "Bugün: %@."), entry.dueOn)
            }
            return String(format: RDLocalization.string("localizable.nova.notice.explain.soon",
                table: .localizable, fallback: "%1$@ tarihine %2$d gün kaldı."), entry.dueOn, entry.days)
        }
    }
    /// Said wherever the list can be emptied, because deleting here deletes
    /// nothing else.
    static let dismissNote = RDLocalization.string("localizable.nova.notice.dismiss.note", table: .localizable,
        fallback: "Silmek bildirimi listeden kaldırır; kaydı silmez. Tarih değişirse bildirim yeniden görünür.")
    /// Said in the notification centre, because this list is not the push list.
    static let noPushNote = RDLocalization.string("localizable.nova.notice.push.note", table: .localizable,
        fallback: "Bu liste kayıtlarınızın tarihlerinden hesaplanır. Telefon bildirimi gönderildiğini ya da okunduğunu göstermez.")
}
