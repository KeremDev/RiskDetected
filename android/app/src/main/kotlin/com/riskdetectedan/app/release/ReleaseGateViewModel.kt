package com.riskdetectedan.app.release

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.legal.LegalAcceptanceRepository
import com.riskdetectedan.core.data.release.AndroidLegalPolicy
import com.riskdetectedan.core.data.release.AppReleasePolicy
import com.riskdetectedan.core.data.release.ReleasePolicySnapshot
import com.riskdetectedan.core.data.release.ReleasePolicyRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface ReleaseGateState {
    data object Clear : ReleaseGateState
    data class Hard(val policy: AppReleasePolicy) : ReleaseGateState
    data class Soft(val policy: AppReleasePolicy) : ReleaseGateState
    data class Legal(
        val policy: AndroidLegalPolicy,
        val isSubmitting: Boolean = false,
        val errorCode: String? = null,
    ) : ReleaseGateState
    data class LegalDocumentsOutdated(val policy: AndroidLegalPolicy) : ReleaseGateState
}

/**
 * Mirrors AppState.swift's release-policy sequence exactly: apply a cached hard-update
 * requirement synchronously first (so a killed-process relaunch with no network still blocks
 * immediately, never a one-frame flash of the real app before the gate catches up), then refresh
 * from `app-release-policy` and re-derive hard/soft/none from the live response. A failed
 * refresh falls back to re-checking the cache rather than clearing it — the whole point of
 * caching a hard requirement is that a network hiccup can't be used to bypass it.
 */
@HiltViewModel
class ReleaseGateViewModel @Inject constructor(
    private val repository: ReleasePolicyRepository,
    private val environmentConfig: RdEnvironmentConfig,
    private val authRepository: AuthRepository,
    private val legalAcceptanceRepository: LegalAcceptanceRepository,
) : ViewModel() {

    private val currentBuild = environmentConfig.appVersionCode

    private val _state = MutableStateFlow<ReleaseGateState>(ReleaseGateState.Clear)
    val state: StateFlow<ReleaseGateState> = _state.asStateFlow()
    private var currentUserId: String? = null

    init {
        applyCachedHardPolicyIfNeeded()
        viewModelScope.launch {
            authRepository.awaitInitialization()
            authRepository.currentUserIdFlow.collectLatest { userId ->
                currentUserId = userId
                refresh(userId)
            }
        }
    }

    private fun applyCachedHardPolicyIfNeeded() {
        val cached = repository.cachedHardPolicy() ?: return
        if (cached.requiresHardUpdate(currentBuild)) {
            _state.value = ReleaseGateState.Hard(cached)
        }
    }

    fun refresh(userId: String? = currentUserId) {
        viewModelScope.launch {
            when (val result = repository.fetchReleasePolicy(userId)) {
                is RdResult.Success -> applySnapshot(result.value, userId)
                is RdResult.Failure -> {
                    val current = _state.value
                    if (current is ReleaseGateState.Legal && current.isSubmitting) {
                        _state.value = current.copy(
                            isSubmitting = false,
                            errorCode = "release_policy_refresh_failed",
                        )
                    }
                    applyCachedHardPolicyIfNeeded()
                }
            }
        }
    }

    private fun applySnapshot(snapshot: ReleasePolicySnapshot, userId: String?) {
        val policy = snapshot.releasePolicy
        if (policy.requiresHardUpdate(currentBuild)) {
            repository.cacheHardPolicy(policy)
            _state.value = ReleaseGateState.Hard(policy)
            return
        }
        repository.clearCachedHardPolicy()

        val legalPolicy = snapshot.androidLegalPolicy
        if (userId != null && legalPolicy?.requiresAppUpdate == true) {
            _state.value = ReleaseGateState.LegalDocumentsOutdated(legalPolicy)
            return
        }
        if (userId != null && legalPolicy?.requiresAcknowledgement == true) {
            _state.value = ReleaseGateState.Legal(legalPolicy)
            return
        }
        applyPolicy(policy)
    }

    private fun applyPolicy(policy: AppReleasePolicy) {
        if (policy.requiresHardUpdate(currentBuild)) {
            repository.cacheHardPolicy(policy)
            _state.value = ReleaseGateState.Hard(policy)
            return
        }
        repository.clearCachedHardPolicy()
        if (policy.offersSoftUpdate(currentBuild) && repository.dismissedSoftPolicyIdentity() != policy.identity) {
            _state.value = ReleaseGateState.Soft(policy)
        } else {
            _state.value = ReleaseGateState.Clear
        }
    }

    fun dismissSoft(policy: AppReleasePolicy) {
        repository.dismissSoftPolicy(policy.identity)
        _state.value = ReleaseGateState.Clear
    }

    fun acknowledgeLegal(policy: AndroidLegalPolicy) {
        val userId = currentUserId ?: return
        _state.value = ReleaseGateState.Legal(policy = policy, isSubmitting = true)
        viewModelScope.launch {
            when (legalAcceptanceRepository.acknowledgeLegalUpdate(policy)) {
                is RdResult.Success -> {
                    repository.markLegalPolicyAccepted(userId, policy)
                    refresh(userId)
                }
                is RdResult.Failure -> {
                    _state.value = ReleaseGateState.Legal(
                        policy = policy,
                        errorCode = "legal_acknowledgement_failed",
                    )
                }
            }
        }
    }

    /** iOS lets an explicit-consent notice close without recording acceptance, while material
     * terms/privacy notices are non-dismissable. A later refresh presents it again. */
    fun dismissExplicitLegal(policy: AndroidLegalPolicy) {
        if (policy.requiresExplicitConsent) _state.value = ReleaseGateState.Clear
    }
}
