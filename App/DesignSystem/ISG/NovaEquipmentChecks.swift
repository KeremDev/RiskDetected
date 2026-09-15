import Foundation

/// What the inventory says about one item today. The value is always the
/// server's: it is worked out at read time from the last report and the type's
/// period, so nothing on this side recomputes or overrides one.
///
/// `periodUnknown` is its own answer on purpose. A report with no period behind
/// it is a gap in the record, never a statement that the equipment is good for
/// another year.
enum NovaEquipmentState: String, CaseIterable, Identifiable, Equatable {
    case neverInspected = "never_inspected"
    case periodUnknown = "period_unknown"
    case failed, overdue
    case dueSoon = "due_soon"
    case valid
    var id: String { rawValue }
}

/// The counters the page shows. Five groups over six states, every state in
/// exactly one group, and the same words are filter values the server accepts —
/// so tapping a counter narrows to exactly the rows that counter counted.
enum NovaEquipmentGroup: String, CaseIterable, Identifiable {
    case overdue, failed, untracked
    case dueSoon = "due_soon"
    case current
    var id: String { rawValue }

    var states: [NovaEquipmentState] {
        switch self {
        case .overdue: return [.overdue]
        case .failed: return [.failed]
        case .untracked: return [.neverInspected, .periodUnknown]
        case .dueSoon: return [.dueSoon]
        case .current: return [.valid]
        }
    }
    var title: String {
        switch self {
        case .overdue: return RDLocalization.string("localizable.nova.equipment.group.overdue", table: .localizable, fallback: "Süresi geçti")
        case .failed: return RDLocalization.string("localizable.nova.equipment.group.failed", table: .localizable, fallback: "Olumsuz")
        case .untracked: return RDLocalization.string("localizable.nova.equipment.group.untracked", table: .localizable, fallback: "Takipsiz")
        case .dueSoon: return RDLocalization.string("localizable.nova.equipment.group.due", table: .localizable, fallback: "Yaklaşıyor")
        case .current: return RDLocalization.string("localizable.nova.equipment.group.current", table: .localizable, fallback: "Güncel")
        }
    }
    /// A finding about the count, never an instruction.
    var footer: String {
        switch self {
        case .overdue: return RDLocalization.string("localizable.nova.equipment.group.overdue.footer", table: .localizable, fallback: "tarih geçti")
        case .failed: return RDLocalization.string("localizable.nova.equipment.group.failed.footer", table: .localizable, fallback: "son rapor")
        case .untracked: return RDLocalization.string("localizable.nova.equipment.group.untracked.footer", table: .localizable, fallback: "tarih yok")
        case .dueSoon: return RDLocalization.string("localizable.nova.equipment.group.due.footer", table: .localizable, fallback: "yaklaşan")
        case .current: return RDLocalization.string("localizable.nova.equipment.group.current.footer", table: .localizable, fallback: "raporlu")
        }
    }
    var symbol: String {
        switch self {
        case .overdue: return "exclamationmark.triangle"
        case .failed: return "xmark.octagon"
        case .untracked: return "questionmark.circle"
        case .dueSoon: return "clock"
        case .current: return "checkmark.circle"
        }
    }
    static func of(_ state: NovaEquipmentState) -> NovaEquipmentGroup {
        allCases.first { $0.states.contains(state) } ?? .untracked
    }
}

/// Where a type's period came from. The product never calls a period a legal
/// requirement unless the expert says what it is relying on.
enum NovaEquipmentPeriodSource: String, CaseIterable, Identifiable, Equatable {
    case manufacturer
    case ruleVersion = "rule_version"
    case unapprovedFixture = "unapproved_fixture"
    /// The product's own starting period for a type. The expert cannot choose
    /// this: the server only ever writes it itself, and it always carries the
    /// review flag until the expert replaces it with a source of their own.
    case regulationDefault = "regulation_default"
    var id: String { rawValue }
    /// A default and an unapproved fixture are both flagged; the server forces
    /// both, so this can never disagree with what is stored.
    var needsReview: Bool { self == .unapprovedFixture || self == .regulationDefault }
    /// What the expert may pick for themselves.
    static var choosable: [NovaEquipmentPeriodSource] { [.manufacturer, .ruleVersion, .unapprovedFixture] }
}

/// Whose answer the stored next date is. A date the expert wrote never reads as
/// one the period produced.
enum NovaEquipmentDueSource: String, Equatable {
    case period, expert
}

