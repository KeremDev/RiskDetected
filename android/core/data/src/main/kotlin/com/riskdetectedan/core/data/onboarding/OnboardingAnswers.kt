package com.riskdetectedan.core.data.onboarding

import com.riskdetectedan.core.common.RdClientMetadata
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Kotlin mirror of App/Models/OnboardingAnswers.swift's OnboardingAnswerChoice. */
@Serializable
data class OnboardingAnswerChoice(val value: String, val label: String)

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
) {
    val hasProfileAnswers: Boolean
        get() = certificateClass != null ||
            hazardClasses.isNotEmpty() ||
            professionalRole != null ||
            safetyProfileId != null ||
            sectors.isNotEmpty() ||
            auditFrequency != null
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
    ),
)
