import Foundation

/// `profiles` tablosunun Swift karşılığı.
///
/// `tier` ve `id` dışında tüm alanlar optional; böylece şema değişikliklerinde
/// (örn. yeni kolon eklendiğinde) decode düşmez ve UI graceful degrade eder.
struct UserProfile: Codable, Identifiable, Equatable {
    let id: UUID
    let email: String?
    let fullName: String?
    let initials: String?
    let title: String?
    let certificateNumber: String?
    let companyName: String?
    let companyLogoURL: String?
    let avatarURL: String?
    let phone: String?
    let tier: SubscriptionTier
    let preferredMethod: RiskMethodWire?
    let dailyQuotaUsed: Int?
    let dailyQuotaResetAt: String?
    let subscriptionPeriod: String?
    let subscriptionRenewalAt: String?
    let appLanguage: RDAppLanguage?
    let preferredContentLocale: RDContentLocale?
    let workJurisdictionCountry: RDWorkJurisdictionCountry?
    let workJurisdictionRegion: String?
    let safetyProfileID: RDSafetyProfileID?
    let safetyProfileVersion: Int?
    let legalDocumentSetID: RDLegalDocumentSetID?
    let firstSeenDeviceRegionCode: String?
    let firstSeenDeviceRegionAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName              = "full_name"
        case initials
        case title
        case certificateNumber     = "certificate_number"
        case companyName           = "company_name"
        case companyLogoURL        = "company_logo_url"
        case avatarURL             = "avatar_url"
        case phone
        case tier
        case preferredMethod       = "preferred_method"
        case dailyQuotaUsed        = "daily_quota_used"
        case dailyQuotaResetAt     = "daily_quota_reset_at"
        case subscriptionPeriod    = "subscription_period"
        case subscriptionRenewalAt = "subscription_renewal_at"
        case appLanguage            = "app_language"
        case preferredContentLocale = "preferred_content_locale"
        case workJurisdictionCountry = "work_jurisdiction_country"
        case workJurisdictionRegion = "work_jurisdiction_region"
        case safetyProfileID        = "safety_profile_id"
        case safetyProfileVersion   = "safety_profile_version"
        case legalDocumentSetID     = "legal_document_set"
        case firstSeenDeviceRegionCode = "first_seen_device_region_code"
        case firstSeenDeviceRegionAt = "first_seen_device_region_at"
        case createdAt             = "created_at"
    }

    var isPro: Bool { tier == .pro }
    var isPaid: Bool { tier.isPaid }

    /// İsim baş harflerini fallback'lerle hesaplar.
    var displayInitials: String {
        if let s = initials, !s.isEmpty { return s }
        if let name = fullName, !name.isEmpty {
            let comps = name.split(separator: " ").prefix(2)
            return comps.compactMap { $0.first.map(String.init) }.joined().uppercased()
        }
        return RDLocalization.string("localizable.user.profile.copy.7d215632", table: .localizable, fallback: "—")
    }

    var displayName: String {
        fullName ?? email?.split(separator: "@").first.map(String.init) ?? RDLocalization.string("localizable.user.profile.kullanici.e56ea28d", table: .localizable, fallback: "Kullanıcı")
    }
}

enum SubscriptionTier: String, Codable, Equatable {
    case free
    case plus
    case pro

    var rank: Int {
        switch self {
        case .free: return 0
        case .plus: return 1
        case .pro: return 2
        }
    }

    var title: String {
        switch self {
        case .free: return RDLocalization.string("localizable.user.profile.free.42029988", table: .localizable, fallback: "FREE")
        case .plus: return RDLocalization.string("localizable.user.profile.plus.4afa6f60", table: .localizable, fallback: "PLUS")
        case .pro: return RDLocalization.string("localizable.user.profile.pro.a455761d", table: .localizable, fallback: "PRO")
        }
    }

    var isPaid: Bool { self != .free }

    func includes(_ required: SubscriptionTier) -> Bool {
        rank >= required.rank
    }
}

