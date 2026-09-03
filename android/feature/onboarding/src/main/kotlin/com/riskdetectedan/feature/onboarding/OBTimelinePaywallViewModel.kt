package com.riskdetectedan.feature.onboarding

import android.app.Activity
import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.revenuecat.purchases.PurchasesTransactionException
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.billing.BillingPackage
import com.riskdetectedan.core.data.billing.BillingRepository
import com.riskdetectedan.core.data.billing.PaywallDesignPricing
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.paywall.PaywallEntryAttribution
import com.riskdetectedan.core.data.paywall.PaywallEventMetadata
import com.riskdetectedan.core.data.paywall.PaywallEventName
import com.riskdetectedan.core.data.paywall.PaywallEventRepository
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

private const val EVENT_SOURCE = "onboarding_v2"

/**
 * The onboarding paywall has no preceding upgrade tap to inherit attribution from, so it declares
 * its own — the same triple `PaywallEventService.swift` writes for `source = .onboardingV2`
 * (`PaywallEntryPoint.onboardingFlow` → surface `onboarding`, component `onboarding_paywall`).
 * Without it every onboarding paywall event landed with a null entry_point and was invisible in
 * the funnel next to the in-app paywall's own rows.
 */
private const val ENTRY_POINT = "onboarding_flow"
private const val ENTRY_SURFACE = "onboarding"
private const val ENTRY_COMPONENT = "onboarding_paywall"

/** Bir plan için yıllık/aylık paket çifti. */
data class OBTimelinePackages(val yearly: BillingPackage?, val monthly: BillingPackage?)

/** Onboarding paywall'ında gösterilen plan — iOS Claude Design akışıyla aynı: PLUS açılışta
 * gelir, çapraz satış kartıyla PRO'ya geçilebilir. */
enum class OBPaywallPlan(val tier: SubscriptionTier) {
    Plus(SubscriptionTier.Plus),
    Pro(SubscriptionTier.Pro),
}

enum class OBPaywallBilling(val wireValue: String) {
    Yearly("yearly"),
    Monthly("monthly"),
}

sealed interface OBTimelinePaywallUiState {
    data object Loading : OBTimelinePaywallUiState
    data class Loaded(val plus: OBTimelinePackages, val pro: OBTimelinePackages) : OBTimelinePaywallUiState

    /** Signed out, offerings fetch failed, or RevenueCat has no Plus package configured on this
     * offering. The purchase CTA remains disabled so a missing store product can never be
     * mistaken for a successful subscription; the explicit free-continuation action remains
     * available because this onboarding upsell does not block access to the free tier. */
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
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val billingRepository: BillingRepository,
    private val paywallEventRepository: PaywallEventRepository,
    private val releasePolicyRepository: ReleasePolicyRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<OBTimelinePaywallUiState>(OBTimelinePaywallUiState.Loading)
    val state: StateFlow<OBTimelinePaywallUiState> = _state.asStateFlow()

    private val _isPurchasing = MutableStateFlow(false)
    val isPurchasing: StateFlow<Boolean> = _isPurchasing.asStateFlow()

    private val _purchaseError = MutableStateFlow<AppErrorMessage?>(null)
    val purchaseError: StateFlow<AppErrorMessage?> = _purchaseError.asStateFlow()

    private val _selectedPlan = MutableStateFlow(OBPaywallPlan.Plus)
    val selectedPlan: StateFlow<OBPaywallPlan> = _selectedPlan.asStateFlow()

    // Her plan kendi faturalama seçimini korur (iOS `plusBilling` / `proBilling`).
    private val _plusBilling = MutableStateFlow(OBPaywallBilling.Yearly)
    private val _proBilling = MutableStateFlow(OBPaywallBilling.Yearly)

    val selectedBilling: StateFlow<OBPaywallBilling> =
        combine(_selectedPlan, _plusBilling, _proBilling) { plan, plus, pro ->
            if (plan == OBPaywallPlan.Plus) plus else pro
        }.stateIn(viewModelScope, SharingStarted.Eagerly, OBPaywallBilling.Yearly)

    private val funnelSessionId = UUID.randomUUID().toString()

    private val entryAttribution = PaywallEntryAttribution(
        entryPoint = ENTRY_POINT,
        entrySurface = ENTRY_SURFACE,
        entryComponent = ENTRY_COMPONENT,
        entryTargetTier = SubscriptionTier.Plus,
        attributes = mapOf("client_platform" to "android"),
    )

