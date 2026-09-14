import Foundation

/// What the tracker says about one obligation today. The value always comes
/// from the server: missing, due soon and expired are worked out there from the
/// dates, so nothing on this side recomputes or overrides one.
enum NovaDocumentStatus: String, CaseIterable, Identifiable, Equatable {
    case missing, dueSoon = "due_soon", expired, valid
    var id: String { rawValue }
}

/// Who says the document is owed. `expert` is the expert's own decision and is
/// the default; `legal` additionally carries the reference they are relying on.
/// The product never asserts a legal duty of its own.
enum NovaDocumentBasis: String, CaseIterable, Identifiable, Equatable {
    case expert, legal
    var id: String { rawValue }
}

/// One kind of document the tracker offers. The catalogue is the server's and
/// holds no health record: there is no code for one.
struct NovaDocumentKind: Identifiable, Equatable {
    let code: String
    let ordinal: Int
    let defaultValidityDays: Int?
    var id: String { code }
}

/// One copy the company holds. The file itself is not stored anywhere: what is
/// kept is the expert's own reference to where the original is.
struct NovaDocumentCopy: Identifiable, Equatable {
    let id: UUID
    let issuedOn: String
    let validUntil: String?
    let documentNo: String?
    let locationNote: String?
    let recordedAt: String?
}

struct NovaDocumentObligation: Identifiable, Equatable {
    let id: UUID
    /// The company the row belongs to. The portfolio spans several, so every
    /// row carries its own rather than inheriting the page's.
    var companyID: UUID?
    var companyName: String?
    var workplaceID: UUID?
    var kindCode: String
    var title: String
    var basis: NovaDocumentBasis
    var legalRef: String?
    var validityDays: Int?
    var noticeDays: Int
    var responsibleContact: String?
    var note: String?
    var isArchived: Bool
    var version: Int
    /// The server's answer for today. Never derived here.
    var status: NovaDocumentStatus
    var latestIssuedOn: String?
    var latestValidUntil: String?
    var copies: [NovaDocumentCopy]
    /// The server says plainly that it holds no file for this row.
    var fileStored: Bool = false
    /// Resolved by the screen from the workplace list, when the row has one.
    var workplaceName: String?

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return [title, kindCode, companyName ?? "", workplaceName ?? "", responsibleContact ?? "", legalRef ?? ""]
            .contains { $0.lowercased().contains(needle) }
    }
}

/// One page of the tracker: the rows, the tally the server counted and the day
/// that tally was worked out for.
struct NovaDocumentBoard: Equatable {
    var rows: [NovaDocumentObligation] = []
    /// How many rows fall in each status. A tally of tracked documents, never a
    /// statement that the company or anyone in it is compliant.
    var counts: [NovaDocumentStatus: Int] = [:]
    var today: String = ""
    /// The server said no file store is available for this feature.
    var fileStorageAvailable = false

    func count(_ status: NovaDocumentStatus) -> Int { counts[status] ?? 0 }
    var total: Int { rows.count }
}

/// One company's share of the portfolio, as the server counted it.
struct NovaDocumentCompanySummary: Identifiable, Equatable {
    let id: UUID
    let name: String
    let total: Int
    let counts: [NovaDocumentStatus: Int]
    func count(_ status: NovaDocumentStatus) -> Int { counts[status] ?? 0 }
    /// The worst thing this company is carrying, for the row's own pill.
    var worst: NovaDocumentStatus? {
        [NovaDocumentStatus.expired, .missing, .dueSoon].first { count($0) > 0 }
    }
}

/// The whole account in one answer: the tally, the per-company summary and one
/// page of rows. The tally covers everything tracked, before any filter, so
/// picking a chip never makes the account look smaller than it is.
struct NovaDocumentPortfolio: Equatable {
    var counts: [NovaDocumentStatus: Int] = [:]
    var companies: [NovaDocumentCompanySummary] = []
    /// Per document kind, following the company filter alone. The company page
    /// reads every heading from this instead of asking once per heading.
    var kindCounts: [String: [NovaDocumentStatus: Int]] = [:]
    var rows: [NovaDocumentObligation] = []
    /// How many rows match the filter in force, across every page.
    var total = 0
    var hasMore = false
    var today = ""
    var fileStorageAvailable = false

    func count(_ status: NovaDocumentStatus) -> Int { counts[status] ?? 0 }
    /// Everything the account tracks, however it is filtered right now.
    var tracked: Int { NovaDocumentStatus.allCases.reduce(0) { $0 + count($1) } }
    var needsAttention: Int { count(.missing) + count(.expired) + count(.dueSoon) }

