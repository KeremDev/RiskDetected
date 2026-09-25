import Foundation
import OSLog
import Supabase

@MainActor
final class OnboardingAnswersService {
    static let shared = OnboardingAnswersService()

    private static let pendingDraftKey = "rd.onboarding.v2.pendingAnswers"
    private static let logger = Logger(
        subsystem: "com.riskdetected.app",
        category: "OnboardingAnswersService"
    )

    private let defaults: UserDefaults
    private let supabase: SupabaseService
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        supabase: SupabaseService = .shared
    ) {
        self.defaults = defaults
        self.supabase = supabase
    }

    func savePendingDraft(_ draft: OnboardingAnswersDraft) {
        guard draft.hasProfileAnswers else {
            clearPendingDraft()
            return
        }

        do {
            let data = try encoder.encode(draft)
            defaults.set(data, forKey: Self.pendingDraftKey)
        } catch {
            Self.logger.error("Failed to encode onboarding draft: \(error.localizedDescription, privacy: .public)")
        }
    }

    func pendingDraft() -> OnboardingAnswersDraft? {
        guard let data = defaults.data(forKey: Self.pendingDraftKey) else {
            return nil
        }

        do {
            return try decoder.decode(OnboardingAnswersDraft.self, from: data)
        } catch {
            Self.logger.error("Failed to decode onboarding draft: \(error.localizedDescription, privacy: .public)")
            defaults.removeObject(forKey: Self.pendingDraftKey)
            return nil
        }
    }

    func clearPendingDraft() {
        defaults.removeObject(forKey: Self.pendingDraftKey)
    }

    @discardableResult
    func syncPendingDraftIfPossible() async -> Bool {
        guard let draft = pendingDraft() else {
            return true
        }

        guard RDGlobalLocalizationBuildGate.isEnabled
                || draft.appLanguage != RDLanguage.english.rawValue
        else {
            return false
        }

        guard draft.hasProfileAnswers else {
            clearPendingDraft()
            return true
        }

        guard supabase.currentUserID != nil else {
            return false
        }

        do {
            try await upsert(draft)
            clearPendingDraft()
            return true
        } catch {
            Self.logger.error("Failed to sync onboarding draft: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The name typed in the Nova funnel ("Sana nasıl hitap edelim?") becomes the profile name while
    /// the profile still has none, or only the default the signup trigger takes from the address.
    /// A name from Apple or Google, or one set on the profile, stays. Never fails the answer sync.
    private func adoptOnboardingName(_ name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let userID = supabase.currentUserID else { return }
        struct ProfileName: Decodable {
            let email: String?
            let full_name: String?
        }
        struct NameUpdate: Encodable {
            let full_name: String
        }
        do {
            let profile: ProfileName = try await supabase.client
                .from("profiles")
                .select("email, full_name")
                .eq("id", value: userID.uuidString)
                .single()
                .execute()
                .value
            let current = (profile.full_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let fromAddress = (profile.email ?? "").split(separator: "@").first.map(String.init) ?? ""
            guard current.isEmpty || current == fromAddress, current != name else { return }
            try await supabase.client
                .from("profiles")
                .update(NameUpdate(full_name: name))
                .eq("id", value: userID.uuidString)
                .execute()
        } catch {
            Self.logger.error("Failed to adopt onboarding name: \(error.localizedDescription, privacy: .public)")
        }
    }

    func upsert(_ draft: OnboardingAnswersDraft) async throws {
        guard RDGlobalLocalizationBuildGate.isEnabled
                || draft.appLanguage != RDLanguage.english.rawValue
        else {
            throw NSError(
                domain: "RiskDetected.GlobalLocalizationBuildGate",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Global localization is disabled for this build."
                ]
            )
        }

        try await supabase.client
            .rpc("upsert_onboarding_v2_answers", params: draft.rpcPayload)
            .execute()

        if let name = draft.nova?.name { await adoptOnboardingName(name) }

        guard
            draft.appLanguage == RDLanguage.english.rawValue,
            let profileRaw = draft.safetyProfileID,
            let profileID = RDSafetyProfileID(rawValue: profileRaw),
            let userID = supabase.currentUserID
        else {
            return
        }

        let definition = RDSafetyProfileCatalog.profile(id: profileID)
        struct LocalizationPayload: Encodable {
            let app_language: String
            let preferred_content_locale: String
            let work_jurisdiction_country: String
            let safety_profile_id: String
            let safety_profile_version: Int
            let legal_document_set: String
            let title: String?
        }

        try await supabase.client
            .from("profiles")
            .update(
                LocalizationPayload(
                    app_language: RDAppLanguage.english.rawValue,
                    preferred_content_locale: definition.contentLocale.rawValue,
                    work_jurisdiction_country: definition.jurisdictionCountry.rawValue,
                    safety_profile_id: definition.id.rawValue,
                    safety_profile_version: definition.profileVersion,
                    legal_document_set: RDLegalDocumentSetID.englishGlobalV1.rawValue,
                    title: draft.professionalRole?.label
                )
            )
            .eq("id", value: userID.uuidString)
            .execute()
    }
}