/// Where an inspection's attached evidence report actually lives, once one is
/// filed and clean.
struct NovaEquipmentAssetDownload: Equatable {
    let bucket: String
    let path: String
}

/// One inspection period, for one equipment type, in one company.
struct NovaEquipmentRule: Identifiable, Equatable {
    let equipmentType: String
    var periodMonths: Int
    var source: NovaEquipmentPeriodSource
    var needsReview: Bool
    var exceptionNote: String?
    var id: String { equipmentType }
}

/// One report on file. `nextDueOn` is what was worked out when it was filed; a
/// period added later never rewrites it.
struct NovaEquipmentInspection: Identifiable, Equatable {
    let id: UUID
    let performedOn: String
    let result: String
    let nextDueOn: String?
    let periodMonths: Int?
    let inspector: String?
    let externalRef: String?
    let note: String?
    let evidenceAssetID: UUID?
    let evidenceDownload: NovaEquipmentAssetDownload?
    var dueSource: NovaEquipmentDueSource?
    /// The expert's own note that an assignment was made in İSG-KATİP. Never a
    /// verification: nothing in this product reads the official system.
    var katipDeclared = false
    var katipNote: String?
}

struct NovaEquipmentItem: Identifiable, Equatable {
    let id: UUID
    var companyID: UUID?
    var companyName: String?
    var workplaceID: UUID?
    var workplaceName: String?
    var equipmentType: String
    var serialTag: String
    var acquiredOn: String?
    var locationNote: String?
    var isArchived: Bool
    /// The server's answer for today. Never derived here.
    var state: NovaEquipmentState
    var periodMonths: Int?
    var periodSource: NovaEquipmentPeriodSource?
    /// nil when the type has no rule at all.
    var periodNeedsReview: Bool?
    var periodExceptionNote: String?
    /// True when a period exists now but the report on file was written before
    /// it, so the two facts on screen do not appear to contradict each other.
    var periodDefinedAfterReport: Bool
    var lastPerformedOn: String?
    var lastResult: String?
    var lastInspector: String?
    var lastExternalRef: String?
    var nextDueOn: String?
    /// Whose answer that date is. Read, never decided here.
    var dueSource: NovaEquipmentDueSource?
    var katipDeclared = false
    var katipNote: String?
    /// Structurally false. The server can only ever send false.
    var katipOfficialVerification = false
    var evidenceAssetID: UUID?
    var evidenceDownload: NovaEquipmentAssetDownload?
    var inspections: [NovaEquipmentInspection] = []

    var group: NovaEquipmentGroup { .of(state) }
    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return [serialTag, equipmentType, companyName ?? "", locationNote ?? "", lastInspector ?? ""]
            .contains { $0.lowercased().contains(needle) }
    }
}

/// One company's share of the inventory, as the server counted it.
struct NovaEquipmentCompanySummary: Identifiable, Equatable {
    let id: UUID
    let name: String
    let total: Int
    let counts: [NovaEquipmentState: Int]
    func count(_ state: NovaEquipmentState) -> Int { counts[state] ?? 0 }
    func count(_ group: NovaEquipmentGroup) -> Int { group.states.reduce(0) { $0 + count($1) } }
    /// What this company is carrying that the expert has to look at: a date
    /// that has passed, or a last report that came back negative.
    var needsAttention: Int {
        count(NovaEquipmentState.overdue) + count(NovaEquipmentState.failed)
    }
}

/// The whole account in one answer: the tally, the per-company summary, the
/// per-type tally and one page of rows.
struct NovaEquipmentBoard: Equatable {
    var counts: [NovaEquipmentState: Int] = [:]
    var companies: [NovaEquipmentCompanySummary] = []
    var typeCounts: [String: [NovaEquipmentState: Int]] = [:]
    var rows: [NovaEquipmentItem] = []
    var total = 0
    var hasMore = false
    var limit = 10
    var offset = 0
    var today = ""
    /// How many days ahead the server starts warning. Read, never invented here.
    var noticeDays = 30

    func count(_ state: NovaEquipmentState) -> Int { counts[state] ?? 0 }
    func count(_ group: NovaEquipmentGroup) -> Int { group.states.reduce(0) { $0 + count($1) } }
    var tracked: Int { NovaEquipmentState.allCases.reduce(0) { $0 + count($1) } }
    var needsAttention: Int {
        count(NovaEquipmentState.overdue) + count(NovaEquipmentState.failed)
    }

