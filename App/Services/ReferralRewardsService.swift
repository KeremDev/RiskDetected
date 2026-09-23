import Foundation
import Supabase

struct ReferralDashboard: Decodable {
    struct Campaign: Decodable {
        let code: String
        let qualificationDays: Int
        let qualificationWindowDays: Int
        let rewardDays: Int
        let doubleSided: Bool

        enum CodingKeys: String, CodingKey {
            case code
            case qualificationDays = "qualification_days"
            case qualificationWindowDays = "qualification_window_days"
            case rewardDays = "reward_days"
            case doubleSided = "double_sided"
        }
    }

    struct Counts: Decodable {
        let invited: Int
        let qualified: Int
        let rewarded: Int
    }

    struct Invite: Decodable, Identifiable {
        let claimID: UUID
        let state: String
        let claimedAt: String
        let qualifiedAt: String?
        let rewardedAt: String?
        let distinctDays: Int?
        let requiredDays: Int?

        var id: UUID { claimID }

        enum CodingKeys: String, CodingKey {
            case claimID = "claim_id"
            case state
            case claimedAt = "claimed_at"
            case qualifiedAt = "qualified_at"
            case rewardedAt = "rewarded_at"
            case distinctDays = "distinct_days"
            case requiredDays = "required_days"
        }
    }

    struct Reward: Decodable, Identifiable {
        let instanceID: UUID
        let state: String
        let earnedAt: String
        let activatedAt: String?
        let expiresAt: String?
        let capability: String?
        let durationHours: Int

        var id: UUID { instanceID }

        enum CodingKeys: String, CodingKey {
            case instanceID = "instance_id"
            case state
            case earnedAt = "earned_at"
            case activatedAt = "activated_at"
            case expiresAt = "expires_at"
            case capability
            case durationHours = "duration_hours"
        }
    }

    let campaign: Campaign
    let referralCode: String
    let shareURL: String
    let shareMessage: String
    let counts: Counts
    let sentInvites: [Invite]
    let acceptedInvites: [Invite]
    let rewards: [Reward]

    enum CodingKeys: String, CodingKey {
        case campaign
        case referralCode = "referral_code"
        case shareURL = "share_url"
        case shareMessage = "share_message"
        case counts
        case sentInvites = "sent_invites"
        case acceptedInvites = "accepted_invites"
        case rewards
    }
}

struct ReferralClaimResult: Decodable {
    let claimID: UUID?
    let state: String
    let replayed: Bool
    let errorCode: String?
    let qualificationDays: Int?
    let qualificationWindowDays: Int?
    let rewardDays: Int?

    enum CodingKeys: String, CodingKey {
        case claimID = "claim_id"
        case state, replayed
        case errorCode = "error_code"
        case qualificationDays = "qualification_days"
        case qualificationWindowDays = "qualification_window_days"
        case rewardDays = "reward_days"
    }
}

struct ReferralActivationResult: Decodable {
    let activated: Bool
    let state: String
    let reason: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case activated, state, reason
        case expiresAt = "expires_at"
    }
}

final class ReferralRewardsService {
    static let shared = ReferralRewardsService()

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
    }

    func dashboard() async throws -> ReferralDashboard {
        try await client
            .rpc("referral_dashboard_v1")
            .execute()
            .value
    }

    func claim(code: String) async throws -> ReferralClaimResult {
        struct Params: Encodable { let p_code: String }
        let result: ReferralClaimResult = try await client
            .rpc("referral_claim_v1", params: Params(p_code: code))
            .execute()
            .value
        if let code = result.errorCode {
            throw ReferralRewardsError.server(code)
        }
        return result
    }

    func activate(instanceID: UUID) async throws -> ReferralActivationResult {
        struct Params: Encodable { let p_instance: UUID }
        return try await client
            .rpc("referral_activate_reward_v1", params: Params(p_instance: instanceID))
            .execute()
            .value
    }

    func track(_ event: String, context: [String: String] = [:]) async {
        struct Params: Encodable {
            let p_event: String
            let p_context: [String: String]
        }
        _ = try? await client
            .rpc("referral_event_v1", params: Params(p_event: event, p_context: context))
            .execute()
    }

    static func userMessage(for error: Error) -> String {
        let value = String(describing: error).uppercased()
        if value.contains("SELF_REFERRAL") {
            return RDLocalization.string("localizable.referral.rewards.service.kendi.davet.kodunu.kullanamazsin.b99bc5be", table: .localizable, fallback: "Kendi davet kodunu kullanamazsın.")
        }
        if value.contains("ALREADY_CLAIMED") {
            return RDLocalization.string("localizable.referral.rewards.service.bu.hesap.daha.once.bir.davet.kodu.kullandi.e591df10", table: .localizable, fallback: "Bu hesap daha önce bir davet kodu kullandı.")
        }
        if value.contains("CYCLE_DETECTED") {
            return RDLocalization.string("localizable.referral.rewards.service.karsilikli.davet.kullanilamaz.5c78bff1", table: .localizable, fallback: "Karşılıklı davet kullanılamaz.")
        }
        if value.contains("INVALID_REFERRAL_CODE") || value.contains("ACCESS_DENIED") {
            return RDLocalization.string("localizable.referral.rewards.service.davet.kodu.bulunamadi.veya.artik.gecerli.degil.b9232929", table: .localizable, fallback: "Davet kodu bulunamadı veya artık geçerli değil.")
        }
        if value.contains("CAMPAIGN_UNAVAILABLE") || value.contains("FEATURE_UNAVAILABLE") {
            return RDLocalization.string("localizable.referral.rewards.service.davet.programi.su.an.kullanilamiyor.biraz.sonra..9f4f7d87", table: .localizable, fallback: "Davet programı şu an kullanılamıyor. Biraz sonra tekrar dene.")
        }
        if value.contains("RATE_LIMITED") {
            return RDLocalization.string("localizable.referral.rewards.service.cok.fazla.kod.denemesi.yapildi.bir.saat.sonra.te.dd652f00", table: .localizable, fallback: "Çok fazla kod denemesi yapıldı. Bir saat sonra tekrar deneyebilirsin.")
        }
        return RDLocalization.string("localizable.referral.rewards.service.islem.tamamlanamadi.internet.baglantini.kontrol..18afe6a6", table: .localizable, fallback: "İşlem tamamlanamadı. İnternet bağlantını kontrol edip tekrar dene.")
    }
}

private enum ReferralRewardsError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case let .server(code): return code
        }
    }
}

final class ReferralDeepLinkStore {
    static let shared = ReferralDeepLinkStore()

    private let defaults = UserDefaults.standard
    private let key = "rd.referral.pendingCode"

    var pendingCode: String? {
        let value = defaults.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard let value, value.range(of: "^[A-Z0-9]{6,12}$", options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    @discardableResult
    func capture(_ url: URL) -> Bool {
        guard url.scheme == "io.supabase.riskdetected", url.host == "invite" else {
            return false
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
              code.range(of: "^[A-Z0-9]{6,12}$", options: .regularExpression) != nil
        else {
            return false
        }
        defaults.set(code, forKey: key)
        return true
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
