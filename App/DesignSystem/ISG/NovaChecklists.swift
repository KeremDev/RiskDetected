import Foundation

/// Where a run is. The value is always the server's; nothing on this side
/// decides that a run is finished.
enum NovaChecklistRunState: String, CaseIterable, Identifiable, Equatable {
    case open, submitted, cancelled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: return RDLocalization.string("localizable.nova.checklist.state.open", table: .localizable, fallback: "Devam eden")
        case .submitted: return RDLocalization.string("localizable.nova.checklist.state.submitted", table: .localizable, fallback: "Tamamlandı")
        case .cancelled: return RDLocalization.string("localizable.nova.checklist.state.cancelled", table: .localizable, fallback: "İptal edildi")
        }
    }
    var footer: String {
        switch self {
        case .open: return RDLocalization.string("localizable.nova.checklist.state.open.footer", table: .localizable, fallback: "yanıt bekliyor")
        case .submitted: return RDLocalization.string("localizable.nova.checklist.state.submitted.footer", table: .localizable, fallback: "kayıtlı")
        case .cancelled: return RDLocalization.string("localizable.nova.checklist.state.cancelled.footer", table: .localizable, fallback: "vazgeçildi")
        }
    }
    var symbol: String {
        switch self {
        case .open: return "square.and.pencil"
        case .submitted: return "checkmark.circle"
        case .cancelled: return "xmark.circle"
        }
    }
}

/// What one question was answered with. `notApplicable` is only offered where
/// the list itself allows it, because the server refuses it elsewhere.
enum NovaChecklistResult: String, CaseIterable, Identifiable, Equatable {
    case conform, nonconform
    case notApplicable = "not_applicable"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .conform: return RDLocalization.string("localizable.nova.checklist.result.conform", table: .localizable, fallback: "Uygun")
        case .nonconform: return RDLocalization.string("localizable.nova.checklist.result.nonconform", table: .localizable, fallback: "Uygun değil")
        case .notApplicable: return RDLocalization.string("localizable.nova.checklist.result.na", table: .localizable, fallback: "Uygulanamaz")
        }
    }
    var wireValue: String {
        switch self {
        case .conform: return "compliant"
        case .nonconform: return "non_compliant"
        case .notApplicable: return "not_applicable"
        }
    }
    init?(wireValue: String) {
        switch wireValue {
        case "compliant", "conform": self = .conform
        case "non_compliant", "nonconform": self = .nonconform
        case "not_applicable": self = .notApplicable
        default: return nil
        }
    }
    var symbol: String {
        switch self {
        case .conform: return "checkmark.circle"
        case .nonconform: return "exclamationmark.triangle"
        case .notApplicable: return "minus.circle"
        }
    }
}

/// The severities the nonconformity record accepts. Offered only when the
/// expert has already asked to open one.
enum NovaChecklistSeverity: String, CaseIterable, Identifiable, Equatable {
    case low, medium, high, critical
    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: return RDLocalization.string("localizable.nova.checklist.severity.low", table: .localizable, fallback: "Düşük")
        case .medium: return RDLocalization.string("localizable.nova.checklist.severity.medium", table: .localizable, fallback: "Orta")
        case .high: return RDLocalization.string("localizable.nova.checklist.severity.high", table: .localizable, fallback: "Yüksek")
        case .critical: return RDLocalization.string("localizable.nova.checklist.severity.critical", table: .localizable, fallback: "Kritik")
        }
    }
}

/// One question as the run shows it: the prompt the pinned version asked, and
/// the answer if there is one.
struct NovaChecklistAnswer: Identifiable, Equatable {
    var id: String { itemCode }
    let itemCode: String
    let prompt: String
    let position: Int
    let atomicItemCode: String?
    let sectionTitle: String?
    let scopeKey: String?
    let allowsNotApplicable: Bool
    let verificationMethod: String?
    let helpText: String?
    let tags: [String]
    let riskTopic: String?
    let naReasonRequired: Bool
    let evidenceRecommended: Bool
    let photoRequired: Bool
    let result: NovaChecklistResult?
    let note: String?
    let evidenceAssetID: UUID?
    let nonconformityID: UUID?
    var isAnswered: Bool { result != nil }
}