    /// What one company-page heading is carrying, summed over its own types.
    func counts(forTypes types: [String]) -> [NovaEquipmentState: Int] {
        var result: [NovaEquipmentState: Int] = [:]
        for type in types {
            for (state, value) in typeCounts[type] ?? [:] { result[state, default: 0] += value }
        }
        return result
    }
    var allCounts: [NovaEquipmentState: Int] { counts }
}

/// What the page is asking for right now.
struct NovaEquipmentQuery: Equatable {
    var query = ""
    /// Either one exact state or one of the five counter groups; the server
    /// accepts both words and the page only ever sends one of them.
    var state: String?
    var company: UUID?
    var workplace: UUID?
    var equipmentType: String?
    /// The page shows ten rows at a time and asks for more on request.
    var limit = 10
    var offset = 0
}

/// What the register and edit forms collect.
struct NovaEquipmentDraft: Equatable {
    var equipmentType: String?
    var serialTag = ""
    var workplaceID: UUID?
    var acquiredOn = ""
    var locationNote = ""

    var isReady: Bool {
        equipmentType != nil && workplaceID != nil &&
            !serialTag.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// What the period form collects. A period never ships without the expert
/// saying where it came from.
struct NovaEquipmentRuleDraft: Equatable {
    var equipmentType: String?
    var periodMonths = ""
    var source: NovaEquipmentPeriodSource = .manufacturer
    var exceptionNote = ""

    var monthsValue: Int? { Int(periodMonths.trimmingCharacters(in: .whitespaces)) }
    var isReady: Bool {
        guard equipmentType != nil, let months = monthsValue, (1...240).contains(months) else { return false }
        return true
    }
}

/// What the inspection form collects.
struct NovaEquipmentInspectionDraft: Equatable {
    var performedOn = ""
    var result = "pass"
    /// Filled from the type's period as a suggestion the expert may change.
    /// Whether it counts as the period's answer or theirs is the server's call.
    var nextDueOn = ""
    var inspector = ""
    var externalRef = ""
    var note = ""
    /// Optional. The expert's own declaration that an İSG-KATİP assignment was
    /// made for this check; the product verifies nothing.
    var katipDeclared = false
    var katipNote = ""
    /// A report filed in the archive. The server refuses an asset that was
    /// never cleared, so this can only ever be a file that really exists.
    var evidenceAssetID: UUID?
    var evidenceTitle: String?

    var isReady: Bool {
        !performedOn.trimmingCharacters(in: .whitespaces).isEmpty &&
            ["pass", "fail", "conditional"].contains(result)
    }
}

enum NovaEquipmentFailure: Error, Equatable {
    case denied, validation, unavailable, moduleUnavailable, planRequired, conflict
    case futureReport, duplicateSerial, dueBeforeReport, dueOnFailedCheck
}

/// The words the module uses, in one place, so a state never reads as more than
/// what the record actually says.
enum NovaEquipmentWords {
    static func state(_ state: NovaEquipmentState) -> String {
        switch state {
        case .neverInspected: return RDLocalization.string("localizable.nova.equipment.state.never", table: .localizable, fallback: "Kontrol kaydı yok")
        case .periodUnknown: return RDLocalization.string("localizable.nova.equipment.state.unknown", table: .localizable, fallback: "Süre belirsiz")
        case .failed: return RDLocalization.string("localizable.nova.equipment.state.failed", table: .localizable, fallback: "Olumsuz")
        case .overdue: return RDLocalization.string("localizable.nova.equipment.state.overdue", table: .localizable, fallback: "Süresi geçti")
        case .dueSoon: return RDLocalization.string("localizable.nova.equipment.state.due", table: .localizable, fallback: "Yaklaşıyor")
        case .valid: return RDLocalization.string("localizable.nova.equipment.state.valid", table: .localizable, fallback: "Güncel")
        }
    }

    /// Why the record says what it says. An answer, not an instruction.
    static func explain(_ item: NovaEquipmentItem) -> String {
        switch item.state {
        case .neverInspected:
            return RDLocalization.string("localizable.nova.equipment.explain.never", table: .localizable,
                fallback: "Bu ekipman için kayıtlı kontrol raporu yok.")
        case .periodUnknown where item.periodDefinedAfterReport:
            return RDLocalization.string("localizable.nova.equipment.explain.late.rule", table: .localizable,
                fallback: "Rapor kaydedildiğinde bu tür için süre tanımlı değildi; sonraki tarih hesaplanmadı. Süre sonradan tanımlandı, eski rapor değiştirilmedi.")
        case .periodUnknown:
            return RDLocalization.string("localizable.nova.equipment.explain.unknown", table: .localizable,
                fallback: "Bu tür için kontrol süresi tanımlı değil; sonraki kontrol tarihi hesaplanmadı. Süreler ekranından tanımlayabilirsiniz.")
        case .failed:
            return RDLocalization.string("localizable.nova.equipment.explain.failed", table: .localizable,
                fallback: "Son kontrol olumsuz sonuçlandı; sonraki tarih üretilmedi.")
        case .overdue:
            return RDLocalization.string("localizable.nova.equipment.explain.overdue", table: .localizable,
                fallback: "Kayıtlı sonraki kontrol tarihi geçmiş.")
        case .dueSoon:
            return RDLocalization.string("localizable.nova.equipment.explain.due", table: .localizable,
                fallback: "Kayıtlı sonraki kontrol tarihi yaklaşıyor.")
        case .valid:
            return RDLocalization.string("localizable.nova.equipment.explain.valid", table: .localizable,
                fallback: "Kayıtlı sonraki kontrol tarihi henüz gelmedi.")
        }
    }

    static func result(_ value: String?) -> String {
        switch value {
        case "pass": return RDLocalization.string("localizable.nova.equipment.result.pass", table: .localizable, fallback: "Uygun")
        case "fail": return RDLocalization.string("localizable.nova.equipment.result.fail", table: .localizable, fallback: "Olumsuz")
        case "conditional": return RDLocalization.string("localizable.nova.equipment.result.conditional", table: .localizable, fallback: "Şartlı uygun")
        case .some(let other): return other
        case nil: return "—"
        }
    }

    /// Where the period came from, attributed rather than presented as a finding
    /// of the product's own.
    static func source(_ value: NovaEquipmentPeriodSource?) -> String {
        switch value {
        case .manufacturer: return RDLocalization.string("localizable.nova.equipment.source.manufacturer", table: .localizable, fallback: "Üretici/kullanma kılavuzu")
        case .ruleVersion: return RDLocalization.string("localizable.nova.equipment.source.rule", table: .localizable, fallback: "Uzmanın dayandığı mevzuat")
        case .unapprovedFixture: return RDLocalization.string("localizable.nova.equipment.source.expert", table: .localizable, fallback: "Uzman tarafından belirlenen")
        case .regulationDefault: return RDLocalization.string("localizable.nova.equipment.source.default", table: .localizable, fallback: "Mevzuat eki genel süresi · ürün varsayılanı")
        case nil: return RDLocalization.string("localizable.nova.equipment.source.none", table: .localizable, fallback: "Tanımlı değil")
        }
    }

    /// Whose answer the next date is, stated rather than left to look derived.
    static func due(_ value: NovaEquipmentDueSource?) -> String {
        switch value {
        case .period: return RDLocalization.string("localizable.nova.equipment.due.period", table: .localizable, fallback: "Süreden hesaplandı")
        case .expert: return RDLocalization.string("localizable.nova.equipment.due.expert", table: .localizable, fallback: "Uzman tarafından değiştirildi")
        case nil: return ""
        }
    }

    static func type(_ code: String) -> String {
        switch code {
        case "lifting_equipment": return RDLocalization.string("localizable.nova.equipment.type.lifting", table: .localizable, fallback: "Kaldırma ekipmanı")
        case "crane": return RDLocalization.string("localizable.nova.equipment.type.crane", table: .localizable, fallback: "Vinç")
        case "forklift": return RDLocalization.string("localizable.nova.equipment.type.forklift", table: .localizable, fallback: "Forklift")
        case "pressure_vessel": return RDLocalization.string("localizable.nova.equipment.type.pressure", table: .localizable, fallback: "Basınçlı kap")
        case "compressor": return RDLocalization.string("localizable.nova.equipment.type.compressor", table: .localizable, fallback: "Kompresör")
        case "boiler": return RDLocalization.string("localizable.nova.equipment.type.boiler", table: .localizable, fallback: "Kazan")
        case "lift": return RDLocalization.string("localizable.nova.equipment.type.lift", table: .localizable, fallback: "Asansör")
        case "scaffold": return RDLocalization.string("localizable.nova.equipment.type.scaffold", table: .localizable, fallback: "İskele")
        case "ladder": return RDLocalization.string("localizable.nova.equipment.type.ladder", table: .localizable, fallback: "Merdiven")
        case "electrical_installation": return RDLocalization.string("localizable.nova.equipment.type.electrical", table: .localizable, fallback: "Elektrik tesisatı")
        case "earthing": return RDLocalization.string("localizable.nova.equipment.type.earthing", table: .localizable, fallback: "Topraklama")
        case "fire_extinguisher": return RDLocalization.string("localizable.nova.equipment.type.extinguisher", table: .localizable, fallback: "Yangın söndürücü")
        case "fire_detection": return RDLocalization.string("localizable.nova.equipment.type.detection", table: .localizable, fallback: "Yangın algılama")
        case "ventilation": return RDLocalization.string("localizable.nova.equipment.type.ventilation", table: .localizable, fallback: "Havalandırma")
        case "power_tool": return RDLocalization.string("localizable.nova.equipment.type.tool", table: .localizable, fallback: "El aleti")
        case "welding_set": return RDLocalization.string("localizable.nova.equipment.type.welding", table: .localizable, fallback: "Kaynak makinesi")
        case "conveyor": return RDLocalization.string("localizable.nova.equipment.type.conveyor", table: .localizable, fallback: "Konveyör")
        case "press_machine": return RDLocalization.string("localizable.nova.equipment.type.press", table: .localizable, fallback: "Pres")
        case "lathe": return RDLocalization.string("localizable.nova.equipment.type.lathe", table: .localizable, fallback: "Torna")
        case "other_equipment": return RDLocalization.string("localizable.nova.equipment.type.other", table: .localizable, fallback: "Diğer ekipman")
        default: return code
        }
    }

    static func failure(_ failure: NovaEquipmentFailure) -> String {
        switch failure {
        case .denied: return RDLocalization.string("localizable.nova.equipment.failure.denied", table: .localizable, fallback: "Bu firmanın ekipman kayıtlarına erişim yok.")
        case .planRequired: return RDLocalization.string("localizable.nova.equipment.failure.plan", table: .localizable, fallback: "Kayıt eklemek için Plus veya Pro plan gerekiyor.")
        case .moduleUnavailable: return RDLocalization.string("localizable.nova.equipment.failure.module", table: .localizable, fallback: "Periyodik kontroller modülü şu anda açık değil.")
        case .conflict: return RDLocalization.string("localizable.nova.equipment.failure.conflict", table: .localizable, fallback: "Bu işlem farklı bir içerikle zaten kaydedilmiş.")
        case .validation: return RDLocalization.string("localizable.nova.equipment.failure.validation", table: .localizable, fallback: "Bilgiler eksik veya geçersiz.")
        case .futureReport: return RDLocalization.string("localizable.nova.equipment.failure.future", table: .localizable, fallback: "Kontrol tarihi bugünden ileri olamaz.")
        case .duplicateSerial: return RDLocalization.string("localizable.nova.equipment.failure.serial", table: .localizable, fallback: "Bu seri/kod bu firmada zaten kayıtlı.")
        case .dueBeforeReport: return RDLocalization.string("localizable.nova.equipment.failure.due.before", table: .localizable, fallback: "Sonraki kontrol tarihi, kontrol tarihinden sonra olmalı.")
        case .dueOnFailedCheck: return RDLocalization.string("localizable.nova.equipment.failure.due.failed", table: .localizable, fallback: "Olumsuz sonuçlanan kontrole sonraki tarih verilemez.")
        case .unavailable: return RDLocalization.string("localizable.nova.equipment.failure.unavailable", table: .localizable, fallback: "Ekipman servisi şu anda kullanılamıyor.")
        }
    }
}

/// Which equipment types a company heading covers, so the company page can show
/// the same inventory the module holds instead of a second list. Periodic
/// checks are the whole of this heading, so it takes every type.
enum NovaEquipmentSectionMap {
    static func types(for section: NovaCompanySection, in catalogue: [String]) -> [String]? {
        section == .inspections ? catalogue : nil
    }
}
