import Foundation
import OSLog
import UIKit

@MainActor
final class LegalAcceptanceService {
    static let shared = LegalAcceptanceService()
    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "LegalAcceptance")

    nonisolated static let kvkkVersion = "kvkk-2026-06-10"
    nonisolated static let termsVersion = "terms-2026-06-10"
    nonisolated static let aiProcessingVersion = "consent-2026-06-10"

    private let supabase = SupabaseService.shared
    private var recordedUsers = Set<UUID>()
    private var recordingUsers = Set<UUID>()
    private var failedAttempts: [UUID: Int] = [:]
    private var nextRetryAt: [UUID: Date] = [:]

    private init() {}

    func recordLoginNoticeAcceptanceIfNeeded(userID: UUID) async {
        guard !recordedUsers.contains(userID), !recordingUsers.contains(userID) else { return }
        let language = RDLanguage.current
        guard language == .turkish || RDLegalReleaseGate.englishAuthAndPurchaseApproved else {
            return
        }
        guard let audit = RDLegalReleaseGate.acceptanceAuditMetadata(language: language) else {
            Self.logger.error("Consent audit record blocked: legal document-set metadata unavailable.")
            return
        }
        let versions = Self.acceptanceVersions(language: language)
        if let retryAt = nextRetryAt[userID], retryAt > Date() {
            return
        }

        recordingUsers.insert(userID)
        defer { recordingUsers.remove(userID) }

        do {
            let existing: [LegalAcceptanceRow] = try await supabase.client
                .from("consents")
                .select("id,user_id,kvkk_version,terms_version,explicit_consent_version,legal_document_set,legal_locale,legal_set_manifest_checksum,accepted_at")
                .eq("user_id", value: userID.uuidString)
                .eq("kvkk_version", value: versions.kvkk)
                .eq("terms_version", value: versions.terms)
                .eq("explicit_consent_version", value: versions.explicitConsent)
                .eq("legal_document_set", value: audit.documentSetID)
                .eq("legal_locale", value: audit.locale)
                .eq("legal_set_manifest_checksum", value: audit.manifestChecksum)
                .limit(1)
                .execute()
                .value

            if !existing.isEmpty {
                failedAttempts[userID] = nil
                nextRetryAt[userID] = nil
                recordedUsers.insert(userID)
                return
            }

            struct Payload: Encodable {
                let user_id: String
                let kvkk_version: String
                let terms_version: String
                let explicit_consent_version: String
                let legal_document_set: String
                let legal_locale: String
                let legal_set_manifest_checksum: String
                let source: String
                let app_version: String
                let device_id: String
            }

            let payload = Payload(
                user_id: userID.uuidString,
                kvkk_version: versions.kvkk,
                terms_version: versions.terms,
                explicit_consent_version: versions.explicitConsent,
                legal_document_set: audit.documentSetID,
                legal_locale: audit.locale,
                legal_set_manifest_checksum: audit.manifestChecksum,
                source: "login_notice",
                app_version: Self.appVersion,
                device_id: UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
            )

            try await supabase.client
                .from("consents")
                .insert(payload)
                .execute()

            failedAttempts[userID] = nil
            nextRetryAt[userID] = nil
            recordedUsers.insert(userID)
        } catch {
            // Legal audit logging must never block login or analysis. The notice stays visible
            // in the UI; a later session can retry the background record. We still log and
            // back off so audit issues do not silently disappear during testing/operations.
            let attempts = (failedAttempts[userID] ?? 0) + 1
            failedAttempts[userID] = attempts
            let retryDelay = min(pow(2.0, Double(attempts)), 300)
            nextRetryAt[userID] = Date().addingTimeInterval(retryDelay)
            Self.logger.error("Consent audit record failed. user=\(userID.uuidString, privacy: .private(mask: .hash)) attempt=\(attempts) retryDelay=\(retryDelay, format: .fixed(precision: 0))s error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return [version, build].compactMap { $0 }.joined(separator: " ")
    }

    private static func acceptanceVersions(
        language: RDLanguage
    ) -> (kvkk: String, terms: String, explicitConsent: String) {
        guard language == .english else {
            return (kvkkVersion, termsVersion, aiProcessingVersion)
        }
        return (
            "not-applicable-en-global-v1",
            LegalDocumentService.shared.document(for: .terms).version,
            LegalDocumentService.shared.document(for: .consent).version
        )
    }
}

private struct LegalAcceptanceRow: Codable, Identifiable {
    let id: UUID
    let userID: UUID
    let kvkkVersion: String
    let termsVersion: String
    let explicitConsentVersion: String
    let legalDocumentSet: String?
    let legalLocale: String?
    let legalSetManifestChecksum: String?
    let acceptedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case kvkkVersion = "kvkk_version"
        case termsVersion = "terms_version"
        case explicitConsentVersion = "explicit_consent_version"
        case legalDocumentSet = "legal_document_set"
        case legalLocale = "legal_locale"
        case legalSetManifestChecksum = "legal_set_manifest_checksum"
        case acceptedAt = "accepted_at"
    }
}
