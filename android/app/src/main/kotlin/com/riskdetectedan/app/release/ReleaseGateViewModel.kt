package com.riskdetectedan.app.release

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.release.AppReleasePolicy
import com.riskdetectedan.core.data.release.ReleasePolicyRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface ReleaseGateState {
    data object Clear : ReleaseGateState
    data class Hard(val policy: AppReleasePolicy) : ReleaseGateState
    data class Soft(val policy: AppReleasePolicy) : ReleaseGateState
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
) : ViewModel() {

    private val currentBuild = environmentConfig.appVersionCode

    private val _state = MutableStateFlow<ReleaseGateState>(ReleaseGateState.Clear)
    val state: StateFlow<ReleaseGateState> = _state.asStateFlow()

    init {
        applyCachedHardPolicyIfNeeded()
        refresh()
    }

    private fun applyCachedHardPolicyIfNeeded() {
        val cached = repository.cachedHardPolicy() ?: return
        if (cached.requiresHardUpdate(currentBuild)) {
            _state.value = ReleaseGateState.Hard(cached)
        }
    }

    fun refresh() {
        viewModelScope.launch {
            when (val result = repository.fetchReleasePolicy()) {
                is RdResult.Success -> applyPolicy(result.value)
                is RdResult.Failure -> applyCachedHardPolicyIfNeeded()
            }
        }
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
}
