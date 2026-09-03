package com.riskdetectedan.feature.paywall

import android.app.Activity
import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.revenuecat.purchases.PurchasesTransactionException
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.analysis.AnalysisResultHubRepository
import com.riskdetectedan.core.data.analysis.AnalysisResultSectionId
import com.riskdetectedan.core.data.billing.BillingPackage
import com.riskdetectedan.core.data.billing.BillingRepository
import com.riskdetectedan.core.data.billing.BillingSubscriptionState
import com.riskdetectedan.core.data.billing.PaywallDesignPricing
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.paywall.PaywallEventMetadata
import com.riskdetectedan.core.data.paywall.PaywallEventName
import com.riskdetectedan.core.data.paywall.PaywallEventRepository
import com.riskdetectedan.core.data.paywall.PaywallEntryAttribution
import com.riskdetectedan.core.data.profile.ProfileRepository
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.data.release.AndroidRuntimeGateName
import com.riskdetectedan.core.data.release.ReleasePolicyRepository
import com.riskdetectedan.core.designsystem.R as RdR
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
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

internal fun String?.resultPromotionEntryPoint(): String? = when (this) {
    "risk_analysis" -> "result_hub_risk_analysis_promotion"
    "expert_recommendations" -> "result_hub_expert_advice_promotion"
    "training_recommendations" -> "result_hub_training_promotion"
    "approved_notebook" -> "result_hub_approved_notebook_promotion"
    else -> null
}

internal fun paywallEntrySurface(entryPoint: String): String = when {
    entryPoint.startsWith("home_") || entryPoint == "quick_scan_quota_alert" -> "home"
    entryPoint.startsWith("analyses_") -> "analyses"
    entryPoint.startsWith("reports_") -> "reports"
    entryPoint.startsWith("profile_") -> "profile"
    entryPoint.startsWith("finding_detail_") -> "finding_detail"
    entryPoint == "result_hub_expert_advice_promotion" -> "expert_advice"
    entryPoint == "result_hub_training_promotion" -> "training_recommendations"
    entryPoint == "result_hub_approved_notebook_promotion" -> "approved_notebook"
    entryPoint.startsWith("result_") -> "analysis_results"
    entryPoint == "onboarding_flow" -> "onboarding"
    else -> "unknown"
}

