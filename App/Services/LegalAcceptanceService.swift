import Foundation
import UIKit

@MainActor
final class LegalAcceptanceService {
    static let shared = LegalAcceptanceService()

    static let kvkkVersion = "kvkk-2026-05-06"
    static let termsVersion = "terms-2026-05-06"
    static let aiProcessingVersion = "ai-photo-text-processing-2026-05-06"

    private let supabase = SupabaseService.shared
    private var recordedUsers = Set<UUID>()
    private var recordingUsers = Set<UUID>()

    private init() {}

    func recordLoginNoticeAcceptanceIfNeeded(userID: UUID) async {
        guard !recordedUsers.contains(userID), !recordingUsers.contains(userID) else { return }
        recordingUsers.insert(userID)
        defer { recordingUsers.remove(userID) }

        do {
            let existing: [LegalAcceptanceRow] = try await supabase.client
                .from("consents")
                .select("id,user_id,kvkk_version,terms_version,explicit_consent_version,accepted_at")
                .eq("user_id", value: userID.uuidString)
                .eq("kvkk_version", value: Self.kvkkVersion)
                .eq("terms_version", value: Self.termsVersion)
                .eq("explicit_consent_version", value: Self.aiProcessingVersion)
                .limit(1)
                .execute()
                .value

            if !existing.isEmpty {
                recordedUsers.insert(userID)
                return
            }

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
                explicit_consent_version: Self.aiProcessingVersion,
                source: "login_notice",
                app_version: Self.appVersion,
                device_id: UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
            )

            try await supabase.client
                .from("consents")
                .insert(payload)
                .execute()

            recordedUsers.insert(userID)
        } catch {
            // Legal audit logging must never block login or analysis. The notice stays visible
            // in the UI; a later session can retry the background record.
        }
    }

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return [version, build].compactMap { $0 }.joined(separator: " ")
    }
}

private struct LegalAcceptanceRow: Codable, Identifiable {
    let id: UUID
    let userID: UUID
    let kvkkVersion: String
    let termsVersion: String
    let explicitConsentVersion: String
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