/// One run: what it was filled against, and what it found.
struct NovaChecklistRun: Identifiable, Equatable {
    let id: UUID
    let companyID: UUID?
    let companyName: String?
    let workplaceID: UUID?
    let workplaceName: String?
    let templateCode: String
    let templateTitle: String?
    /// The version pinned when the run started. Publishing a newer list later
    /// never changes what this run asked.
    let templateVersion: Int
    let state: NovaChecklistRunState
    let startedOn: String
    let submittedAt: String?
    let revision: Int64
    let revisesRunID: UUID?
    let areaLabel: String?
    let equipmentLabel: String?
    let documentNumber: String?
    let expected: Int
    let answered: Int
    let remaining: Int
    let conform: Int
    let nonconform: Int
    let notApplicable: Int
    let progressPercent: Double?
    let coveragePercent: Double?
    let applicableCoveragePercent: Double?
    let scorePercent: Double?
    let sourceIDs: [String]
    /// How many failing answers the expert chose to turn into a record. Never
    /// all of them by default, because nothing converts on its own.
    let nonconformitiesOpened: Int
    let answers: [NovaChecklistAnswer]
    var isPersonal: Bool { companyID == nil }
    var isComplete: Bool { expected > 0 && remaining == 0 }
    /// A partial run must never read as fully compliant. The server score is
    /// meaningful only after every question has an answer.
    var completedScorePercent: Double? { isComplete ? scorePercent : nil }
}

/// One question in a template the expert is editing.
struct NovaChecklistTemplateItem: Identifiable, Equatable {
    var id: String { itemCode }
    let itemCode: String
    let prompt: String
    let position: Int
    let atomicItemCode: String?
    let sectionTitle: String?
    let scopeKey: String?
    let allowsNotApplicable: Bool
    let verificationMethod: String?
    let helpText: String?
    let tags: [String]
    let riskTopic: String?
    let naReasonRequired: Bool
    let evidenceRecommended: Bool
    let photoRequired: Bool
    let sourceIDs: [String]
}

/// One version of a list. Only a draft is editable.
struct NovaChecklistTemplateVersion: Identifiable, Equatable {
    var id: Int { version }
    let version: Int
    let revision: Int64
    let status: String
    let publishedAt: String?
    let approvalNote: String?
    let items: [NovaChecklistTemplateItem]
    var isDraft: Bool { status == "draft" }
    var isPublished: Bool { status == "published" }
    var statusTitle: String {
        switch status {
        case "draft": return RDLocalization.string("localizable.nova.checklist.version.draft", table: .localizable, fallback: "Taslak")
        case "published": return RDLocalization.string("localizable.nova.checklist.version.published", table: .localizable, fallback: "Yayımda")
        default: return RDLocalization.string("localizable.nova.checklist.version.superseded", table: .localizable, fallback: "Geçmiş")
        }
    }
}

/// One list the expert wrote, with all its versions.
struct NovaChecklistTemplate: Identifiable, Equatable {
    var id: String { templateCode }
    let templateCode: String
    let title: String
    /// A product template is readable but never editable. None ships today.
    let isProduct: Bool
    let isArchived: Bool
    let versions: [NovaChecklistTemplateVersion]
    var draft: NovaChecklistTemplateVersion? { versions.first(where: \.isDraft) }
    var published: NovaChecklistTemplateVersion? { versions.first(where: \.isPublished) }
}

/// A list a run may be started from: published only.
struct NovaChecklistStarter: Identifiable, Equatable {
    var id: String { templateCode }
    let templateCode: String
    let title: String
    let version: Int
    let items: Int
    let isProduct: Bool
    let catalogTemplateCode: String?
    let sectorCode: String?
    let kind: String?
    let scopeNote: String?
    let professionalReviewStatus: String?

    var kindTitle: String {
        switch kind {
        case "sector": return "Saha"
        case "activity": return "Faaliyet"
        case "equipment": return "Ekipman"
        case "hazard": return "Tehlike"
        default: return RDLocalization.string("localizable.nova.checklists.genel.338fde21", table: .localizable, fallback: "Genel")
        }
    }

    var selectionSubtitle: String {
        let context = [sectorCode, kindTitle, "\(items) soru"]
            .compactMap { $0 }.joined(separator: " · ")
        guard let scopeNote, !scopeNote.isEmpty else { return context }
        return context + "\n" + scopeNote
    }
}

struct NovaChecklistCatalogue: Equatable {
    struct Workplace: Identifiable, Equatable { let id: UUID; let name: String; let needsReview: Bool }
    let workplaces: [Workplace]
    let starters: [NovaChecklistStarter]
    let productTemplatesOffered: Bool
    let catalogVersion: String?
    let publicationStatus: String?
    let professionalReviewStatus: String?
}

