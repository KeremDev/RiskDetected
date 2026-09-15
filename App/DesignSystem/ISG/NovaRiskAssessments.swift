import Foundation

/// What the record says about one workplace today. The value is always the
/// server's: it is worked out at read time from the finalised document's own
/// dates, so nothing on this side recomputes or overrides one.
///
/// `periodUnknown` is its own answer on purpose. A finalised document with no
/// period behind it is a gap in the record, never a statement that the
/// workplace is covered for another year.
enum NovaRiskState: String, CaseIterable, Identifiable, Equatable {
    case neverAssessed = "never_assessed"
    case periodUnknown = "period_unknown"
    case expired
    case dueSoon = "due_soon"
    case valid
    var id: String { rawValue }
}

/// The counters the page shows. Four groups over five states, every state in
/// exactly one group, and the same words are filter values the server accepts —
/// so tapping a counter narrows to exactly the rows that counter counted.
enum NovaRiskGroup: String, CaseIterable, Identifiable {
    case expired, untracked, current
    case dueSoon = "due_soon"
    var id: String { rawValue }

    var states: [NovaRiskState] {
        switch self {
        case .expired: return [.expired]
        case .untracked: return [.neverAssessed, .periodUnknown]
        case .dueSoon: return [.dueSoon]
        case .current: return [.valid]
        }
    }
    var title: String {
        switch self {
        case .expired: return RDLocalization.string("localizable.nova.risk.group.expired", table: .localizable, fallback: "Süresi doldu")
        case .untracked: return RDLocalization.string("localizable.nova.risk.group.untracked", table: .localizable, fallback: "Takipsiz")
        case .dueSoon: return RDLocalization.string("localizable.nova.risk.group.due", table: .localizable, fallback: "Yaklaşıyor")
        case .current: return RDLocalization.string("localizable.nova.risk.group.current", table: .localizable, fallback: "Güncel")
        }
    }
    /// A finding about the count, never an instruction.
    var footer: String {
        switch self {
        case .expired: return RDLocalization.string("localizable.nova.risk.group.expired.footer", table: .localizable, fallback: "tarih geçti")
        case .untracked: return RDLocalization.string("localizable.nova.risk.group.untracked.footer", table: .localizable, fallback: "belge yok")
        case .dueSoon: return RDLocalization.string("localizable.nova.risk.group.due.footer", table: .localizable, fallback: "yaklaşan")
        case .current: return RDLocalization.string("localizable.nova.risk.group.current.footer", table: .localizable, fallback: "yürürlükte")
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
    static func of(_ state: NovaRiskState) -> NovaRiskGroup {
        allCases.first { $0.states.contains(state) } ?? .untracked
    }
}

/// The four revision kinds, each with its own date rule. The rules live on the
/// server; these are the names and what the expert is told about each.
enum NovaRiskKind: String, CaseIterable, Identifiable, Equatable {
    case full, partial, metadata, rescan
    var id: String { rawValue }
    var title: String {
        switch self {
        case .full: return RDLocalization.string("localizable.nova.risk.kind.full", table: .localizable, fallback: "Tam yenileme")
        case .partial: return RDLocalization.string("localizable.nova.risk.kind.partial", table: .localizable, fallback: "Kısmi revizyon")
        case .metadata: return RDLocalization.string("localizable.nova.risk.kind.metadata", table: .localizable, fallback: "Bilgi düzeltmesi")
        case .rescan: return RDLocalization.string("localizable.nova.risk.kind.rescan", table: .localizable, fallback: "Yeniden tarama")
        }
    }
    /// What this kind does to the dates, said plainly before it is chosen.
    var explain: String {
        switch self {
        case .full: return RDLocalization.string("localizable.nova.risk.kind.full.explain", table: .localizable,
            fallback: "Yeni bir değerlendirme tarihi taşır ve süreyi yeniden başlatır.")
        case .partial: return RDLocalization.string("localizable.nova.risk.kind.partial.explain", table: .localizable,
            fallback: "Belirli bölümleri günceller. Değerlendirme tarihini ve süreyi değiştirmez.")
        case .metadata: return RDLocalization.string("localizable.nova.risk.kind.metadata.explain", table: .localizable,
            fallback: "Yanlış yazılmış bilgiyi düzeltir. Değerlendirme tarihini ve süreyi değiştirmez.")
        case .rescan: return RDLocalization.string("localizable.nova.risk.kind.rescan.explain", table: .localizable,
            fallback: "Aynı belgenin daha iyi bir kopyasını ekler. Yenileme sayılmaz.")
        }
    }
    /// Only a full renewal carries a date of its own; the server refuses one on
    /// the others, so the form does not offer it.
    var carriesAssessmentDate: Bool { self == .full }
    /// The server demands a reason for anything that is not a renewal or a scan.
    var needsReason: Bool { self == .partial || self == .metadata }
    var needsScope: Bool { self == .partial }
}

/// Where a finalised version's period came from. The product never calls a
/// period a legal requirement unless a published rule produced it.
enum NovaRiskPeriodSource: String, Equatable {
    case ruleVersion = "rule_version"
    case unapprovedFixture = "unapproved_fixture"
    case hazardClass = "hazard_class"
    var title: String {
        switch self {
        case .ruleVersion: return RDLocalization.string("localizable.nova.risk.period.rule", table: .localizable, fallback: "Yayımlanmış kural")
        case .unapprovedFixture: return RDLocalization.string("localizable.nova.risk.period.expert", table: .localizable, fallback: "Uzman tarafından belirlenen")
        case .hazardClass: return RDLocalization.string("localizable.nova.risk.period.hazard", table: .localizable, fallback: "Tehlike sınıfına göre otomatik")
        }
    }
    var needsReview: Bool { self == .unapprovedFixture }
}

/// One source finding the expert carried over from a photo analysis. Carrying
/// one writes nothing back to the analysis.
struct NovaRiskSource: Identifiable, Equatable {
    let id: UUID
    let analysisID: UUID
    let findingID: UUID
    let sourceVersion: Int
    let selectedAt: Date?
}

/// One consequence the expert recorded for a scoped revision.
struct NovaRiskImpact: Identifiable, Equatable {
    let id: UUID
    let targetKind: String
    let targetRef: String
    let action: String
    let note: String?
    var actionTitle: String {
        switch action {
        case "review": return RDLocalization.string("localizable.nova.risk.impact.review", table: .localizable, fallback: "Gözden geçirilecek")
        case "reschedule": return RDLocalization.string("localizable.nova.risk.impact.reschedule", table: .localizable, fallback: "Yeniden planlanacak")
        default: return RDLocalization.string("localizable.nova.risk.impact.none", table: .localizable, fallback: "Değişiklik yok")
        }
    }
}

/// One version in the history. A finalised one is never edited.
struct NovaRiskVersion: Identifiable, Equatable {
    var id: Int { version }
    let version: Int
    let kind: NovaRiskKind
    let previousVersion: Int?
    let assessmentOn: String
    let revisionOn: String?
    let scope: [String]
    let reason: String?
    let state: String
    let finalizedAt: Date?
    let periodYears: Int?
    let periodSource: NovaRiskPeriodSource?
    let periodNeedsReview: Bool
    let dateNeedsReview: Bool
    let validUntil: String?
    let sourceDrift: Bool
    let driftNote: String?
    let fileAssetID: UUID?
    let sources: [NovaRiskSource]
    let impacts: [NovaRiskImpact]
    var editRevision: Int = 0
    var cancellationNote: String?
    var isDraft: Bool { state == "draft" }
    var isFinal: Bool { state == "final" }
}

/// One workplace's risk assessment as the board sees it.
struct NovaRiskRow: Identifiable, Equatable {
    let id: UUID
    let companyID: UUID?
    let companyName: String?
    let workplaceID: UUID?
    let workplaceName: String?
    let currentVersion: Int
    let baseAssessmentOn: String?
    let validUntil: String?
    let state: NovaRiskState
    let group: NovaRiskGroup
    let noticeDays: Int
    let currentKind: NovaRiskKind?
    let currentAssessmentOn: String?
    let currentRevisionOn: String?
    let periodYears: Int?
    let periodSource: NovaRiskPeriodSource?
    let periodNeedsReview: Bool?
    let dateNeedsReview: Bool
    let sourceDrift: Bool
    let driftNote: String?
    /// The workplace's own hazard class (az/tehlikeli/çok tehlikeli) and the
    /// legal renewal period it implies, so the finalize step can offer that
    /// number before the expert ever types one.
    let workplaceHazardClass: String?
    let workplaceSuggestedPeriodYears: Int?
    let hasOpenDraft: Bool
    let draftVersion: Int?
    let draftKind: NovaRiskKind?
    let draftAssessmentOn: String?
    let draftReason: String?
    let sourceLinkCount: Int
    let versions: [NovaRiskVersion]
}

/// What the client may offer, and what it must say about it.
struct NovaRiskCatalogue: Equatable {
    struct Workplace: Identifiable, Equatable { let id: UUID; let name: String; let needsReview: Bool }
    struct Rule: Identifiable, Equatable {
        var id: String { ruleCode }
        let ruleCode: String
        let periodKind: String
        let periodLength: Int?
    }
    let workplaces: [Workplace]
    /// Empty while no rule set has been approved. The form then has only the
    /// expert's own number, and says so.
    let rules: [Rule]
    let noticeDays: Int
    let expertPeriodNeedsReview: Bool
}

/// The whole board in one read.
struct NovaRiskBoard: Equatable {
    struct CompanyTally: Identifiable, Equatable {
        let id: UUID
        let name: String
        let total: Int
        let counts: [String: Int]
    }
    let rows: [NovaRiskRow]
    let counts: [String: Int]
    let companies: [CompanyTally]
    let total: Int
    let hasMore: Bool
    let offset: Int
    let noticeDays: Int
    func count(_ group: NovaRiskGroup) -> Int {
        group.states.reduce(0) { $0 + (counts[$1.rawValue] ?? 0) }
    }
    var needsAttention: Int { count(.expired) + count(.dueSoon) + count(.untracked) }
}

struct NovaRiskQuery: Equatable {
    var company: UUID?
    var state: String?
    var workplace: UUID?
    var search: String = ""
    var limit: Int = 10
    var offset: Int = 0
}

/// What the expert fills in to open a new version.
struct NovaRiskVersionDraft: Equatable {
    var assessmentID: UUID?
    var kind: NovaRiskKind = .full
    var assessmentOn: String = ""
    var revisionOn: String = ""
    var scope: [String] = []
    var reason: String = ""
    var expectedCurrent: Int = 0
    var versionToEdit: Int?
    var editRevision: Int = 0
}

/// What the expert confirms to make a version the document that stands.
struct NovaRiskFinalizeDraft: Equatable {
    var assessmentID: UUID?
    var version: Int = 0
    var expectedCurrent: Int = 0
    /// Empty means the expert's own number below is used, and it is stored and
    /// shown as the expert's.
    var ruleCode: String = ""
    var periodYears: String = ""
    var kind: NovaRiskKind = .full
    var editRevision: Int = 0
    /// The years the workplace's own hazard class implies, shown as a hint;
    /// nil when the workplace has no hazard class on file yet.
    var suggestedYears: Int?
}

enum NovaRiskFailure: Error, Equatable {
    case denied, planRequired, moduleUnavailable, validation, conflict
    case dateInFuture, dateImmutable, draftOpen, versionFinalized, ruleNeedsReview
    case unavailable
    var message: String {
        switch self {
        case .denied: return RDLocalization.string("localizable.nova.risk.error.denied", table: .localizable,
            fallback: "Bu kayda erişim yok.")
        case .planRequired: return RDLocalization.string("localizable.nova.risk.error.plan", table: .localizable,
            fallback: "Bu işlem için Plus veya Pro aboneliği gerekiyor.")
        case .moduleUnavailable: return RDLocalization.string("localizable.nova.risk.error.module", table: .localizable,
            fallback: "Risk değerlendirmesi modülü henüz açık değil.")
        case .validation: return RDLocalization.string("localizable.nova.risk.error.validation", table: .localizable,
            fallback: "Girilen bilgiler eksik veya birbiriyle uyumsuz.")
        case .conflict: return RDLocalization.string("localizable.nova.risk.error.conflict", table: .localizable,
            fallback: "Kayıt bu sırada başka bir yerden değişti. Yenileyip tekrar deneyin.")
        case .dateInFuture: return RDLocalization.string("localizable.nova.risk.error.future", table: .localizable,
            fallback: "Değerlendirme tarihi bugünden ileri olamaz.")
        case .dateImmutable: return RDLocalization.string("localizable.nova.risk.error.immutable", table: .localizable,
            fallback: "Değerlendirme tarihi yalnızca tam yenilemede değişir.")
        case .draftOpen: return RDLocalization.string("localizable.nova.risk.error.draft", table: .localizable,
            fallback: "Bu değerlendirmede zaten açık bir taslak var. Önce onu tamamlayın.")
        case .versionFinalized: return RDLocalization.string("localizable.nova.risk.error.finalized", table: .localizable,
            fallback: "Tamamlanmış sürüm değiştirilemez.")
        case .ruleNeedsReview: return RDLocalization.string("localizable.nova.risk.error.rule", table: .localizable,
            fallback: "Seçilen kural yayımlanmış değil. Süreyi kendiniz belirleyebilirsiniz.")
        case .unavailable: return RDLocalization.string("localizable.nova.risk.error.unavailable", table: .localizable,
            fallback: "Kayıt alınamadı. Bağlantıyı kontrol edip tekrar deneyin.")
        }
    }
}

/// The words the screens use, in one place so the same state never gets two
/// names on two surfaces.
enum NovaRiskWords {
    static func state(_ value: NovaRiskState) -> String {
        switch value {
        case .neverAssessed: return RDLocalization.string("localizable.nova.risk.state.never", table: .localizable, fallback: "Değerlendirilmemiş")
        case .periodUnknown: return RDLocalization.string("localizable.nova.risk.state.unknown", table: .localizable, fallback: "Süre bilinmiyor")
        case .expired: return RDLocalization.string("localizable.nova.risk.state.expired", table: .localizable, fallback: "Süresi doldu")
        case .dueSoon: return RDLocalization.string("localizable.nova.risk.state.due", table: .localizable, fallback: "Yaklaşıyor")
        case .valid: return RDLocalization.string("localizable.nova.risk.state.valid", table: .localizable, fallback: "Yürürlükte")
        }
    }
    /// Why the row reads the way it does. Every state has a reason, so no row is
    /// ever a colour with no explanation.
    static func explain(_ row: NovaRiskRow) -> String {
        switch row.state {
        case .neverAssessed: return RDLocalization.string("localizable.nova.risk.explain.never", table: .localizable,
            fallback: "Bu işyeri için tamamlanmış bir risk değerlendirmesi kaydı yok.")
        case .periodUnknown: return RDLocalization.string("localizable.nova.risk.explain.unknown", table: .localizable,
            fallback: "Belge var ama geçerlilik süresi kayıtlı değil. Süre girilene kadar tarih üretilmez.")
        case .expired: return RDLocalization.string("localizable.nova.risk.explain.expired", table: .localizable,
            fallback: "Geçerlilik tarihi geçti.")
        case .dueSoon: return RDLocalization.string("localizable.nova.risk.explain.due", table: .localizable,
            fallback: "Geçerlilik tarihi uyarı penceresinin içinde.")
        case .valid: return RDLocalization.string("localizable.nova.risk.explain.valid", table: .localizable,
            fallback: "Belge yürürlükte.")
        }
    }
    /// The sentence the screen carries wherever a period is shown.
    static let periodAttribution = RDLocalization.string("localizable.nova.risk.period.attribution", table: .localizable,
        fallback: "Süre kaynağı her satırda yazılıdır. Uzmanın kendi belirlediği süre mevzuat gereği olarak sunulmaz.")
    /// The sentence the screen carries wherever an analysis is offered.
    static let analysisNotAssessment = RDLocalization.string("localizable.nova.risk.analysis.note", table: .localizable,
        fallback: "Fotoğraf analizi kaynak olarak kullanılabilir; tek başına risk değerlendirmesi sayılmaz.")
}