    init {
        load()
    }

    private fun billingFor(plan: OBPaywallPlan): OBPaywallBilling =
        if (plan == OBPaywallPlan.Plus) _plusBilling.value else _proBilling.value

    private fun setBilling(plan: OBPaywallPlan, billing: OBPaywallBilling) {
        if (plan == OBPaywallPlan.Plus) _plusBilling.value = billing else _proBilling.value = billing
    }

    fun packagesFor(plan: OBPaywallPlan): OBTimelinePackages {
        val loaded = _state.value as? OBTimelinePaywallUiState.Loaded ?: return OBTimelinePackages(null, null)
        return if (plan == OBPaywallPlan.Plus) loaded.plus else loaded.pro
    }

    fun packageFor(plan: OBPaywallPlan, billing: OBPaywallBilling): BillingPackage? =
        packagesFor(plan).let { if (billing == OBPaywallBilling.Yearly) it.yearly else it.monthly }

    fun selectBilling(billing: OBPaywallBilling) {
        val plan = _selectedPlan.value
        if (billingFor(plan) == billing || _isPurchasing.value) return
        setBilling(plan, billing)
        authRepository.currentUserId?.let {
            recordEvent(it, PaywallEventName.BillingSelect, selectedTier = plan.tier, billing = billing)
        }
    }

    /** Çapraz satış kartı: PLUS ↔ PRO geçişi. PRO paketi yoksa geçiş yapılmaz. */
    fun togglePlan() {
        if (_isPurchasing.value) return
        val target = if (_selectedPlan.value == OBPaywallPlan.Plus) OBPaywallPlan.Pro else OBPaywallPlan.Plus
        val targetPackages = packagesFor(target)
        if (targetPackages.yearly == null && targetPackages.monthly == null) return
        _selectedPlan.value = target
        setBilling(target, OBPaywallBilling.Yearly)
        alignBillingWithAvailablePackage()
        authRepository.currentUserId?.let {
            recordEvent(it, PaywallEventName.PlanSelect, selectedTier = target.tier, billing = billingFor(target))
        }
    }

    /** CTA ve kapatma, uygulama içi paywall'daki karşılıkları gibi kaydedilir (iOS
     * `handlePrimaryAction` / `closePaywall`); bunlar olmadan onboarding hunisinde görüntüleme ile
     * satın alma arasındaki adım boş kalıyordu. */
    fun recordCtaTap() {
        val plan = _selectedPlan.value
        authRepository.currentUserId?.let {
            recordEvent(
                it,
                PaywallEventName.CtaTap,
                selectedTier = plan.tier,
                billingPackage = packageFor(plan, billingFor(plan)),
                billing = billingFor(plan),
            )
        }
    }

    fun recordClose() {
        val plan = _selectedPlan.value
        authRepository.currentUserId?.let {
            recordEvent(it, PaywallEventName.Close, selectedTier = plan.tier, billing = billingFor(plan))
        }
    }

    /** Çapraz satış kartı yalnızca karşı planın gerçekten satılabildiği durumda gösterilir. */
    fun crossSellAvailable(): Boolean {
        val other = if (_selectedPlan.value == OBPaywallPlan.Plus) OBPaywallPlan.Pro else OBPaywallPlan.Plus
        val packages = packagesFor(other)
        return packages.yearly != null || packages.monthly != null
    }

    private fun alignBillingWithAvailablePackage() {
        OBPaywallPlan.entries.forEach { plan ->
            if (packageFor(plan, billingFor(plan)) != null) return@forEach
            setBilling(
                plan,
                if (packagesFor(plan).yearly != null) OBPaywallBilling.Yearly else OBPaywallBilling.Monthly,
            )
        }
    }