struct NovaChecklistLibrarySector: Identifiable, Equatable {
    var id: String { code }
    let code: String
    let name: String
    let count: Int
}

struct NovaChecklistLibraryItem: Identifiable, Equatable {
    var id: String { templateCode }
    let templateCode: String
    let catalogTemplateCode: String
    let title: String
    let sectorCode: String?
    let sectorName: String?
    let kind: String
    let aliases: [String]
    let scopeNote: String
    let professionalReviewStatus: String
    let items: Int
    let sourceIDs: [String]
}

struct NovaChecklistLibraryMatch: Identifiable, Equatable {
    struct Context: Identifiable, Equatable {
        var id: String { templateCode + ":" + itemCode }
        let templateCode: String
        let catalogTemplateCode: String
        let title: String
        let sectorCode: String?
        let sectorName: String?
        let itemCode: String
    }
    var id: String { atomicItemCode }
    let atomicItemCode: String
    let prompt: String
    let verificationMethod: String?
    let riskTopic: String?
    let tags: [String]
    let sourceIDs: [String]
    let contexts: [Context]
}

struct NovaChecklistLibrary: Equatable {
    let catalogVersion: String
    let publicationStatus: String
    let professionalReviewStatus: String
    let sectors: [NovaChecklistLibrarySector]
    let rows: [NovaChecklistLibraryItem]
    let matchedItems: [NovaChecklistLibraryMatch]
    let total: Int
    let limit: Int
    let offset: Int
    var hasMore: Bool { offset + rows.count < total }
}

struct NovaChecklistTemplateDetail: Identifiable, Equatable {
    var id: String { templateCode }
    let templateCode: String
    let catalogTemplateCode: String?
    let catalogVersion: String?
    let title: String
    let sectorCode: String?
    let kind: String?
    let aliases: [String]
    let scopeNote: String?
    let sourceIDs: [String]
    let isProduct: Bool
    let professionalReviewStatus: String?
    let version: Int
    let items: [NovaChecklistTemplateItem]
}

struct NovaChecklistBoard: Equatable {
    struct CompanyTally: Identifiable, Equatable {
        let id: UUID
        let name: String
        let total: Int
        let counts: [String: Int]
    }
    let rows: [NovaChecklistRun]
    let counts: [String: Int]
    let companies: [CompanyTally]
    let total: Int
    let hasMore: Bool
    let offset: Int
    func count(_ state: NovaChecklistRunState) -> Int { counts[state.rawValue] ?? 0 }
    var needsAttention: Int { count(.open) }
}

struct NovaChecklistQuery: Equatable {
    var company: UUID?
    var state: String?
    var workplace: UUID?
    var template: String?
    var search: String = ""
    var limit: Int = 10
    var offset: Int = 0
}

/// What the expert fills in to answer one question. The record toggle is its
/// own field on purpose: a failing answer is not a finding until it is asked
/// for.
struct NovaChecklistAnswerDraft: Equatable {
    var runID: UUID?
    var itemCode: String = ""
    var prompt: String = ""
    var allowsNotApplicable: Bool = true
    var verificationMethod: String?
    var helpText: String?
    var naReasonRequired: Bool = false
    var evidenceRecommended: Bool = false
    var photoRequired: Bool = false
    var result: NovaChecklistResult = .conform
    var note: String = ""
    var attachment: IsgWorkspaceAttachmentDraft?
    var evidenceAssetID: UUID?
    var openNonconformity: Bool = false
    var severity: NovaChecklistSeverity = .medium
    var dueOn: String = ""
    var expectedRevision: Int64 = 0
}

struct NovaChecklistItemSelection: Equatable {
    let sourceTemplateCode: String
    let sourceItemCode: String
    var sectionTitle: String = ""
    var scopeKey: String = ""
    var allowDuplicate = false
}

struct NovaChecklistAssignment: Identifiable, Equatable {
    let id: UUID
    let companyID: UUID
    let workplaceID: UUID?
    let workplaceName: String?
    let templateCode: String
    let templateTitle: String
    let templateVersion: Int
    let assignedAt: String
}

