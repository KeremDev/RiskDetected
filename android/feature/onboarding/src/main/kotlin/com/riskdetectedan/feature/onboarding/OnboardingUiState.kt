package com.riskdetectedan.feature.onboarding

import com.riskdetectedan.core.data.onboarding.OnboardingAnswerChoice
import com.riskdetectedan.core.data.onboarding.OnboardingAnswersDraft
import com.riskdetectedan.core.data.onboarding.OnboardingCertificate
import com.riskdetectedan.core.data.onboarding.OnboardingFrequency
import com.riskdetectedan.core.data.onboarding.OnboardingHazardClass
import com.riskdetectedan.core.data.onboarding.OnboardingPlan
import com.riskdetectedan.core.data.onboarding.OnboardingSector
import com.riskdetectedan.core.data.onboarding.OnboardingProfessionalRole
import com.riskdetectedan.core.data.onboarding.OnboardingSafetyProfile
import com.riskdetectedan.core.common.RdClientMetadata

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
    val professionalRole: OnboardingProfessionalRole? = null,
    val safetyProfile: OnboardingSafetyProfile? = null,
    val sectors: List<OnboardingSector> = emptyList(),
    val frequency: OnboardingFrequency? = null,
    val selectedPlan: OnboardingPlan = OnboardingPlan.Yearly,
) {
    fun toAnswersDraft(): OnboardingAnswersDraft = OnboardingAnswersDraft(
        certificateClass = certificate
            ?.takeIf { RdClientMetadata.APP_LANGUAGE == "tr" }
            ?.let { OnboardingAnswerChoice(it.id, it.label) },
        hazardClasses = OnboardingHazardClass.entries
            .filter { hazards.contains(it) }
            .takeIf { RdClientMetadata.APP_LANGUAGE == "tr" }
            .orEmpty()
            .map { OnboardingAnswerChoice(it.id, it.label) },
        sectors = sectors.map { OnboardingAnswerChoice(it.id, it.wireLabel()) },
        auditFrequency = frequency?.let { OnboardingAnswerChoice(it.id, it.wireTitle()) },
        selectedPlan = OnboardingAnswerChoice(selectedPlan.id, selectedPlan.wireLabel()),
        professionalRole = professionalRole?.let { OnboardingAnswerChoice(it.id, it.wireLabel()) },
        safetyProfileId = safetyProfile?.id ?: RdClientMetadata.SAFETY_PROFILE_ID,
        appLanguage = RdClientMetadata.APP_LANGUAGE,
    )

    companion object {
        fun fromAnswersDraft(draft: OnboardingAnswersDraft): OnboardingUiState = OnboardingUiState(
            certificate = OnboardingCertificate.entries.firstOrNull {
                it.id == draft.certificateClass?.value
            },
            hazards = OnboardingHazardClass.entries.filterTo(linkedSetOf()) { hazard ->
                draft.hazardClasses.any { it.value == hazard.id }
            },
            professionalRole = OnboardingProfessionalRole.entries.firstOrNull {
                it.id == draft.professionalRole?.value
            },
            safetyProfile = OnboardingSafetyProfile.entries.firstOrNull {
                it.id == draft.safetyProfileId
            },
            sectors = draft.sectors.mapNotNull { answer ->
                OnboardingSector.entries.firstOrNull { it.id == answer.value }
            },
            frequency = OnboardingFrequency.entries.firstOrNull {
                it.id == draft.auditFrequency?.value
            },
            selectedPlan = OnboardingPlan.entries.firstOrNull {
                it.id == draft.selectedPlan?.value
            } ?: OnboardingPlan.Yearly,
        )
    }
}

private fun OnboardingProfessionalRole.wireLabel(): String = when (this) {
    OnboardingProfessionalRole.SafetyProfessional -> "Safety professional"
    OnboardingProfessionalRole.SafetyManager -> "HSE/OHS/WHS manager"
    OnboardingProfessionalRole.SiteManager -> "Site manager"
    OnboardingProfessionalRole.Engineer -> "Engineer"
    OnboardingProfessionalRole.Supervisor -> "Supervisor"
    OnboardingProfessionalRole.Consultant -> "Consultant"
    OnboardingProfessionalRole.EmployerOwner -> "Employer/Owner"
    OnboardingProfessionalRole.Other -> "Other"
}

private fun OnboardingSector.wireLabel(): String {
    if (RdClientMetadata.APP_LANGUAGE != "en") return label
    return when (this) {
        OnboardingSector.Construction -> "Construction"
        OnboardingSector.Manufacturing -> "Manufacturing / Factory"
        OnboardingSector.Energy -> "Energy"
        OnboardingSector.Mining -> "Mining"
        OnboardingSector.Office -> "Office"
        OnboardingSector.LogisticsWarehouse -> "Warehouse / Logistics"
        OnboardingSector.ChemicalLaboratory -> "Chemicals / Laboratory"
        OnboardingSector.Healthcare -> "Healthcare / Hospital"
        OnboardingSector.FoodProduction -> "Food Production"
        OnboardingSector.AgricultureLivestock -> "Agriculture / Livestock"
        OnboardingSector.Retail -> "Retail / Store"
        OnboardingSector.MunicipalFieldServices -> "Municipal / Public Field Services"
        OnboardingSector.Education -> "Educational Institution"
        OnboardingSector.Hospitality -> "Hotel / Hospitality"
        OnboardingSector.Other -> "Other"
    }
}

private fun OnboardingFrequency.wireTitle(): String {
    if (RdClientMetadata.APP_LANGUAGE != "en") return title
    return when (this) {
        OnboardingFrequency.One -> "Single focus"
        OnboardingFrequency.TwoToFive -> "Standard volume"
        OnboardingFrequency.SixToFifteen -> "High volume"
        OnboardingFrequency.FifteenPlus -> "Intensive fieldwork"
    }
}

private fun OnboardingPlan.wireLabel(): String {
    if (RdClientMetadata.APP_LANGUAGE != "en") return label
    return when (this) {
        OnboardingPlan.Yearly -> "Annual"
        OnboardingPlan.Monthly -> "Monthly"
    }
}