    /// What one company-page heading is carrying, summed over its own kinds.
    func counts(forKinds kinds: [String]) -> [NovaDocumentStatus: Int] {
        var result: [NovaDocumentStatus: Int] = [:]
        for kind in kinds {
            for (status, value) in kindCounts[kind] ?? [:] { result[status, default: 0] += value }
        }
        return result
    }
}

/// Which company sections a document kind belongs under, so the company page
/// can show the same records the tracker holds instead of a second list.
enum NovaDocumentSectionMap {
    static func kinds(for section: NovaCompanySection) -> [String]? {
        switch section {
        case .risk: return ["risk_assessment"]
        case .emergency: return ["emergency_plan", "drill_record"]
        case .inspections: return ["equipment_inspection", "measurement_report"]
        case .board: return ["board_minutes"]
        case .handover: return ["ppe_handover"]
        case .representative: return ["appointment_letter"]
        case .files: return ["service_contract", "annual_work_plan", "permit_form",
                             "contractor_file", "approved_notebook", "other"]
        // Training documents are the training module's own record, and the logo,
        // personnel, support and accident headings are not document obligations.
        case .training, .logo, .personnel, .support, .accidents: return nil
        }
    }
}

/// What the portfolio page is asking for right now.
struct NovaDocumentQuery: Equatable {
    var query = ""
    var status: NovaDocumentStatus?
    var company: UUID?
    var kinds: [String]?
    /// The page shows ten rows at a time and asks for more on request.
    var limit = 10
    var offset = 0
}

/// What the add and edit forms collect.
struct NovaDocumentDraft: Equatable {
    var kindCode: String?
    var title: String = ""
    var workplaceID: UUID?
    var basis: NovaDocumentBasis = .expert
    var legalRef: String = ""
    var validityDays: String = ""
    var noticeDays: String = "30"
    var responsibleContact: String = ""
    var note: String = ""

    /// A legal basis is only offered once the expert has typed the reference,
    /// so the record can never claim a duty with nothing behind it.
    var isReady: Bool {
        guard kindCode != nil, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if basis == .legal && legalRef.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return true
    }
    var validityValue: Int? { Int(validityDays.trimmingCharacters(in: .whitespaces)) }
    var noticeValue: Int { Int(noticeDays.trimmingCharacters(in: .whitespaces)) ?? 30 }
}

/// What the copy form collects. An absent end date lets the obligation's own
/// period decide, and an obligation without one produces a copy that stands.
struct NovaDocumentCopyDraft: Equatable {
    var issuedOn: String = ""
    var validUntil: String = ""
    var documentNo: String = ""
    var locationNote: String = ""
    var isReady: Bool { !issuedOn.trimmingCharacters(in: .whitespaces).isEmpty }
}

enum NovaDocumentFailure: Error, Equatable {
    case denied, validation, versionConflict, archived, unavailable, planRequired, conflict
}

/// One workplace an obligation can be scoped to.
struct NovaDocumentWorkplace: Identifiable, Equatable {
    let id: UUID
    let name: String
}

/// The words the tracker uses, in one place so a status never reads as one
/// thing on the card and another in the popup.
enum NovaDocumentWords {
    static func status(_ value: NovaDocumentStatus) -> String {
        switch value {
        case .missing: return RDLocalization.string("localizable.nova.document.status.missing", table: .localizable, fallback: "Eksik")
        case .dueSoon: return RDLocalization.string("localizable.nova.document.status.due.soon", table: .localizable, fallback: "Yaklaşıyor")
        case .expired: return RDLocalization.string("localizable.nova.document.status.expired", table: .localizable, fallback: "Süresi doldu")
        case .valid: return RDLocalization.string("localizable.nova.document.status.valid", table: .localizable, fallback: "Güncel")
        }
    }

    static func tone(_ value: NovaDocumentStatus) -> NovaStatus {
        switch value {
        case .missing: return .danger
        case .expired: return .danger
        case .dueSoon: return .warning
        case .valid: return .success
        }
    }

    static func symbol(_ value: NovaDocumentStatus) -> String {
        switch value {
        case .missing: return "questionmark.circle"
        case .expired: return "exclamationmark.circle"
        case .dueSoon: return "clock"
        case .valid: return "checkmark.circle"
        }
    }

    static func basis(_ value: NovaDocumentBasis) -> String {
        switch value {
        case .expert: return RDLocalization.string("localizable.nova.document.basis.expert", table: .localizable, fallback: "Uzman kararı")
        case .legal: return RDLocalization.string("localizable.nova.document.basis.legal", table: .localizable, fallback: "Mevzuat dayanağı")
        }
    }