enum NovaChecklistFailure: Error, Equatable {
    case denied, planRequired, moduleUnavailable, validation, explanationRequired, conflict
    case runSubmitted, runIncomplete, templatePublished, duplicateItem, companyRequired
    case unavailable
    var message: String {
        switch self {
        case .denied: return RDLocalization.string("localizable.nova.checklist.error.denied", table: .localizable,
            fallback: "Bu kayda erişim yok.")
        case .planRequired: return RDLocalization.string("localizable.nova.checklist.error.plan", table: .localizable,
            fallback: "Bu işlem için Plus veya Pro aboneliği gerekiyor.")
        case .moduleUnavailable: return RDLocalization.string("localizable.nova.checklist.error.module", table: .localizable,
            fallback: "Kontrol listeleri modülü henüz açık değil.")
        case .validation: return RDLocalization.string("localizable.nova.checklist.error.validation", table: .localizable,
            fallback: "Girilen bilgiler eksik veya birbiriyle uyumsuz.")
        case .explanationRequired: return RDLocalization.string("localizable.nova.checklists.uygun.degil.ve.uygulanamaz.yanitlarinda.aciklama.9301e1c9", table: .localizable, fallback: "Uygun değil ve Uygulanamaz yanıtlarında açıklama zorunludur.")
        case .conflict: return RDLocalization.string("localizable.nova.checklist.error.conflict", table: .localizable,
            fallback: "Kayıt bu sırada başka bir yerden değişti. Yenileyip tekrar deneyin.")
        case .runSubmitted: return RDLocalization.string("localizable.nova.checklist.error.submitted", table: .localizable,
            fallback: "Tamamlanmış kontrol değiştirilemez.")
        case .runIncomplete: return RDLocalization.string("localizable.nova.checklist.error.incomplete", table: .localizable,
            fallback: "Yanıtlanmamış soru var. Tamamlamak için hepsini yanıtlayın.")
        case .templatePublished: return RDLocalization.string("localizable.nova.checklist.error.published", table: .localizable,
            fallback: "Yayımlanmış liste değiştirilemez. Değişiklik için yeni sürüm açın.")
        case .duplicateItem: return RDLocalization.string("localizable.nova.checklists.bu.madde.ayni.kapsam.anahtariyla.listede.zaten.v.3df1a4ef", table: .localizable, fallback: "Bu madde aynı kapsam anahtarıyla listede zaten var. Gerçekten farklı bir alan veya ekipman içinse ayrı bir kapsam adı girin.")
        case .companyRequired: return RDLocalization.string("localizable.nova.checklists.kanit.veya.uygunsuzluk.kaydi.icin.kontrolu.bir.f.e893f7b2", table: .localizable, fallback: "Kanıt veya uygunsuzluk kaydı için kontrolü bir firmada başlatın.")
        case .unavailable: return RDLocalization.string("localizable.nova.checklist.error.unavailable", table: .localizable,
            fallback: "Kayıt alınamadı. Bağlantıyı kontrol edip tekrar deneyin.")
        }
    }
}

/// The words the screens use, in one place so the same thing never gets two
/// names on two surfaces.
enum NovaChecklistWords {
    /// The sentence the screen carries wherever a failing answer is shown.
    static let neverAutomatic = RDLocalization.string("localizable.nova.checklist.auto.note", table: .localizable,
        fallback: "Olumsuz yanıt kendiliğinden uygunsuzluk kaydı açmaz. Kayıt açmak sizin seçiminizdir.")
    /// The sentence the templates screen carries at the top.
    static let catalogNotice = RDLocalization.string("localizable.nova.checklist.product.note", table: .localizable,
        fallback: "Ürün hazır kontrol listesi göndermez. Onaylanmış bir soru kataloğu yok; listeyi siz yazarsınız.")
    /// The sentence beside a published version.
    static let selfApproved = RDLocalization.string("localizable.nova.checklist.approval.note", table: .localizable,
        fallback: "Yayımlamak listenin sizin onayınızdan geçtiği anlamına gelir; mevzuat onayı değildir.")
    /// Why a run reads the way it does.
    static func explain(_ run: NovaChecklistRun) -> String {
        switch run.state {
        case .open:
            return String(format: RDLocalization.string("localizable.nova.checklist.explain.open", table: .localizable,
                fallback: "%d sorudan %d tanesi yanıtlandı."), run.expected, run.answered)
        case .submitted:
            return String(format: RDLocalization.string("localizable.nova.checklist.explain.submitted", table: .localizable,
                fallback: "%d uygun, %d uygun değil, %d uygulanamaz."), run.conform, run.nonconform, run.notApplicable)
        case .cancelled:
            return RDLocalization.string("localizable.nova.checklist.explain.cancelled", table: .localizable,
                fallback: "Bu kontrolden vazgeçildi; yanıtları kayıtta kaldı.")
        }
    }
}
