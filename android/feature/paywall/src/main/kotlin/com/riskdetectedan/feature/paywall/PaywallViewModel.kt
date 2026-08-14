package com.riskdetectedan.feature.paywall

import android.app.Activity
import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.revenuecat.purchases.PurchasesTransactionException
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.billing.BillingPackage
import com.riskdetectedan.core.data.billing.BillingRepository
import com.riskdetectedan.core.data.billing.BillingSubscriptionState
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.paywall.PaywallEventMetadata
import com.riskdetectedan.core.data.paywall.PaywallEventName
import com.riskdetectedan.core.data.paywall.PaywallEventRepository
import com.riskdetectedan.core.data.profile.ProfileRepository
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.data.release.AndroidRuntimeGateName
import com.riskdetectedan.core.data.release.ReleasePolicyRepository
import com.riskdetectedan.core.designsystem.R as RdR
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

sealed interface PaywallUiState {
    data object Loading : PaywallUiState
    data object SignedOut : PaywallUiState
    data class Loaded(
        val packages: List<BillingPackage>,
        val currentTier: SubscriptionTier,
        val currentProductId: String? = null,
    ) : PaywallUiState
    data class Failed(val error: AppErrorMessage) : PaywallUiState
}

enum class PaywallPlan(val tier: SubscriptionTier) {
    Plus(SubscriptionTier.Plus),
    Pro(SubscriptionTier.Pro),
}

internal fun selectionIsUnavailableAsCurrentOrLower(
    currentTier: SubscriptionTier,
    currentProductId: String?,
    targetTier: SubscriptionTier,
    targetProductId: String,
): Boolean {
    if (currentTier.rank > targetTier.rank) return true
    return currentTier == targetTier && currentProductId != null &&
        currentProductId.substringBefore(':') == targetProductId.substringBefore(':')
}

enum class PaywallBilling(val wireValue: String) {
    Monthly("monthly"),
    Yearly("yearly"),
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
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val billingRepository: BillingRepository,
    private val profileRepository: ProfileRepository,
    private val paywallEventRepository: PaywallEventRepository,
    private val releasePolicyRepository: ReleasePolicyRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<PaywallUiState>(PaywallUiState.Loading)
    val state: StateFlow<PaywallUiState> = _state.asStateFlow()

    private val _isPurchasing = MutableStateFlow(false)
    val isPurchasing: StateFlow<Boolean> = _isPurchasing.asStateFlow()

    private val _purchaseError = MutableStateFlow<AppErrorMessage?>(null)
    val purchaseError: StateFlow<AppErrorMessage?> = _purchaseError.asStateFlow()

    private val _selectedPlan = MutableStateFlow(PaywallPlan.Plus)
    val selectedPlan: StateFlow<PaywallPlan> = _selectedPlan.asStateFlow()

    private val _selectedBilling = MutableStateFlow(PaywallBilling.Yearly)
    val selectedBilling: StateFlow<PaywallBilling> = _selectedBilling.asStateFlow()

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
            val runtimeGate = releasePolicyRepository.resolveGate(AndroidRuntimeGateName.Payments)
            if (!runtimeGate.enabled) {
                _state.value = PaywallUiState.Failed(
                    AppErrorMessages.make(
                        context.getString(RdR.string.rd_android_satin_alma_kapali_format, runtimeGate.reason),
                        context = context.getString(RdR.string.rd_abonelik_yuklenemedi),
                    ),
                )
                return@launch
            }
            when (val configured = billingRepository.configure(userId)) {
                is RdResult.Failure -> {
                    _state.value = PaywallUiState.Failed(
                        AppErrorMessages.make(
                            configured.message,
                            context = context.getString(RdR.string.rd_abonelik_yuklenemedi),
                        ),
                    )
                    return@launch
                }
                is RdResult.Success -> Unit
            }

