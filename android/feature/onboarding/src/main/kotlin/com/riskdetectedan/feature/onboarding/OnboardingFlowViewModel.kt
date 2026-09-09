package com.riskdetectedan.feature.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.AnalysisSectorPreferences
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.onboarding.OnboardingAnswersRepository
import com.riskdetectedan.core.data.onboarding.OnboardingCertificate
import com.riskdetectedan.core.data.onboarding.OnboardingFrequency
import com.riskdetectedan.core.data.onboarding.OnboardingHazardClass
import com.riskdetectedan.core.data.onboarding.OnboardingPlan
import com.riskdetectedan.core.data.onboarding.OnboardingSector
import com.riskdetectedan.core.data.onboarding.OnboardingProfessionalRole
import com.riskdetectedan.core.data.onboarding.OnboardingSafetyProfile
import com.riskdetectedan.core.data.profile.ProfileRepository
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.common.RdResult
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Mirrors OnboardingV2State.swift's step/answer state + next()/back()/goTo(). Deliberately
 * simplified vs iOS only at the rendering layer: every profile-affecting answer is persisted
 * locally and replayed after authentication, matching the live pending-draft behavior.
 */
@HiltViewModel
class OnboardingFlowViewModel @Inject constructor(
    private val answersRepository: OnboardingAnswersRepository,
    private val sectorPreferences: AnalysisSectorPreferences,
    private val authRepository: AuthRepository,
    private val profileRepository: ProfileRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(OnboardingUiState())
    val uiState: StateFlow<OnboardingUiState> = _uiState.asStateFlow()
    private var isResolvingPostAuth = false

    init {
        answersRepository.loadPending()?.let { pending ->
            _uiState.value = OnboardingUiState.fromAnswersDraft(pending)
        }
    }

    fun next() {
        _uiState.value = _uiState.value.copy(step = _uiState.value.step + 1)
    }

    fun back() {
        _uiState.value = _uiState.value.copy(step = maxOf(0, _uiState.value.step - 1))
    }

    fun goTo(step: Int) {
        _uiState.value = _uiState.value.copy(step = step)
    }

    fun setCertificate(value: OnboardingCertificate) {
        _uiState.value = _uiState.value.copy(certificate = value)
        persistDraft()
    }

    fun toggleHazard(value: OnboardingHazardClass) {
        val current = _uiState.value.hazards
        _uiState.value = _uiState.value.copy(
            hazards = if (current.contains(value)) current - value else current + value,
        )
        persistDraft()
    }

    fun setProfessionalRole(value: OnboardingProfessionalRole) {
        _uiState.value = _uiState.value.copy(professionalRole = value)
        persistDraft()
    }

    fun setSafetyProfile(value: OnboardingSafetyProfile) {
        _uiState.value = _uiState.value.copy(safetyProfile = value)
        persistDraft()
    }

    fun toggleSector(value: OnboardingSector) {
        val current = _uiState.value.sectors
        _uiState.value = _uiState.value.copy(
            sectors = if (current.contains(value)) current - value else current + value,
        )
        persistDraft()
    }

    fun setFrequency(value: OnboardingFrequency) {
        _uiState.value = _uiState.value.copy(frequency = value)
        persistDraft()
    }

    fun setPlan(value: OnboardingPlan) {
        _uiState.value = _uiState.value.copy(selectedPlan = value)
        persistDraft()
    }

    /** Called once auth succeeds (step 8 -> 9) — mirrors syncPendingDraftIfPossible's
     * "requires a session" guard. Also lands the
     * chosen sectors in [AnalysisSectorPreferences] (real port of `savePendingDraft`'s
     * side effect — this local copy is exactly what `AnalysisSectorPreferences.
     * onboardingSectors()`/the Home-embedded sector-picker sheet reads back later, matching
     * iOS's own local-cache-only round trip, not a server fetch). */
    internal fun submitAnswersAfterAuth(onResolved: (PostAuthDestination) -> Unit) {
        if (isResolvingPostAuth) return
        isResolvingPostAuth = true
        persistDraft()
        val sectorIds = _uiState.value.sectors.mapNotNull { AnalysisSector.fromId(it.id)?.id }
        if (sectorIds.isNotEmpty()) sectorPreferences.saveOnboardingSectors(sectorIds)
        viewModelScope.launch {
            answersRepository.syncPending()
            val userId = authRepository.currentUserId
            val tier = userId?.let {
                (profileRepository.fetchProfile(it) as? RdResult.Success)?.value?.tier
            }
            isResolvingPostAuth = false
            onResolved(PostAuthReducer.destination(tier))
        }
    }

    fun clearPendingDraft() {
        answersRepository.clearPending()
        _uiState.value = OnboardingUiState()
    }

    private fun persistDraft() {
        answersRepository.savePending(_uiState.value.toAnswersDraft())
    }
}

internal enum class PostAuthDestination { Finish, TrialInvite }

/** Existing Plus/Pro users skip trial invitation, notification prompt and paywall like iOS. */
internal object PostAuthReducer {
    fun destination(tier: SubscriptionTier?): PostAuthDestination =
        if (tier?.isPaid == true) PostAuthDestination.Finish else PostAuthDestination.TrialInvite
}