    fun load() {
        val userId = authRepository.currentUserId
        if (userId == null) {
            _state.value = OBTimelinePaywallUiState.Unavailable
            return
        }
        viewModelScope.launch {
            if (!releasePolicyRepository.resolveGate(AndroidRuntimeGateName.Payments).enabled) {
                _state.value = OBTimelinePaywallUiState.Unavailable
                return@launch
            }
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
            fun pair(tier: SubscriptionTier) = OBTimelinePackages(
                yearly = packages.find { it.tier == tier && PaywallDesignPricing.matchesYearly(it) },
                monthly = packages.find { it.tier == tier && PaywallDesignPricing.matchesMonthly(it) },
            )
            val plusPackages = pair(SubscriptionTier.Plus)
            if (plusPackages.yearly == null && plusPackages.monthly == null) {
                _state.value = OBTimelinePaywallUiState.Unavailable
                return@launch
            }
            _state.value = OBTimelinePaywallUiState.Loaded(plus = plusPackages, pro = pair(SubscriptionTier.Pro))
            alignBillingWithAvailablePackage()
            recordEvent(
                userId,
                PaywallEventName.View,
                selectedTier = SubscriptionTier.Plus,
                billing = billingFor(_selectedPlan.value),
            )
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
            val gate = releasePolicyRepository.resolveGate(AndroidRuntimeGateName.Payments)
            if (!gate.enabled) {
                _isPurchasing.value = false
                _purchaseError.value = AppErrorMessages.make(
                    context.getString(RdR.string.rd_satin_alma_kapali_format, gate.reason),
                    context = context.getString(RdR.string.rd_satin_alma_dogrulanamadi),
                )
                return@launch
            }
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
                    if (cause is PurchasesTransactionException && cause.userCancelled) {
                        // Silent for the user, recorded for the funnel — same split as
                        // feature:paywall and PaywallDesignFlowView.swift.
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

    fun clearPurchaseError() {
        _purchaseError.value = null
    }

    fun restorePurchases(onRestored: () -> Unit) {
        if (_isPurchasing.value) return
        val userId = authRepository.currentUserId ?: return
        _isPurchasing.value = true
        _purchaseError.value = null
        viewModelScope.launch {
            val gate = releasePolicyRepository.resolveGate(AndroidRuntimeGateName.Payments)
            if (!gate.enabled) {
                _isPurchasing.value = false
                _purchaseError.value = AppErrorMessages.make(
                    context.getString(RdR.string.rd_satin_alma_kapali_format, gate.reason),
                    context = context.getString(RdR.string.rd_satin_alimlar_geri_yuklenemedi),
                )
                return@launch
            }
            when (val configured = billingRepository.configure(userId)) {
                is RdResult.Failure -> {
                    _isPurchasing.value = false
                    _purchaseError.value = AppErrorMessages.make(
                        configured.message,
                        context = context.getString(RdR.string.rd_satin_alimlar_geri_yuklenemedi),
                    )
                    return@launch
                }
                is RdResult.Success -> Unit
            }
            recordEvent(userId, PaywallEventName.RestoreTap, selectedTier = null)
            when (val result = billingRepository.restorePurchases()) {
                is RdResult.Success -> {
                    _isPurchasing.value = false
                    if (result.value.isPaid) {
                        onRestored()
                    } else {
                        _purchaseError.value = AppErrorMessages.make(
                            context.getString(RdR.string.rd_aktif_abonelik_bulunamadi),
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

    private fun recordEvent(
        userId: String,
        event: PaywallEventName,
        selectedTier: SubscriptionTier?,
        billingPackage: BillingPackage? = null,
        purchaseError: String? = null,
        billing: OBPaywallBilling? = null,
    ) {
        paywallEventRepository.record(
            event = event,
            userId = userId,
            funnelSessionId = funnelSessionId,
            selectedTier = selectedTier,
            // An explicit selection carries its own billing period: billing_select/plan_select
            // reach no store package, so deriving the value from a product id alone left every
            // onboarding monthly/yearly choice unrecorded.
            billing = billing?.wireValue ?: billingPackage?.productId?.let {
                when {
                    it.contains("yearly", ignoreCase = true) -> "yearly"
                    it.contains("monthly", ignoreCase = true) -> "monthly"
                    else -> null
                }
            },
            productIdentifier = billingPackage?.productId,
            metadata = PaywallEventMetadata(
                layout = "onboarding_timeline",
                // The tier the user already has is not resolved on this screen (onboarding never
                // reads the entitlement here), and reporting the *selected* tier as the current
                // one made every onboarding row look like an existing subscriber.
                currentTier = "unknown",
                selectedPackageId = billingPackage?.id,
                purchaseError = purchaseError,
            ),
            source = EVENT_SOURCE,
            attribution = entryAttribution,
        )
    }
}
