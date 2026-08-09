package com.riskdetectedan.feature.onboarding

import android.app.Activity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.revenuecat.purchases.PurchasesTransactionException
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.billing.BillingPackage
import com.riskdetectedan.core.data.billing.BillingRepository
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.paywall.PaywallEventMetadata
import com.riskdetectedan.core.data.paywall.PaywallEventName
import com.riskdetectedan.core.data.paywall.PaywallEventRepository
import com.riskdetectedan.core.data.profile.SubscriptionTier
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

private const val PURCHASE_CONTEXT = "Satın alma doğrulanamadı"
private const val EVENT_SOURCE = "onboarding_v2"

/** The two real packages [OBTimelinePaywallScreen] offers — always Plus (onboarding upsells the
 * entry-level paid tier only, same as iOS's `OBTimelinePaywallView`, never Pro). */
data class OBTimelinePackages(val yearly: BillingPackage?, val monthly: BillingPackage?)

sealed interface OBTimelinePaywallUiState {
    data object Loading : OBTimelinePaywallUiState
    data class Loaded(val packages: OBTimelinePackages) : OBTimelinePaywallUiState

    /** Signed out, offerings fetch failed, or RevenueCat has no Plus package configured on this
     * offering — the screen falls back to its pre-existing static Google-Play-shows-price copy
     * and both CTAs just continue onboarding, same as before this real-purchase wiring. Not
     * surfaced as an error to the user: this is an onboarding upsell, not a paywall the user is
     * blocked behind. */
    data object Unavailable : OBTimelinePaywallUiState
}

/**
 * Real purchase wiring for step 11's timeline paywall — closes the gap documented on
 * [OBTimelinePaywallScreen]'s previous static-placeholder version: iOS's `OBTimelinePaywallView`
 * does a live RevenueCat purchase right here, in onboarding, before the user ever reaches
 * feature:paywall. Deliberately its own small ViewModel rather than reusing
 * `feature:paywall`'s `PaywallViewModel` — `feature:onboarding` doesn't depend on
 * `feature:paywall` (pre-existing module-boundary reasoning), but both already depend on
 * `core:data`, which is all a real [BillingRepository]-backed purchase needs.
 */
@HiltViewModel
class OBTimelinePaywallViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val billingRepository: BillingRepository,
    private val paywallEventRepository: PaywallEventRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<OBTimelinePaywallUiState>(OBTimelinePaywallUiState.Loading)
    val state: StateFlow<OBTimelinePaywallUiState> = _state.asStateFlow()

    private val _isPurchasing = MutableStateFlow(false)
    val isPurchasing: StateFlow<Boolean> = _isPurchasing.asStateFlow()

    private val _purchaseError = MutableStateFlow<AppErrorMessage?>(null)
    val purchaseError: StateFlow<AppErrorMessage?> = _purchaseError.asStateFlow()

    private val funnelSessionId = UUID.randomUUID().toString()

    init {
        load()
    }

    private fun load() {
        val userId = authRepository.currentUserId
        if (userId == null) {
            _state.value = OBTimelinePaywallUiState.Unavailable
            return
        }
        viewModelScope.launch {
            when (billingRepository.configure(userId)) {
                is RdResult.Failure -> {
                    _state.value = OBTimelinePaywallUiState.Unavailable
                    return@launch
                }
                is RdResult.Success -> Unit
            }
            val packages = when (val result = billingRepository.fetchPackages()) {
                is RdResult.Success -> result.value
                is RdResult.Failure -> {
                    _state.value = OBTimelinePaywallUiState.Unavailable
                    return@launch
                }
            }
            val plusPackages = OBTimelinePackages(
                yearly = packages.find { it.tier == SubscriptionTier.Plus && it.productId.contains("yearly", ignoreCase = true) },
                monthly = packages.find { it.tier == SubscriptionTier.Plus && it.productId.contains("monthly", ignoreCase = true) },
            )
            if (plusPackages.yearly == null && plusPackages.monthly == null) {
                _state.value = OBTimelinePaywallUiState.Unavailable
                return@launch
            }
            _state.value = OBTimelinePaywallUiState.Loaded(plusPackages)
            recordEvent(userId, PaywallEventName.View, selectedTier = SubscriptionTier.Plus)
        }
    }

    /** Purchases [billingPackage] and calls [onPurchased] once the store attempt resolves to a
     * success (regardless of granted tier — the backend webhook, not this client read, is the
     * entitlement source of truth per master §37) — same "just continue" behavior the static CTA
     * always had, now backed by a real purchase attempt instead of skipping it. A user-cancelled
     * sheet is silent (matches feature:paywall/iOS); any other failure surfaces inline and does
     * NOT call [onPurchased] — the user stays on this screen to retry or fall back to the free
     * "Şimdilik ücretsiz devam et" button. */
    fun purchase(activity: Activity, billingPackage: BillingPackage, onPurchased: () -> Unit) {
        if (_isPurchasing.value) return
        val userId = authRepository.currentUserId ?: return
        _isPurchasing.value = true
        _purchaseError.value = null
        viewModelScope.launch {
            recordEvent(userId, PaywallEventName.PurchaseStarted, selectedTier = billingPackage.tier, billingPackage = billingPackage)
            when (val result = billingRepository.purchase(activity, billingPackage)) {
                is RdResult.Success -> {
                    _isPurchasing.value = false
                    recordEvent(userId, PaywallEventName.PurchaseSucceeded, selectedTier = result.value, billingPackage = billingPackage)
                    onPurchased()
                }
                is RdResult.Failure -> {
                    _isPurchasing.value = false
                    val cause = result.cause
                    if (cause is PurchasesTransactionException && cause.userCancelled) return@launch
                    _purchaseError.value = AppErrorMessages.makePurchase(
                        cause ?: RuntimeException(result.message),
                        context = PURCHASE_CONTEXT,
                        fallbackTitle = PURCHASE_CONTEXT,
                    )
                    recordEvent(
                        userId,
                        PaywallEventName.PurchaseFailed,
                        selectedTier = billingPackage.tier,
                        billingPackage = billingPackage,
                        purchaseError = result.message,
                    )
                }
            }
        }
    }

    fun clearPurchaseError() {
        _purchaseError.value = null
    }

    private fun recordEvent(
        userId: String,
        event: PaywallEventName,
        selectedTier: SubscriptionTier?,
        billingPackage: BillingPackage? = null,
        purchaseError: String? = null,
    ) {
        viewModelScope.launch {
            paywallEventRepository.record(
                event = event,
                userId = userId,
                funnelSessionId = funnelSessionId,
                selectedTier = selectedTier,
                billing = billingPackage?.productId?.let {
                    when {
                        it.contains("yearly", ignoreCase = true) -> "yearly"
                        it.contains("monthly", ignoreCase = true) -> "monthly"
                        else -> null
                    }
                },
                productIdentifier = billingPackage?.productId,
                metadata = PaywallEventMetadata(
                    layout = "onboarding_timeline",
                    currentTier = selectedTier?.name?.lowercase() ?: "unknown",
                    selectedPackageId = billingPackage?.id,
                    purchaseError = purchaseError,
                ),
                source = EVENT_SOURCE,
            )
        }
    }
}
