package com.riskdetectedan.app.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.profile.ProfileRepository
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.data.profile.UserProfile
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Closes the "userTier hardcoded to Free" gap documented since Faz N/O/Q — fetches the real
 * [UserProfile] instead (tier for CanvasSheet/photo-count gating, initials/tier for the header
 * avatar). Same non-blocking shape as [HomeProgressViewModel]/[QuotaViewModel]: a failed/absent
 * fetch just leaves [profile] null, and every call site falls back to [SubscriptionTier.Free] —
 * the same safe default already in place, just no longer the *only* value ever reachable.
 *
 * NOT ported: iOS's remote `loadRemotePlanCapabilities` (per-tier `app_feature_flags`-driven
 * override of `maxPhotosPerAnalysis`/paid-multi-photo kill switch) — that's a genuinely separate
 * remote-capabilities system, still a real documented gap. This closes the *local* default half
 * of `PlanCapabilities` only: `maxPhotosPerAnalysis: tier.isPaid ? 3 : 1`
 * (`AppState.swift`'s own pre-remote-fetch default, `safeMaxPhotosPerAnalysis` clamps 1..3) —
 * ported verbatim in [HomeScreen] via `maxPhotoCount`.
 */
@HiltViewModel
class HomeTierViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val profileRepository: ProfileRepository,
) : ViewModel() {

    private val _profile = MutableStateFlow<UserProfile?>(null)
    val profile: StateFlow<UserProfile?> = _profile.asStateFlow()

    fun refresh() {
        val userId = authRepository.currentUserId ?: return
        viewModelScope.launch {
            when (val result = profileRepository.fetchProfile(userId)) {
                is RdResult.Success -> _profile.value = result.value
                is RdResult.Failure -> Unit
            }
        }
    }
}
