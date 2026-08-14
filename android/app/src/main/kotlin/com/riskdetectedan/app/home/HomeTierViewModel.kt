package com.riskdetectedan.app.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.analysis.PlanCapabilitiesRepository
import com.riskdetectedan.core.data.analysis.PlanCapabilities
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.billing.BillingRepository
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
 * after the tier resolves. [photoCapabilities] starts null and the caller uses the local plan
 * contract until the Android build allowlist and remote rules resolve. That fallback is
 * Free=1, Plus/Pro=3, matching the paid product instead of briefly painting paid users as Free.
 */
@HiltViewModel
class HomeTierViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val billingRepository: BillingRepository,
    private val profileRepository: ProfileRepository,
    private val planCapabilitiesRepository: PlanCapabilitiesRepository,
) : ViewModel() {

    private val _profile = MutableStateFlow<UserProfile?>(null)
    val profile: StateFlow<UserProfile?> = _profile.asStateFlow()

    private val _photoCapabilities = MutableStateFlow<PlanCapabilities?>(null)
    val photoCapabilities: StateFlow<PlanCapabilities?> = _photoCapabilities.asStateFlow()

    fun refresh() {
        val userId = authRepository.currentUserId ?: return
        viewModelScope.launch {
            // Same passive reconciliation as iOS app entry: refreshes RevenueCat
            // cancellation intent, while the following profile read remains the
            // only authority that can unlock paid UI/capabilities.
            billingRepository.reconcileBackendSubscription()
            when (val result = profileRepository.fetchProfile(userId)) {
                is RdResult.Success -> {
                    _profile.value = result.value
                    val tier = result.value.tier
                    _photoCapabilities.value = (planCapabilitiesRepository.fetchCapabilities(tier) as? RdResult.Success)
                        ?.value
                }
                is RdResult.Failure -> Unit
            }
        }
    }
}