internal fun paywallEntryComponent(entryPoint: String): String = when {
    entryPoint.endsWith("header_upgrade") -> "header_upgrade_cta"
    entryPoint.endsWith("profile_menu_upgrade") -> "header_profile_menu_upgrade"
    entryPoint.contains("quota_alert") -> "quota_alert"
    entryPoint.contains("canvas_locked") -> "analysis_focus_lock"
    entryPoint.contains("photo_upload_quota") -> "photo_upload_quota_lock"
    entryPoint.contains("quota_hint") -> "quota_status_card"
    entryPoint.contains("analysis_start_quota") -> "analysis_start_quota_gate"
    entryPoint.contains("quick_scan_quota") -> "quick_scan_quota_gate"
    entryPoint.contains("photo_tray_locked") -> "photo_tray_locked_slot"
    entryPoint.contains("photo_limit") -> "photo_limit_gate"
    entryPoint.endsWith("company_picker") -> "company_picker_lock"
    entryPoint.endsWith("upsell_card") -> "plan_upsell_card"
    entryPoint.contains("locked_report_options") -> "report_options_lock"
    entryPoint.startsWith("result_hub_") -> "result_membership_promotion"
    entryPoint == "result_summary_upgrade_hint" -> "result_summary_hint"
    entryPoint == "result_confidence_chip" -> "confidence_chip"
    entryPoint == "result_finding_locked_feature" -> "finding_card_locked_feature"
    entryPoint == "result_locked_finding_preview" -> "locked_finding_preview"
    entryPoint.contains("regulatory_references") -> "regulatory_references_lock"
    entryPoint.startsWith("finding_detail_") -> "finding_detail_membership_promotion"
    entryPoint == "onboarding_flow" -> "onboarding_paywall"
    else -> "unknown"
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
    private val resultHubRepository: AnalysisResultHubRepository,
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

    // iOS'ta olduğu gibi her plan kendi faturalama seçimini korur (PaywallDesignFlowView'daki
    // plusBilling / proBilling): PLUS ↔ PRO arasında gidip gelmek diğerinin seçimini bozmaz.
    private val _plusBilling = MutableStateFlow(PaywallBilling.Yearly)
    private val _proBilling = MutableStateFlow(PaywallBilling.Yearly)

    val selectedBilling: StateFlow<PaywallBilling> =
        combine(_selectedPlan, _plusBilling, _proBilling) { plan, plus, pro ->
            if (plan == PaywallPlan.Plus) plus else pro
        }.stateIn(viewModelScope, SharingStarted.Eagerly, PaywallBilling.Yearly)

    private fun billingFor(plan: PaywallPlan): PaywallBilling =
        if (plan == PaywallPlan.Plus) _plusBilling.value else _proBilling.value

    private fun setBilling(plan: PaywallPlan, billing: PaywallBilling) {
        if (plan == PaywallPlan.Plus) _plusBilling.value = billing else _proBilling.value = billing
    }

    // One funnel session per ViewModel instance — mirrors iOS's per-presentation
    // funnel_session_id (a fresh UUID each time the paywall is shown, reused by every event
    // fired during that visit).
    private var funnelSessionId = UUID.randomUUID().toString()
    private var resultHubAnalysisId: String? = null
    private var resultHubSection: AnalysisResultSectionId? = null
    private var entryAttribution: PaywallEntryAttribution? = null
    private var didBegin = false

    fun begin(
        resultAnalysisId: String? = null,
        resultSection: String? = null,
        inheritedFunnelSessionId: String? = null,
        entryPoint: String? = null,
        entryTargetTier: String? = null,
        entryItemId: String? = null,
        entryAttributes: Map<String, String> = emptyMap(),
    ) {
        if (didBegin) return
        didBegin = true
        funnelSessionId = inheritedFunnelSessionId?.takeIf { it.isNotBlank() } ?: funnelSessionId
        resultHubAnalysisId = resultAnalysisId?.takeIf { it.isNotBlank() }
        resultHubSection = resultSection.toResultSectionOrNull()
        val resolvedEntryPoint = entryPoint?.takeIf(String::isNotBlank)
            ?: resultSection.resultPromotionEntryPoint()
            ?: "unknown"
        entryAttribution = PaywallEntryAttribution(
            entryPoint = resolvedEntryPoint,
            entrySurface = paywallEntrySurface(resolvedEntryPoint),
            entryComponent = paywallEntryComponent(resolvedEntryPoint),
            entryTargetTier = entryTargetTier.toSubscriptionTierOrNull(),
            analysisId = resultHubAnalysisId,
            resultSection = resultSection?.takeIf(String::isNotBlank),
            itemId = entryItemId?.takeIf(String::isNotBlank),
            attributes = entryAttributes + ("client_platform" to "android"),
        )
        authRepository.currentUserId?.let { userId ->
            recordEvent(
                userId = userId,
                event = PaywallEventName.EntryTap,
                selectedTier = entryAttribution?.entryTargetTier,
            )
        }
        recordResultHubEvent("paywall_viewed")
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
            recordEvent(
                userId,
                PaywallEventName.View,
                selectedTier = _selectedPlan.value.tier,
                billing = billingFor(_selectedPlan.value),
            )
        }
    }

    /**
     * Applies the plan a promotion asked for (`PaywallForTier`) without emitting `plan_select`:
     * the user tapped an upgrade surface, not the paywall's own plan toggle, and iOS derives its
     * `activeScreen` from the same context silently. Logging one here made every promotion-opened
     * paywall look like the user had switched plans on it.
     */
    fun applyInitialPlan(plan: PaywallPlan) {
        if (_selectedPlan.value == plan || _isPurchasing.value) return
        _selectedPlan.value = plan
        setBilling(plan, PaywallBilling.Yearly)
        alignBillingWithAvailablePackage((_state.value as? PaywallUiState.Loaded)?.packages.orEmpty())
    }

    fun selectPlan(plan: PaywallPlan) {
        if (_selectedPlan.value == plan || _isPurchasing.value) return
        _selectedPlan.value = plan
        setBilling(plan, PaywallBilling.Yearly)
        val packages = (_state.value as? PaywallUiState.Loaded)?.packages.orEmpty()
        alignBillingWithAvailablePackage(packages)
        authRepository.currentUserId?.let {
            recordEvent(it, PaywallEventName.PlanSelect, selectedTier = plan.tier, billing = billingFor(plan))
        }
    }

    /** Çapraz satış kartı: PLUS ↔ PRO ekranı arasında geçiş (iOS `toggleScreen()`). */
    fun togglePlan() {
        selectPlan(if (_selectedPlan.value == PaywallPlan.Plus) PaywallPlan.Pro else PaywallPlan.Plus)
    }

    fun selectBilling(billing: PaywallBilling) {
        val plan = _selectedPlan.value
        if (billingFor(plan) == billing || _isPurchasing.value) return
        setBilling(plan, billing)
        authRepository.currentUserId?.let {
            recordEvent(it, PaywallEventName.BillingSelect, selectedTier = plan.tier, billing = billing)
        }
    }

    /** Ekranın fiyat/deneme/indirim hesapları için ihtiyaç duyduğu ham paket. */
    fun packageFor(plan: PaywallPlan, billing: PaywallBilling): BillingPackage? =
        (_state.value as? PaywallUiState.Loaded)?.packages.orEmpty().firstOrNull { pkg ->
            pkg.tier == plan.tier && pkg.matches(billing)
        }

    fun selectedPackage(): BillingPackage? =
        packageFor(_selectedPlan.value, billingFor(_selectedPlan.value))

    fun recordClose() {
        authRepository.currentUserId?.let {
            recordEvent(it, PaywallEventName.Close, selectedTier = _selectedPlan.value.tier, billing = billingFor(_selectedPlan.value))
        }
    }

    fun recordCtaTap() {
        authRepository.currentUserId?.let {
            recordEvent(
                it,
                PaywallEventName.CtaTap,
                selectedTier = _selectedPlan.value.tier,
                billingPackage = selectedPackage(),
                billing = billingFor(_selectedPlan.value),
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
            recordResultHubEvent("checkout_started")
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
                    recordResultHubEvent("purchase_completed")
                }
                is RdResult.Failure -> {
                    _isPurchasing.value = false
                    val cause = result.cause
                    if (cause is PurchasesTransactionException && cause.userCancelled) {
                        // Silent in the UI, matches iOS's `catch is CancellationError` in
                        // InAppPaywallView.swift — no error card, no purchase_failed event. The
                        // funnel still needs the drop-off, so record purchase_cancelled exactly
                        // as PaywallDesignFlowView.swift does.
                        recordEvent(
                            userId,
                            PaywallEventName.PurchaseCancelled,
                            selectedTier = billingPackage.tier,
                            billingPackage = billingPackage,
                        )
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
                    if (!result.value.isPaid) {
                        _purchaseError.value = AppErrorMessages.make(
                            context.getString(RdR.string.rd_paywall_design_restore_empty),
                            context = context.getString(RdR.string.rd_satin_alimlar_geri_yuklenemedi),
                        )
                    }
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
            attribution = entryAttribution,
        )
    }

    private fun recordResultHubEvent(name: String) {
        val analysisId = resultHubAnalysisId ?: return
        val section = resultHubSection ?: return
        viewModelScope.launch {
            resultHubRepository.recordEvent(
                analysisId = analysisId,
                name = name,
                section = section,
                funnelSessionId = funnelSessionId,
            )
        }
    }

    private fun String?.toResultSectionOrNull(): AnalysisResultSectionId? = when (this) {
        "risk_analysis" -> AnalysisResultSectionId.RiskAnalysis
        "expert_recommendations" -> AnalysisResultSectionId.ExpertRecommendations
        "training_recommendations" -> AnalysisResultSectionId.TrainingRecommendations
        "approved_notebook" -> AnalysisResultSectionId.ApprovedNotebook
        else -> null
    }

    private fun String?.toSubscriptionTierOrNull(): SubscriptionTier? = when (this?.lowercase()) {
        "free" -> SubscriptionTier.Free
        "plus" -> SubscriptionTier.Plus
        "pro" -> SubscriptionTier.Pro
        else -> null
    }

    fun clearPurchaseError() {
        _purchaseError.value = null
    }

    private fun alignBillingWithAvailablePackage(packages: List<BillingPackage>) {
        PaywallPlan.entries.forEach { plan ->
            if (packages.any { it.tier == plan.tier && it.matches(billingFor(plan)) }) return@forEach
            setBilling(
                plan,
                if (packages.any { it.tier == plan.tier && it.matches(PaywallBilling.Yearly) }) {
                    PaywallBilling.Yearly
                } else {
                    PaywallBilling.Monthly
                },
            )
        }
    }

    private fun BillingPackage.matches(billing: PaywallBilling): Boolean = when (billing) {
        PaywallBilling.Monthly -> PaywallDesignPricing.matchesMonthly(this)
        PaywallBilling.Yearly -> PaywallDesignPricing.matchesYearly(this)
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