            val packages = when (val result = billingRepository.fetchPackages()) {
                is RdResult.Success -> result.value
                is RdResult.Failure -> {
                    _state.value = PaywallUiState.Failed(
                        AppErrorMessages.make(
                            result.message,
                            context = context.getString(RdR.string.rd_abonelik_yuklenemedi),
                        ),
                    )
                    return@launch
                }
            }
            val subscriptionState = when (val result = billingRepository.currentSubscriptionState()) {
                is RdResult.Success -> result.value
                // A completed offerings fetch with an unreadable customer-info read is still
                // worth showing — surface Free rather than fail the whole paywall over what's
                // likely a transient read error (same reasoning as AnalysisViewModel's findings
                // fallback).
                is RdResult.Failure -> BillingSubscriptionState(SubscriptionTier.Free, null)
            }
            // Supabase is the entitlement authority throughout the app. RevenueCat remains the
            // store-product authority, but its CustomerInfo can briefly lag the server webhook
            // (or legitimately differ under a staging test override). Reading only CustomerInfo
            // here made a backend-verified Plus/Pro user look Free inside the paywall even while
            // the rest of the app correctly unlocked paid capabilities.
            val backendTier = when (val profile = profileRepository.fetchProfile(userId)) {
                is RdResult.Success -> profile.value.tier
                is RdResult.Failure -> subscriptionState.tier
            }
            val activeProductId = subscriptionState.activeProductId
                ?.takeIf { subscriptionState.tier == backendTier }
            _state.value = PaywallUiState.Loaded(packages, backendTier, activeProductId)
            _selectedPlan.value = if (backendTier == SubscriptionTier.Free) PaywallPlan.Plus else PaywallPlan.Pro
            alignBillingWithAvailablePackage(packages)
            recordEvent(userId, PaywallEventName.View, selectedTier = _selectedPlan.value.tier)
        }
    }

    fun selectPlan(plan: PaywallPlan) {
        if (_selectedPlan.value == plan || _isPurchasing.value) return
        _selectedPlan.value = plan
        _selectedBilling.value = PaywallBilling.Yearly
        val packages = (_state.value as? PaywallUiState.Loaded)?.packages.orEmpty()
        alignBillingWithAvailablePackage(packages)
        authRepository.currentUserId?.let {
            recordEvent(it, PaywallEventName.PlanSelect, selectedTier = plan.tier, billing = _selectedBilling.value)
        }
    }

    fun selectBilling(billing: PaywallBilling) {
        if (_selectedBilling.value == billing || _isPurchasing.value) return
        _selectedBilling.value = billing
        authRepository.currentUserId?.let {
            recordEvent(it, PaywallEventName.BillingSelect, selectedTier = _selectedPlan.value.tier, billing = billing)
        }
    }

    fun selectedPackage(): BillingPackage? {
        val packages = (_state.value as? PaywallUiState.Loaded)?.packages.orEmpty()
        return packages.firstOrNull { pkg ->
            pkg.tier == _selectedPlan.value.tier && pkg.matches(_selectedBilling.value)
        }
    }

    fun recordClose() {
        authRepository.currentUserId?.let {
            recordEvent(it, PaywallEventName.Close, selectedTier = _selectedPlan.value.tier, billing = _selectedBilling.value)
        }
    }

    fun recordCtaTap() {
        authRepository.currentUserId?.let {
            recordEvent(
                it,
                PaywallEventName.CtaTap,
                selectedTier = _selectedPlan.value.tier,
                billingPackage = selectedPackage(),
                billing = _selectedBilling.value,
            )
        }
    }

    fun purchase(activity: Activity, billingPackage: BillingPackage) {
        if (_isPurchasing.value) return
        val userId = authRepository.currentUserId ?: return
        _isPurchasing.value = true
        _purchaseError.value = null
        viewModelScope.launch {
            if (!ensurePaymentsGateOpen()) return@launch
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
                    if (current != null) {
                        val refreshed = (billingRepository.currentSubscriptionState() as? RdResult.Success)?.value
                        _state.value = current.copy(
                            currentTier = refreshed?.tier ?: result.value,
                            currentProductId = refreshed?.activeProductId,
                        )
                    }
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
                        context = context.getString(RdR.string.rd_satin_alma_dogrulanamadi),
                        fallbackTitle = context.getString(RdR.string.rd_satin_alma_dogrulanamadi),
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
            if (!ensurePaymentsGateOpen()) return@launch
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
                        context = context.getString(RdR.string.rd_satin_alimlar_geri_yuklenemedi),
                        fallbackTitle = context.getString(RdR.string.rd_satin_alimlar_geri_yuklenemedi),
                    )
                }
            }
        }
    }

    private suspend fun ensurePaymentsGateOpen(): Boolean {
        val runtimeGate = releasePolicyRepository.resolveGate(AndroidRuntimeGateName.Payments)
        if (runtimeGate.enabled) return true
        _isPurchasing.value = false
        _purchaseError.value = AppErrorMessages.make(
            context.getString(RdR.string.rd_android_satin_alma_kapali_format, runtimeGate.reason),
            context = context.getString(RdR.string.rd_satin_alma_dogrulanamadi),
        )
        return false
    }

    private fun recordEvent(
        userId: String,
        event: PaywallEventName,
        selectedTier: SubscriptionTier?,
        billingPackage: BillingPackage? = null,
        purchaseError: String? = null,
        billing: PaywallBilling? = null,
    ) {
        viewModelScope.launch {
            paywallEventRepository.record(
                event = event,
                userId = userId,
                funnelSessionId = funnelSessionId,
                selectedTier = selectedTier,
                billing = billing?.wireValue ?: billingPackage?.productId?.let {
                    when {
                        it.contains("yearly", ignoreCase = true) -> "yearly"
                        it.contains("monthly", ignoreCase = true) -> "monthly"
                        else -> null
                    }
                },
                productIdentifier = billingPackage?.productId,
                metadata = PaywallEventMetadata(
                    currentTier = ((_state.value as? PaywallUiState.Loaded)?.currentTier)
                        ?.name?.lowercase() ?: "unknown",
                    selectedPackageId = billingPackage?.id,
                    purchaseError = purchaseError,
                ),
            )
        }
    }

    fun clearPurchaseError() {
        _purchaseError.value = null
    }

    private fun alignBillingWithAvailablePackage(packages: List<BillingPackage>) {
        if (packages.any { it.tier == _selectedPlan.value.tier && it.matches(_selectedBilling.value) }) return
        _selectedBilling.value = when {
            packages.any { it.tier == _selectedPlan.value.tier && it.matches(PaywallBilling.Yearly) } -> PaywallBilling.Yearly
            else -> PaywallBilling.Monthly
        }
    }

    private fun BillingPackage.matches(billing: PaywallBilling): Boolean = when (billing) {
        PaywallBilling.Monthly -> productId.contains("monthly", ignoreCase = true)
        PaywallBilling.Yearly -> productId.contains("yearly", ignoreCase = true) || productId.contains("annual", ignoreCase = true)
    }


    fun selectionIsCurrentPlan(): Boolean {
        val loaded = _state.value as? PaywallUiState.Loaded ?: return false
        val selectedPackage = selectedPackage() ?: return false
        return selectionIsUnavailableAsCurrentOrLower(
            currentTier = loaded.currentTier,
            currentProductId = loaded.currentProductId,
            targetTier = selectedPackage.tier,
            targetProductId = selectedPackage.productId,
        )
    }
}
