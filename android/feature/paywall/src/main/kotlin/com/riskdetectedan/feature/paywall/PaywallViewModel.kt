package com.riskdetectedan.feature.paywall

import android.app.Activity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.revenuecat.purchases.PurchasesTransactionException
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.billing.AppErrorMessage
import com.riskdetectedan.core.data.billing.AppErrorMessages
import com.riskdetectedan.core.data.billing.BillingPackage
import com.riskdetectedan.core.data.billing.BillingRepository
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

sealed interface PaywallUiState {
    data object Loading : PaywallUiState
    data object SignedOut : PaywallUiState
    data class Loaded(val packages: List<BillingPackage>, val currentTier: SubscriptionTier) : PaywallUiState
    data class Failed(val message: String) : PaywallUiState
}

/**
 * Mirrors `RevenueCatSubscriptionManager`'s configure -> identify -> loadOfferings sequence
 * (SubscriptionManager.swift) via [BillingRepository]. No pricing/trial-length UI logic lives
 * here — that's server/store-configured (DEC-04 coordinates trial length across platforms,
 * DEC-14 requires identical Play/App Store product ids), this just displays what the store
 * actually returns and reports what the store actually granted after a purchase.
 */
@HiltViewModel
class PaywallViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val billingRepository: BillingRepository,
    private val paywallEventRepository: PaywallEventRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<PaywallUiState>(PaywallUiState.Loading)
    val state: StateFlow<PaywallUiState> = _state.asStateFlow()

    private val _isPurchasing = MutableStateFlow(false)
    val isPurchasing: StateFlow<Boolean> = _isPurchasing.asStateFlow()

    private val _purchaseError = MutableStateFlow<AppErrorMessage?>(null)
    val purchaseError: StateFlow<AppErrorMessage?> = _purchaseError.asStateFlow()

    // One funnel session per ViewModel instance — mirrors iOS's per-presentation
    // funnel_session_id (a fresh UUID each time the paywall is shown, reused by every event
    // fired during that visit).
    private val funnelSessionId = UUID.randomUUID().toString()

    init {
        load()
    }

    fun load() {
        val userId = authRepository.currentUserId
        if (userId == null) {
            _state.value = PaywallUiState.SignedOut
            return
        }
        _state.value = PaywallUiState.Loading
        viewModelScope.launch {
            when (val configured = billingRepository.configure(userId)) {
                is RdResult.Failure -> {
                    _state.value = PaywallUiState.Failed(configured.message)
                    return@launch
                }
                is RdResult.Success -> Unit
            }

            val packages = when (val result = billingRepository.fetchPackages()) {
                is RdResult.Success -> result.value
                is RdResult.Failure -> {
                    _state.value = PaywallUiState.Failed(result.message)
                    return@launch
                }
            }
            val tier = when (val result = billingRepository.currentTier()) {
                is RdResult.Success -> result.value
                // A completed offerings fetch with an unreadable customer-info read is still
                // worth showing — surface Free rather than fail the whole paywall over what's
                // likely a transient read error (same reasoning as AnalysisViewModel's findings
                // fallback).
                is RdResult.Failure -> SubscriptionTier.Free
            }
            _state.value = PaywallUiState.Loaded(packages, tier)
            recordEvent(userId, PaywallEventName.View, selectedTier = tier)
        }
    }

    fun purchase(activity: Activity, billingPackage: BillingPackage) {
        if (_isPurchasing.value) return
        val userId = authRepository.currentUserId ?: return
        _isPurchasing.value = true
        _purchaseError.value = null
        viewModelScope.launch {
            recordEvent(
                userId,
                PaywallEventName.PurchaseStarted,
                selectedTier = billingPackage.tier,
                billingPackage = billingPackage,
            )
            when (val result = billingRepository.purchase(activity, billingPackage)) {
                is RdResult.Success -> {
                    _isPurchasing.value = false
                    val current = _state.value as? PaywallUiState.Loaded
                    if (current != null) _state.value = current.copy(currentTier = result.value)
                    recordEvent(
                        userId,
                        PaywallEventName.PurchaseSucceeded,
                        selectedTier = result.value,
                        billingPackage = billingPackage,
                    )
                }
                is RdResult.Failure -> {
                    _isPurchasing.value = false
                    val cause = result.cause
                    if (cause is PurchasesTransactionException && cause.userCancelled) {
                        // Silent, matches iOS's `catch is CancellationError` in
                        // InAppPaywallView.swift — no error UI, no purchase_failed event, the
                        // user just closed the Google Play sheet.
                        return@launch
                    }
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

    fun restorePurchases() {
        if (_isPurchasing.value) return
        val userId = authRepository.currentUserId ?: return
        _isPurchasing.value = true
        _purchaseError.value = null
        viewModelScope.launch {
            recordEvent(userId, PaywallEventName.RestoreTap, selectedTier = null)
            when (val result = billingRepository.restorePurchases()) {
                is RdResult.Success -> {
                    _isPurchasing.value = false
                    val current = _state.value as? PaywallUiState.Loaded
                    if (current != null) _state.value = current.copy(currentTier = result.value)
                }
                is RdResult.Failure -> {
                    _isPurchasing.value = false
                    _purchaseError.value = AppErrorMessages.makePurchase(
                        result.cause ?: RuntimeException(result.message),
                        context = "Satın alımlar geri yüklenemedi",
                        fallbackTitle = "Satın alımlar geri yüklenemedi",
                    )
                }
            }
        }
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
                    currentTier = selectedTier?.name?.lowercase() ?: "unknown",
                    selectedPackageId = billingPackage?.id,
                    purchaseError = purchaseError,
                ),
            )
        }
    }

    fun clearPurchaseError() {
        _purchaseError.value = null
    }
}
