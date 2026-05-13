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
    let phone: String?
    let tier: SubscriptionTier
    let preferredMethod: RiskMethodWire?
    let dailyQuotaUsed: Int?
    let dailyQuotaResetAt: String?
    let subscriptionPeriod: String?
    let subscriptionRenewalAt: String?
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
        case phone
        case tier
        case preferredMethod       = "preferred_method"
        case dailyQuotaUsed        = "daily_quota_used"
        case dailyQuotaResetAt     = "daily_quota_reset_at"
        case subscriptionPeriod    = "subscription_period"
        case subscriptionRenewalAt = "subscription_renewal_at"
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
        return "—"
    }

    var displayName: String {
        fullName ?? email?.split(separator: "@").first.map(String.init) ?? "Kullanıcı"
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
        case .free: return "Free"
        case .plus: return "Plus"
        case .pro: return "Pro"
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

    var isPaid: Bool { tier.isPaid }
    var isPro: Bool { tier == .pro }

    static func forTier(_ tier: SubscriptionTier) -> PlanCapabilities {
        switch tier {
        case .free:
            return PlanCapabilities(
                tier: tier,
                standardAnalysisLabel: "Günde 1 analiz",
                detailedAnalysisLabel: "Yok",
                reportLabel: "3/ay, özelleştirilemez",
                acceleratedReportLabel: "Yok",
                archiveLabel: "7 gün",
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
                standardAnalysisLabel: "15/gün",
                detailedAnalysisLabel: "2/gün",
                reportLabel: "150/ay, logolu",
                acceleratedReportLabel: "50/ay",
                archiveLabel: "30 gün",
                canUseDetailedRiskTable: true,
                canUseEmergencyRisk: true,
                canUseProcedureCheck: false,
                advancedCanvasLabel: "Sınırlı",
                canUseAutomaticDelivery: true,
                canUseTrainedAI: false,
                supportLabel: "E-posta"
            )
        case .pro:
            return PlanCapabilities(
                tier: tier,
                standardAnalysisLabel: "60/gün",
                detailedAnalysisLabel: "10/gün",
                reportLabel: "Sınırsız, logolu",
                acceleratedReportLabel: "250/ay",
                archiveLabel: "Sınırsız",
                canUseDetailedRiskTable: true,
                canUseEmergencyRisk: true,
                canUseProcedureCheck: true,
                advancedCanvasLabel: "Tam",
                canUseAutomaticDelivery: true,
                canUseTrainedAI: true,
                supportLabel: "E-posta + WhatsApp"
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
