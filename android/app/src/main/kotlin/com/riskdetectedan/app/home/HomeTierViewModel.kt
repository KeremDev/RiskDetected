package com.riskdetectedan.app.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.analysis.PlanCapabilitiesRepository
import com.riskdetectedan.core.data.analysis.PlanPhotoCapabilities
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
 * **Remote `PlanCapabilities` override now closed too** (previously documented as a separate
 * still-open gap): [refresh] fires [PlanCapabilitiesRepository.fetchPhotoCapabilities] right
 * after the tier resolves, same two-step sequencing as `applyTier`/`refreshRemotePlanCapabilities`
 * — [photoCapabilities] starts null (caller uses its own local `tier.isPaid ? 3 : 1` default,
 * same as iOS's synchronous `PlanCapabilities.forTier(tier)` before the async remote fetch lands)
 * and gets overwritten once the remote fetch resolves, exactly like iOS's `planCapabilities`
 * `@Published` getting reassigned twice.
 */
@HiltViewModel
class HomeTierViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val profileRepository: ProfileRepository,
    private val planCapabilitiesRepository: PlanCapabilitiesRepository,
) : ViewModel() {

    private val _profile = MutableStateFlow<UserProfile?>(null)
    val profile: StateFlow<UserProfile?> = _profile.asStateFlow()

    private val _photoCapabilities = MutableStateFlow<PlanPhotoCapabilities?>(null)
    val photoCapabilities: StateFlow<PlanPhotoCapabilities?> = _photoCapabilities.asStateFlow()

    fun refresh() {
        val userId = authRepository.currentUserId ?: return
        viewModelScope.launch {
            when (val result = profileRepository.fetchProfile(userId)) {
                is RdResult.Success -> {
                    _profile.value = result.value
                    val tier = result.value.tier
                    _photoCapabilities.value = (planCapabilitiesRepository.fetchPhotoCapabilities(tier) as? RdResult.Success)
                        ?.value
                }
                is RdResult.Failure -> Unit
            }
        }
    }
}