    /// The catalogue codes, named. A health record has no code here because the
    /// server's catalogue has none.
    static func kind(_ code: String) -> String {
        switch code {
        case "risk_assessment": return RDLocalization.string("localizable.nova.document.kind.risk.assessment", table: .localizable, fallback: "Risk değerlendirmesi")
        case "emergency_plan": return RDLocalization.string("localizable.nova.document.kind.emergency.plan", table: .localizable, fallback: "Acil durum planı")
        case "drill_record": return RDLocalization.string("localizable.nova.document.kind.drill", table: .localizable, fallback: "Tatbikat kaydı")
        case "training_record": return RDLocalization.string("localizable.nova.document.kind.training", table: .localizable, fallback: "Eğitim kaydı")
        case "board_minutes": return RDLocalization.string("localizable.nova.document.kind.board", table: .localizable, fallback: "Kurul tutanağı")
        case "appointment_letter": return RDLocalization.string("localizable.nova.document.kind.appointment", table: .localizable, fallback: "Görevlendirme yazısı")
        case "ppe_handover": return RDLocalization.string("localizable.nova.document.kind.ppe", table: .localizable, fallback: "KKD zimmet formu")
        case "equipment_inspection": return RDLocalization.string("localizable.nova.document.kind.inspection", table: .localizable, fallback: "Periyodik kontrol raporu")
        case "measurement_report": return RDLocalization.string("localizable.nova.document.kind.measurement", table: .localizable, fallback: "Ortam ölçüm raporu")
        case "service_contract": return RDLocalization.string("localizable.nova.document.kind.contract", table: .localizable, fallback: "İSG hizmet sözleşmesi")
        case "annual_work_plan": return RDLocalization.string("localizable.nova.document.kind.work.plan", table: .localizable, fallback: "Yıllık çalışma planı")
        case "annual_training_plan": return RDLocalization.string("localizable.nova.document.kind.training.plan", table: .localizable, fallback: "Yıllık eğitim planı")
        case "permit_form": return RDLocalization.string("localizable.nova.document.kind.permit", table: .localizable, fallback: "Çalışma izni formu")
        case "contractor_file": return RDLocalization.string("localizable.nova.document.kind.contractor", table: .localizable, fallback: "Taşeron evrak dosyası")
        case "approved_notebook": return RDLocalization.string("localizable.nova.document.kind.notebook", table: .localizable, fallback: "Onaylı defter")
        default: return RDLocalization.string("localizable.nova.document.kind.other", table: .localizable, fallback: "Diğer belge")
        }
    }

    static func kindSymbol(_ code: String) -> String {
        switch code {
        case "risk_assessment": return "exclamationmark.triangle"
        case "emergency_plan": return "figure.run"
        case "drill_record": return "flame"
        case "training_record", "annual_training_plan": return "graduationcap.fill"
        case "board_minutes": return "person.3"
        case "appointment_letter": return "signature"
        case "ppe_handover": return "shield"
        case "equipment_inspection": return "wrench.and.screwdriver"
        case "measurement_report": return "waveform.path.ecg"
        case "service_contract": return "doc.plaintext"
        case "annual_work_plan": return "calendar"
        case "permit_form": return "checkmark.seal"
        case "contractor_file": return "building.2"
        case "approved_notebook": return "book"
        default: return "doc.text"
        }
    }

    static func failure(_ value: NovaDocumentFailure) -> String {
        switch value {
        case .denied:
            return RDLocalization.string("localizable.nova.document.error.denied", table: .localizable,
                fallback: "Bu firmanın evrak takibine erişiminiz yok.")
        case .versionConflict, .conflict:
            return RDLocalization.string("localizable.nova.document.error.conflict", table: .localizable,
                fallback: "Kayıt bu sırada değişti. Listeyi yenileyip tekrar deneyin.")
        case .archived:
            return RDLocalization.string("localizable.nova.document.error.archived", table: .localizable,
                fallback: "Arşivlenmiş bir takip kaydına yeni kopya eklenemez.")
        case .validation:
            return RDLocalization.string("localizable.nova.document.error.validation", table: .localizable,
                fallback: "Gönderilen bilgiler kabul edilmedi. Alanları kontrol edin.")
        case .planRequired:
            return RDLocalization.string("localizable.nova.document.error.plan", table: .localizable,
                fallback: "Evrak takibi için Plus veya Pro plan gerekir.")
        case .unavailable:
            return RDLocalization.string("localizable.nova.document.error.unavailable", table: .localizable,
                fallback: "Evrak takibi şu anda kullanılamıyor.")
        }
    }
}
