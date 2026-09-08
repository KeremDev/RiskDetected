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
import com.riskdetectedan.core.data.billing.PurchaseErrorClassifier
import com.riskdetectedan.core.data.billing.PurchaseErrorKind
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

internal data class PaywallEntryDefinition(val surface: String, val component: String)

/**
 * Stable analytics catalog shared conceptually with iOS `PaywallEntryPoint`.
 * Exact lookup is deliberate: prefix heuristics made a typo look partially valid and let a new
 * card silently land in the dashboard with component="unknown".
 */
internal val paywallEntryCatalog: Map<String, PaywallEntryDefinition> = mapOf(
    "home_header_upgrade" to PaywallEntryDefinition("home", "header_upgrade_cta"),
    "home_header_profile_menu_upgrade" to PaywallEntryDefinition("home", "header_profile_menu_upgrade"),
    "analyses_header_upgrade" to PaywallEntryDefinition("analyses", "header_upgrade_cta"),
    "analyses_header_profile_menu_upgrade" to PaywallEntryDefinition("analyses", "header_profile_menu_upgrade"),
    "reports_header_upgrade" to PaywallEntryDefinition("reports", "header_upgrade_cta"),
    "reports_header_profile_menu_upgrade" to PaywallEntryDefinition("reports", "header_profile_menu_upgrade"),
    "result_header_upgrade" to PaywallEntryDefinition("analysis_results", "header_upgrade_cta"),
    "result_header_profile_menu_upgrade" to PaywallEntryDefinition("analysis_results", "header_profile_menu_upgrade"),
    "quick_scan_quota_alert" to PaywallEntryDefinition("home", "quota_alert"),
    "home_canvas_locked_focus" to PaywallEntryDefinition("home", "analysis_focus_lock"),
    "home_photo_upload_quota" to PaywallEntryDefinition("home", "photo_upload_quota_lock"),
    "home_quota_hint" to PaywallEntryDefinition("home", "quota_status_card"),
    "home_analysis_start_quota" to PaywallEntryDefinition("home", "analysis_start_quota_gate"),
    "home_quick_scan_quota" to PaywallEntryDefinition("home", "quick_scan_quota_gate"),
    "home_photo_tray_locked_slot" to PaywallEntryDefinition("home", "photo_tray_locked_slot"),
    "home_photo_limit" to PaywallEntryDefinition("home", "photo_limit_gate"),
    "analyses_company_picker" to PaywallEntryDefinition("analyses", "company_picker_lock"),
    "reports_company_picker" to PaywallEntryDefinition("reports", "company_picker_lock"),
    "profile_company_picker" to PaywallEntryDefinition("profile", "company_picker_lock"),
    "profile_upsell_card" to PaywallEntryDefinition("profile", "plan_upsell_card"),
    "reports_upsell_card" to PaywallEntryDefinition("reports", "plan_upsell_card"),
    "reports_locked_report_options" to PaywallEntryDefinition("reports", "report_options_lock"),
    "reports_report_company_picker" to PaywallEntryDefinition("reports", "company_picker_lock"),
    "result_hub_risk_analysis_promotion" to PaywallEntryDefinition("analysis_results", "result_membership_promotion"),
    "result_hub_expert_advice_promotion" to PaywallEntryDefinition("expert_advice", "result_membership_promotion"),
    "result_hub_training_promotion" to PaywallEntryDefinition("training_recommendations", "result_membership_promotion"),
    "result_hub_approved_notebook_promotion" to PaywallEntryDefinition("approved_notebook", "result_membership_promotion"),
    "result_locked_report_options" to PaywallEntryDefinition("analysis_results", "report_options_lock"),
    "result_report_company_picker" to PaywallEntryDefinition("analysis_results", "company_picker_lock"),
    "result_summary_upgrade_hint" to PaywallEntryDefinition("analysis_results", "result_summary_hint"),
    "result_confidence_chip" to PaywallEntryDefinition("analysis_results", "confidence_chip"),
    "result_finding_locked_feature" to PaywallEntryDefinition("analysis_results", "finding_card_locked_feature"),
    "result_locked_finding_preview" to PaywallEntryDefinition("analysis_results", "locked_finding_preview"),
    "finding_detail_plus_pro_promotion" to PaywallEntryDefinition("finding_detail", "finding_detail_membership_promotion"),
    "finding_detail_pro_promotion" to PaywallEntryDefinition("finding_detail", "finding_detail_membership_promotion"),
    "finding_detail_regulatory_references" to PaywallEntryDefinition("finding_detail", "regulatory_references_lock"),
    "onboarding_personal_plan" to PaywallEntryDefinition("onboarding", "personal_plan_screen"),
    "onboarding_trial_invite" to PaywallEntryDefinition("onboarding", "trial_invite_screen"),
    "onboarding_flow" to PaywallEntryDefinition("onboarding", "onboarding_paywall"),
)

