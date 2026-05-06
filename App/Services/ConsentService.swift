import Foundation
import UIKit

@MainActor
final class ConsentService {
    static let shared = ConsentService()

    static let kvkkVersion = "kvkk-2026-05-06"
    static let termsVersion = "terms-2026-05-06"
    static let explicitConsentVersion = "ai-photo-processing-2026-05-06"

    private let supabase = SupabaseService.shared
    private var acceptedCache: [UUID: Bool] = [:]

    private init() {}

    func hasRequiredConsent(userID: UUID) async -> Bool {
        if let cached = acceptedCache[userID] {
            return cached
        }

        do {
            let rows: [ConsentRow] = try await supabase.client
                .from("consents")
                .select("id,user_id,kvkk_version,terms_version,explicit_consent_version,accepted_at")
                .eq("user_id", value: userID.uuidString)
                .eq("kvkk_version", value: Self.kvkkVersion)
                .eq("terms_version", value: Self.termsVersion)
                .eq("explicit_consent_version", value: Self.explicitConsentVersion)
                .limit(1)
                .execute()
                .value
            let accepted = !rows.isEmpty
            acceptedCache[userID] = accepted
            return accepted
        } catch {
            acceptedCache[userID] = false
            return false
        }
    }

    func acceptRequiredConsent(userID: UUID, source: String = "first_analysis") async throws {
        struct Payload: Encodable {
            let user_id: String
            let kvkk_version: String
            let terms_version: String
            let explicit_consent_version: String
            let source: String
            let app_version: String
            let device_id: String
        }

        let payload = Payload(
            user_id: userID.uuidString,
            kvkk_version: Self.kvkkVersion,
            terms_version: Self.termsVersion,
            explicit_consent_version: Self.explicitConsentVersion,
            source: source,
            app_version: Self.appVersion,
            device_id: UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        )

        try await supabase.client
            .from("consents")
            .upsert(
                payload,
                onConflict: "user_id,kvkk_version,terms_version,explicit_consent_version",
                ignoreDuplicates: true
            )
            .execute()

        acceptedCache[userID] = true
    }

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return [version, build].compactMap { $0 }.joined(separator: " ")
    }
}

struct ConsentRow: Codable, Identifiable, Equatable {
    let id: UUID
    let userID: UUID
    let kvkkVersion: String
    let termsVersion: String
    let explicitConsentVersion: String?
    let acceptedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case kvkkVersion = "kvkk_version"
        case termsVersion = "terms_version"
        case explicitConsentVersion = "explicit_consent_version"
        case acceptedAt = "accepted_at"
    }
}