struct PlanCapabilities: Equatable {
    let tier: SubscriptionTier
    let standardAnalysisLabel: String
    let detailedAnalysisLabel: String
    let reportLabel: String
    let acceleratedReportLabel: String
    let archiveLabel: String
    let canUseDetailedRiskTable: Bool
    let canUseEmergencyRisk: Bool
    let canUseProcedureCheck: Bool
    let advancedCanvasLabel: String
    let canUseAutomaticDelivery: Bool
    let canUseTrainedAI: Bool
    let supportLabel: String
    let maxPhotosPerAnalysis: Int
    let visiblePhotoSlotsInUI: Int
    let maxFindingsPerPhoto: Int
    let maxFindingsPerAnalysis: Int
    let canUseMultiPhotoAnalysis: Bool
    let canEditAIFindings: Bool
    let canAddManualFindings: Bool

    var isPaid: Bool { tier.isPaid }
    var isPro: Bool { tier == .pro }
    var safeVisiblePhotoSlotsInUI: Int { max(1, min(visiblePhotoSlotsInUI, 3)) }
    var safeMaxPhotosPerAnalysis: Int { max(1, min(maxPhotosPerAnalysis, 3)) }

    init(
        tier: SubscriptionTier,
        standardAnalysisLabel: String,
        detailedAnalysisLabel: String,
        reportLabel: String,
        acceleratedReportLabel: String,
        archiveLabel: String,
        canUseDetailedRiskTable: Bool,
        canUseEmergencyRisk: Bool,
        canUseProcedureCheck: Bool,
        advancedCanvasLabel: String,
        canUseAutomaticDelivery: Bool,
        canUseTrainedAI: Bool,
        supportLabel: String,
        maxPhotosPerAnalysis: Int = 1,
        visiblePhotoSlotsInUI: Int = 1,
        maxFindingsPerPhoto: Int = 12,
        maxFindingsPerAnalysis: Int = 12,
        canUseMultiPhotoAnalysis: Bool = false,
        canEditAIFindings: Bool = false,
        canAddManualFindings: Bool = false
    ) {
        self.tier = tier
        self.standardAnalysisLabel = standardAnalysisLabel
        self.detailedAnalysisLabel = detailedAnalysisLabel
        self.reportLabel = reportLabel
        self.acceleratedReportLabel = acceleratedReportLabel
        self.archiveLabel = archiveLabel
        self.canUseDetailedRiskTable = canUseDetailedRiskTable
        self.canUseEmergencyRisk = canUseEmergencyRisk
        self.canUseProcedureCheck = canUseProcedureCheck
        self.advancedCanvasLabel = advancedCanvasLabel
        self.canUseAutomaticDelivery = canUseAutomaticDelivery
        self.canUseTrainedAI = canUseTrainedAI
        self.supportLabel = supportLabel
        self.maxPhotosPerAnalysis = maxPhotosPerAnalysis
        self.visiblePhotoSlotsInUI = visiblePhotoSlotsInUI
        self.maxFindingsPerPhoto = maxFindingsPerPhoto
        self.maxFindingsPerAnalysis = maxFindingsPerAnalysis
        self.canUseMultiPhotoAnalysis = canUseMultiPhotoAnalysis
        self.canEditAIFindings = canEditAIFindings
        self.canAddManualFindings = canAddManualFindings
    }

    func applyingPhotoRules(
        maxPhotosPerAnalysis: Int,
        visiblePhotoSlotsInUI: Int,
        maxFindingsPerPhoto: Int,
        maxFindingsPerAnalysis: Int,
        canUseMultiPhotoAnalysis: Bool,
        canEditAIFindings: Bool,
        canAddManualFindings: Bool
    ) -> PlanCapabilities {
        PlanCapabilities(
            tier: tier,
            standardAnalysisLabel: standardAnalysisLabel,
            detailedAnalysisLabel: detailedAnalysisLabel,
            reportLabel: reportLabel,
            acceleratedReportLabel: acceleratedReportLabel,
            archiveLabel: archiveLabel,
            canUseDetailedRiskTable: canUseDetailedRiskTable,
            canUseEmergencyRisk: canUseEmergencyRisk,
            canUseProcedureCheck: canUseProcedureCheck,
            advancedCanvasLabel: advancedCanvasLabel,
            canUseAutomaticDelivery: canUseAutomaticDelivery,
            canUseTrainedAI: canUseTrainedAI,
            supportLabel: supportLabel,
            maxPhotosPerAnalysis: max(1, min(maxPhotosPerAnalysis, 3)),
            visiblePhotoSlotsInUI: max(1, min(visiblePhotoSlotsInUI, 3)),
            maxFindingsPerPhoto: max(1, maxFindingsPerPhoto),
            maxFindingsPerAnalysis: max(1, maxFindingsPerAnalysis),
            canUseMultiPhotoAnalysis: canUseMultiPhotoAnalysis,
            canEditAIFindings: canEditAIFindings,
            canAddManualFindings: canAddManualFindings
        )
    }

