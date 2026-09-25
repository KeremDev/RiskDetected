package com.riskdetectedan.core.data.onboarding

import com.riskdetectedan.core.common.RdClientMetadata
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Kotlin mirror of App/Models/OnboardingAnswers.swift's OnboardingAnswerChoice. */
@Serializable
data class OnboardingAnswerChoice(val value: String, val label: String)

/**
 * Kotlin mirror of App/Models/OnboardingAnswers.swift's OnboardingNovaAnswers: every answer of the
 * Nova funnel, kept whole in `raw_answers.nova`, because the server's answer columns only cover the
 * V2 questions. Choices keep their Nova value and label; a "Diğer" choice carries the text the user
 * wrote as its label. No defaults, so every field is sent.
 */
@Serializable
data class OnboardingNovaAnswers(
    val flow: String,
    val name: String?,
    val certificate: OnboardingAnswerChoice?,
    val work: OnboardingAnswerChoice?,
    val role: OnboardingAnswerChoice?,
    val experience: OnboardingAnswerChoice?,
    val sectors: List<OnboardingAnswerChoice>,
    val trainings: List<OnboardingAnswerChoice>,
    val approach: List<OnboardingAnswerChoice>,
    val inspections: Int,
    val growth: List<OnboardingAnswerChoice>,
    val assist: List<OnboardingAnswerChoice>,
    /** Question ids the user skipped. */
    val skipped: List<String>,
    /** The optional updates box on the mail signup page; null when that page was not used. */
    @SerialName("marketing_email_opt_in") val marketingEmailOptIn: Boolean?,
)

/**
 * Kotlin mirror of App/Models/OnboardingAnswers.swift's OnboardingAnswersDraft — same fields,
 * same defaults (onboardingVersion "v2"). Locale and safety-profile defaults are resolved from
 * the active Android locale so onboarding, analysis and reporting use one coherent contract.
 */
@Serializable
data class OnboardingAnswersDraft(
    val onboardingVersion: String = "v2",
    val certificateClass: OnboardingAnswerChoice? = null,
    val hazardClasses: List<OnboardingAnswerChoice> = emptyList(),
    val professionalRole: OnboardingAnswerChoice? = null,
    val safetyProfileId: String? = RdClientMetadata.SAFETY_PROFILE_ID,
    val appLanguage: String = RdClientMetadata.APP_LANGUAGE,
    val sectors: List<OnboardingAnswerChoice> = emptyList(),
    val auditFrequency: OnboardingAnswerChoice? = null,
    val selectedPlan: OnboardingAnswerChoice? = null,
    val capturedAt: String = java.time.Instant.now().toString(),
    /** Nova funnel only; drafts saved before it existed load it as null. */
    val nova: OnboardingNovaAnswers? = null,
) {
    val hasProfileAnswers: Boolean
        get() = certificateClass != null ||
            hazardClasses.isNotEmpty() ||
            professionalRole != null ||
            safetyProfileId != null ||
            sectors.isNotEmpty() ||
            auditFrequency != null ||
            nova != null
}

/** Maps 1:1 to upsert_onboarding_v2_answers' p_* RPC parameters — same names, same shape. */
@Serializable
data class OnboardingAnswersRpcPayload(
    @SerialName("p_onboarding_version") val onboardingVersion: String,
    @SerialName("p_certificate_class") val certificateClass: String?,
    @SerialName("p_hazard_classes") val hazardClasses: List<String>,
    @SerialName("p_sectors") val sectors: List<String>,
    @SerialName("p_audit_frequency") val auditFrequency: String?,
    @SerialName("p_selected_plan") val selectedPlan: String?,
    @SerialName("p_raw_answers") val rawAnswers: OnboardingAnswersRawPayload,
)

@Serializable
data class OnboardingAnswersRawPayload(
    @SerialName("captured_at") val capturedAt: String,
    @SerialName("certificate_class") val certificateClass: RawChoice?,
    @SerialName("hazard_classes") val hazardClasses: List<RawChoice>,
    @SerialName("professional_role") val professionalRole: RawChoice?,
    @SerialName("safety_profile_id") val safetyProfileId: String?,
    @SerialName("app_language") val appLanguage: String,
    val sectors: List<RawChoice>,
    @SerialName("audit_frequency") val auditFrequency: RawChoice?,
    @SerialName("selected_plan") val selectedPlan: RawChoice?,
    /** Left out of the JSON when null (not a Nova draft), so it never clears a stored one. */
    val nova: OnboardingNovaAnswers? = null,
)

@Serializable
data class RawChoice(val value: String, val label: String)

fun OnboardingAnswerChoice.toRaw() = RawChoice(value, label)

fun OnboardingAnswersDraft.toRpcPayload(): OnboardingAnswersRpcPayload = OnboardingAnswersRpcPayload(
    onboardingVersion = onboardingVersion,
    certificateClass = certificateClass?.value,
    hazardClasses = hazardClasses.map { it.value },
    sectors = sectors.map { it.value },
    auditFrequency = auditFrequency?.value,
    selectedPlan = selectedPlan?.value,
    rawAnswers = OnboardingAnswersRawPayload(
        capturedAt = capturedAt,
        certificateClass = certificateClass?.toRaw(),
        hazardClasses = hazardClasses.map { it.toRaw() },
        professionalRole = professionalRole?.toRaw(),
        safetyProfileId = safetyProfileId,
        appLanguage = appLanguage,
        sectors = sectors.map { it.toRaw() },
        auditFrequency = auditFrequency?.toRaw(),
        selectedPlan = selectedPlan?.toRaw(),
        nova = nova,
    ),
)
