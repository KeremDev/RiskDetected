import Foundation

struct OnboardingAnswerChoice: Codable, Equatable {
    let value: String
    let label: String
}

/// Every answer of the Nova funnel, kept whole in `raw_answers.nova`: the server's answer columns
/// only cover the V2 questions. Single and multiple choices keep their Nova value and label; a
/// "Diğer" choice carries the text the user wrote as its label.
struct OnboardingNovaAnswers: Codable, Equatable {
    var flow = "nova-v1"
    let name: String?
    let certificate: OnboardingAnswerChoice?
    let work: OnboardingAnswerChoice?
    let role: OnboardingAnswerChoice?
    let experience: OnboardingAnswerChoice?
    let sectors: [OnboardingAnswerChoice]
    let trainings: [OnboardingAnswerChoice]
    let approach: [OnboardingAnswerChoice]
    let inspections: Int
    let growth: [OnboardingAnswerChoice]
    let assist: [OnboardingAnswerChoice]
    /// Question ids the user skipped.
    let skipped: [String]
    /// The optional updates box on the mail signup page; nil when that page was not used.
    let marketingEmailOptIn: Bool?

    enum CodingKeys: String, CodingKey {
        case flow, name, certificate, work, role, experience, sectors, trainings, approach
        case inspections, growth, assist, skipped
        case marketingEmailOptIn = "marketing_email_opt_in"
    }
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
    /// Nova funnel only; drafts saved before it existed decode it as nil.
    let nova: OnboardingNovaAnswers?

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
        capturedAt: String = ISO8601DateFormatter().string(from: Date()),
        nova: OnboardingNovaAnswers? = nil
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
        self.nova = nova
    }

    var hasProfileAnswers: Bool {
        certificateClass != nil ||
            !hazardClasses.isEmpty ||
            professionalRole != nil ||
            safetyProfileID != nil ||
            !sectors.isEmpty ||
            auditFrequency != nil ||
            nova != nil
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
                selectedPlan: selectedPlan,
                nova: nova
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
    let nova: OnboardingNovaAnswers?

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
        case nova
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