internal fun paywallEntrySurface(entryPoint: String): String =
    paywallEntryCatalog[entryPoint]?.surface ?: "unknown"

internal fun paywallEntryComponent(entryPoint: String): String =
    paywallEntryCatalog[entryPoint]?.component ?: "unknown"

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
        entryPoint: String,
        entryTargetTier: String? = null,
        entryItemId: String? = null,
        entryAttributes: Map<String, String> = emptyMap(),
    ) {
        if (didBegin) return
        didBegin = true
        funnelSessionId = inheritedFunnelSessionId?.takeIf { it.isNotBlank() } ?: funnelSessionId
        resultHubAnalysisId = resultAnalysisId?.takeIf { it.isNotBlank() }
        resultHubSection = resultSection.toResultSectionOrNull()
        val resolvedEntryPoint = entryPoint.takeIf(String::isNotBlank)
            ?: resultSection.resultPromotionEntryPoint()
            ?: "unknown"
        val isRegisteredEntryPoint = paywallEntryCatalog.containsKey(resolvedEntryPoint)
        entryAttribution = PaywallEntryAttribution(
            entryPoint = resolvedEntryPoint,
            entrySurface = paywallEntrySurface(resolvedEntryPoint),
            entryComponent = paywallEntryComponent(resolvedEntryPoint),
            entryTargetTier = entryTargetTier.toSubscriptionTierOrNull(),
            analysisId = resultHubAnalysisId,
            resultSection = resultSection?.takeIf(String::isNotBlank),
            itemId = entryItemId?.takeIf(String::isNotBlank),
            attributes = entryAttributes + mapOf(
                "client_platform" to "android",
                "attribution_status" to if (isRegisteredEntryPoint) "registered" else "unregistered_entry_point",
            ),
        )
        authRepository.currentUserId?.let { userId ->
            recordEvent(
                userId = userId,
                event = PaywallEventName.EntryTap,
                selectedTier = entryAttribution?.entryTargetTier,
            )
            // Opening the paywall is a UI fact, not an offerings-load success. Recording this
            // only after RevenueCat/configuration completed made failed/slow opens disappear.
            recordEvent(
                userId = userId,
                event = PaywallEventName.View,
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
            try {
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
                    val errorKind = cause?.let { PurchaseErrorClassifier.classify(it) }?.kind
                    if ((cause is PurchasesTransactionException && cause.userCancelled) || errorKind == PurchaseErrorKind.Cancelled) {
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
                    if (errorKind == PurchaseErrorKind.PaymentPending) {
                        recordEvent(
                            userId,
                            PaywallEventName.PaymentPending,
                            selectedTier = billingPackage.tier,
                            billingPackage = billingPackage,
                            purchaseError = result.message,
                        )
                    } else {
                        recordEvent(
                            userId,
                            PaywallEventName.PurchaseFailed,
                            selectedTier = billingPackage.tier,
                            billingPackage = billingPackage,
                            purchaseError = result.message,
                        )
                    }
                    _purchaseError.value = AppErrorMessages.makePurchase(
                        cause ?: RuntimeException(result.message),
                        context = context.getString(RdR.string.rd_satin_alma_dogrulanamadi),
                        fallbackTitle = context.getString(RdR.string.rd_satin_alma_dogrulanamadi),
                    )
                }
            }
            } finally {
                _isPurchasing.value = false
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
