import Foundation

struct OnboardingAnswerChoice: Codable, Equatable {
    let value: String
    let label: String
}

struct OnboardingAnswersDraft: Codable, Equatable {
    let onboardingVersion: String
    let certificateClass: OnboardingAnswerChoice?
    let hazardClasses: [OnboardingAnswerChoice]
    let professionalRole: OnboardingAnswerChoice?
    let safetyProfileID: String?
    let appLanguage: String
    let sectors: [OnboardingAnswerChoice]
    let auditFrequency: OnboardingAnswerChoice?
    let selectedPlan: OnboardingAnswerChoice?
    let capturedAt: String

    init(
        onboardingVersion: String = "v2",
        certificateClass: OnboardingAnswerChoice?,
        hazardClasses: [OnboardingAnswerChoice],
        professionalRole: OnboardingAnswerChoice? = nil,
        safetyProfileID: String? = nil,
        appLanguage: String = RDLanguage.current.rawValue,
        sectors: [OnboardingAnswerChoice],
        auditFrequency: OnboardingAnswerChoice?,
        selectedPlan: OnboardingAnswerChoice?,
        capturedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.onboardingVersion = onboardingVersion
        self.certificateClass = certificateClass
        self.hazardClasses = hazardClasses
        self.professionalRole = professionalRole
        self.safetyProfileID = safetyProfileID
        self.appLanguage = appLanguage
        self.sectors = sectors
        self.auditFrequency = auditFrequency
        self.selectedPlan = selectedPlan
        self.capturedAt = capturedAt
    }

    var hasProfileAnswers: Bool {
        certificateClass != nil ||
            !hazardClasses.isEmpty ||
            professionalRole != nil ||
            safetyProfileID != nil ||
            !sectors.isEmpty ||
            auditFrequency != nil
    }

    var rpcPayload: OnboardingAnswersRPCPayload {
        OnboardingAnswersRPCPayload(
            onboardingVersion: onboardingVersion,
            certificateClass: certificateClass?.value,
            hazardClasses: hazardClasses.map(\.value),
            sectors: sectors.map(\.value),
            auditFrequency: auditFrequency?.value,
            selectedPlan: selectedPlan?.value,
            rawAnswers: OnboardingAnswersRawPayload(
                capturedAt: capturedAt,
                certificateClass: certificateClass,
                hazardClasses: hazardClasses,
                professionalRole: professionalRole,
                safetyProfileID: safetyProfileID,
                appLanguage: appLanguage,
                sectors: sectors,
                auditFrequency: auditFrequency,
                selectedPlan: selectedPlan
            )
        )
    }
}

struct OnboardingAnswersRawPayload: Codable, Equatable {
    let capturedAt: String
    let certificateClass: OnboardingAnswerChoice?
    let hazardClasses: [OnboardingAnswerChoice]
    let professionalRole: OnboardingAnswerChoice?
    let safetyProfileID: String?
    let appLanguage: String
    let sectors: [OnboardingAnswerChoice]
    let auditFrequency: OnboardingAnswerChoice?
    let selectedPlan: OnboardingAnswerChoice?

    enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
        case certificateClass = "certificate_class"
        case hazardClasses = "hazard_classes"
        case professionalRole = "professional_role"
        case safetyProfileID = "safety_profile_id"
        case appLanguage = "app_language"
        case sectors
        case auditFrequency = "audit_frequency"
        case selectedPlan = "selected_plan"
    }
}

struct OnboardingAnswersRPCPayload: Encodable {
    let onboardingVersion: String
    let certificateClass: String?
    let hazardClasses: [String]
    let sectors: [String]
    let auditFrequency: String?
    let selectedPlan: String?
    let rawAnswers: OnboardingAnswersRawPayload

    enum CodingKeys: String, CodingKey {
        case onboardingVersion = "p_onboarding_version"
        case certificateClass = "p_certificate_class"
        case hazardClasses = "p_hazard_classes"
        case sectors = "p_sectors"
        case auditFrequency = "p_audit_frequency"
        case selectedPlan = "p_selected_plan"
        case rawAnswers = "p_raw_answers"
    }
}
