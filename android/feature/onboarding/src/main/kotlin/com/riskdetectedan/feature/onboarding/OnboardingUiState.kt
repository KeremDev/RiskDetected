package com.riskdetectedan.feature.onboarding

import com.riskdetectedan.core.data.onboarding.OnboardingAnswerChoice
import com.riskdetectedan.core.data.onboarding.OnboardingAnswersDraft
import com.riskdetectedan.core.data.onboarding.OnboardingCertificate
import com.riskdetectedan.core.data.onboarding.OnboardingFrequency
import com.riskdetectedan.core.data.onboarding.OnboardingHazardClass
import com.riskdetectedan.core.data.onboarding.OnboardingPlan
import com.riskdetectedan.core.data.onboarding.OnboardingSector

/**
 * Kotlin mirror of OnboardingV2State.swift's Turkish-path fields (professionalRole/
 * safetyProfileID are the English-branch fields — not carried here, see OnboardingChoices.kt's
 * doc comment). `step` mirrors the exact 0-11 sequence from OnboardingViewV2.swift's `switch
 * state.step` (Turkish branch): 0 splash, 1 painPoint, 2 certificate, 3 hazardClass, 4 sector,
 * 5 frequency, 6 loading, 7 planSummary, 8 auth, 9 trialInvite, 10 notificationPermission,
 * 11 paywall.
 */
data class OnboardingUiState(
    val step: Int = 0,
    val certificate: OnboardingCertificate? = null,
    val hazards: Set<OnboardingHazardClass> = emptySet(),
    val sectors: List<OnboardingSector> = emptyList(),
    val frequency: OnboardingFrequency? = null,
    val selectedPlan: OnboardingPlan = OnboardingPlan.Yearly,
) {
    fun toAnswersDraft(): OnboardingAnswersDraft = OnboardingAnswersDraft(
        certificateClass = certificate?.let { OnboardingAnswerChoice(it.id, it.label) },
        hazardClasses = OnboardingHazardClass.entries
            .filter { hazards.contains(it) }
            .map { OnboardingAnswerChoice(it.id, it.label) },
        sectors = sectors.map { OnboardingAnswerChoice(it.id, it.label) },
        auditFrequency = frequency?.let { OnboardingAnswerChoice(it.id, it.title) },
        selectedPlan = OnboardingAnswerChoice(selectedPlan.id, selectedPlan.label),
    )
}
