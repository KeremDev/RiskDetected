package com.riskdetectedan.feature.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.AnalysisSectorPreferences
import com.riskdetectedan.core.data.onboarding.OnboardingAnswersRepository
import com.riskdetectedan.core.data.onboarding.OnboardingCertificate
import com.riskdetectedan.core.data.onboarding.OnboardingFrequency
import com.riskdetectedan.core.data.onboarding.OnboardingHazardClass
import com.riskdetectedan.core.data.onboarding.OnboardingPlan
import com.riskdetectedan.core.data.onboarding.OnboardingSector
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Mirrors OnboardingV2State.swift's step/answer state + next()/back()/goTo(). Deliberately
 * simplified vs iOS: no spring animation config (that's a SwiftUI-transition concern, not
 * state), no local pending-draft persistence (see OnboardingAnswersRepository's doc comment —
 * this submits once, at step 8->9 transition, after auth exists — rather than iOS's
 * persist-on-every-change + replay-on-reconnect).
 */
@HiltViewModel
class OnboardingFlowViewModel @Inject constructor(
    private val answersRepository: OnboardingAnswersRepository,
    private val sectorPreferences: AnalysisSectorPreferences,
) : ViewModel() {

    private val _uiState = MutableStateFlow(OnboardingUiState())
    val uiState: StateFlow<OnboardingUiState> = _uiState.asStateFlow()

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
    }

    fun toggleHazard(value: OnboardingHazardClass) {
        val current = _uiState.value.hazards
        _uiState.value = _uiState.value.copy(
            hazards = if (current.contains(value)) current - value else current + value,
        )
    }

    fun toggleSector(value: OnboardingSector) {
        val current = _uiState.value.sectors
        _uiState.value = _uiState.value.copy(
            sectors = if (current.contains(value)) current - value else current + value,
        )
    }

    fun setFrequency(value: OnboardingFrequency) {
        _uiState.value = _uiState.value.copy(frequency = value)
    }

    fun setPlan(value: OnboardingPlan) {
        _uiState.value = _uiState.value.copy(selectedPlan = value)
    }

    /** Called once auth succeeds (step 8 -> 9) — mirrors syncPendingDraftIfPossible's
     * "requires a session" guard, just without the local-cache replay path. Also lands the
     * chosen sectors in [AnalysisSectorPreferences] (real port of `savePendingDraft`'s
     * side effect — this local copy is exactly what `AnalysisSectorPreferences.
     * onboardingSectors()`/the Home-embedded sector-picker sheet reads back later, matching
     * iOS's own local-cache-only round trip, not a server fetch). */
    fun submitAnswersAfterAuth() {
        val sectorIds = _uiState.value.sectors.mapNotNull { AnalysisSector.fromId(it.id)?.id }
        if (sectorIds.isNotEmpty()) sectorPreferences.saveOnboardingSectors(sectorIds)
        viewModelScope.launch {
            answersRepository.upsert(_uiState.value.toAnswersDraft())
        }
    }
}