    static func forTier(_ tier: SubscriptionTier) -> PlanCapabilities {
        switch tier {
        case .free:
            return PlanCapabilities(
                tier: tier,
                standardAnalysisLabel: RDLocalization.string("localizable.user.profile.gunde.1.analiz.9d0f7674", table: .localizable, fallback: "Günde 1 analiz"),
                detailedAnalysisLabel: "Yok",
                reportLabel: RDLocalization.string("localizable.user.profile.3.ay.ozellestirilemez.542e7f36", table: .localizable, fallback: "3/ay, özelleştirilemez"),
                acceleratedReportLabel: "Yok",
                archiveLabel: RDLocalization.string("localizable.user.profile.7.gun.50bab9a0", table: .localizable, fallback: "7 gün"),
                canUseDetailedRiskTable: false,
                canUseEmergencyRisk: false,
                canUseProcedureCheck: false,
                advancedCanvasLabel: "Yok",
                canUseAutomaticDelivery: false,
                canUseTrainedAI: false,
                supportLabel: "Yok"
            )
        case .plus:
            return PlanCapabilities(
                tier: tier,
                standardAnalysisLabel: RDLocalization.string("localizable.user.profile.10.gun.27d28e88", table: .localizable, fallback: "10/gün"),
                detailedAnalysisLabel: RDLocalization.string("localizable.user.profile.2.gun.6ae8389a", table: .localizable, fallback: "2/gün"),
                reportLabel: RDLocalization.string("localizable.user.profile.150.ay.logolu.9cae9a62", table: .localizable, fallback: "150/ay, logolu"),
                acceleratedReportLabel: "50/ay",
                archiveLabel: RDLocalization.string("localizable.user.profile.30.gun.6dda91e3", table: .localizable, fallback: "30 gün"),
                canUseDetailedRiskTable: true,
                canUseEmergencyRisk: true,
                canUseProcedureCheck: false,
                advancedCanvasLabel: RDLocalization.string("localizable.user.profile.sinirli.54922517", table: .localizable, fallback: "Sınırlı"),
                canUseAutomaticDelivery: true,
                canUseTrainedAI: false,
                supportLabel: "E-posta"
            )
        case .pro:
            return PlanCapabilities(
                tier: tier,
                standardAnalysisLabel: RDLocalization.string("localizable.user.profile.40.gun.ac233a26", table: .localizable, fallback: "40/gün"),
                detailedAnalysisLabel: RDLocalization.string("localizable.user.profile.10.gun.3ca3a91b", table: .localizable, fallback: "10/gün"),
                reportLabel: RDLocalization.string("localizable.user.profile.750.ay.logolu.144b1175", table: .localizable, fallback: "750/ay, logolu"),
                acceleratedReportLabel: "250/ay",
                archiveLabel: RDLocalization.string("localizable.user.profile.sinirsiz.626a8719", table: .localizable, fallback: "Sınırsız"),
                canUseDetailedRiskTable: true,
                canUseEmergencyRisk: true,
                canUseProcedureCheck: true,
                advancedCanvasLabel: "Tam",
                canUseAutomaticDelivery: true,
                canUseTrainedAI: true,
                supportLabel: RDLocalization.string("localizable.user.profile.e.posta.whatsapp.a2275ad7", table: .localizable, fallback: "E-posta + WhatsApp")
            )
        }
    }
}

enum RiskMethodWire: String, Codable, Equatable {
    case fineKinney = "fine_kinney"
    case matrix5x5  = "matrix_5x5"

    var domain: RiskMethod {
        switch self {
        case .fineKinney: return .fineKinney
        case .matrix5x5:  return .matrix5x5
        }
    }
}
