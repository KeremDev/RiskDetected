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
    case pro
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
