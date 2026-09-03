package com.riskdetectedan.feature.onboarding

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.billing.PaywallDesignPricing
import com.riskdetectedan.core.data.legal.LegalDocumentAssets
import com.riskdetectedan.core.designsystem.RdLegalDocument
import com.riskdetectedan.core.designsystem.RdLegalDocumentSheet
import com.riskdetectedan.core.designsystem.RdPaywallDesignBilling
import com.riskdetectedan.core.designsystem.RdPaywallDesignColor
import com.riskdetectedan.core.designsystem.RdPaywallDesignCta
import com.riskdetectedan.core.designsystem.RdPaywallDesignScreen
import com.riskdetectedan.core.designsystem.RdPaywallDesignTier
import com.riskdetectedan.core.designsystem.rdPaywallDesignState
import com.riskdetectedan.core.designsystem.R as RdR

private const val PLAY_SUBSCRIPTIONS_URL = "https://play.google.com/store/account/subscriptions"
private const val ONBOARDING_PLUS_TRIAL_DAYS = 7

internal fun resolvedOnboardingTrialDays(
    hasYearlyPackage: Boolean,
    storePeriodIso8601: String?,
): Int? = if (hasYearlyPackage) {
    PaywallDesignPricing.trialDays(storePeriodIso8601) ?: ONBOARDING_PLUS_TRIAL_DAYS
} else {
    null
}

/**
 * Onboarding 11. adımın paywall'ı — uygulama içi paywall ile birebir aynı Claude Design ekranı
 * (`PaywallDesignFlowView.swift`, `source = .onboardingV2`). iOS'ta olduğu gibi PLUS açılışta
 * gelir, çapraz satış kartıyla PRO'ya geçilir; kapatma düğmesi onboarding'i ücretsiz tamamlar.
 *
 * Ekran bileşenleri `core:designsystem`'de durur (her iki özellik modülü de oraya bağlı), akış
 * mantığı [OBTimelinePaywallViewModel]'de kalır — `feature:onboarding` hâlâ `feature:paywall`'a
 * bağlı değildir.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OBTimelinePaywallScreen(
    onDismiss: () -> Unit,
    viewModel: OBTimelinePaywallViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val selectedPlan by viewModel.selectedPlan.collectAsState()
    val selectedBilling by viewModel.selectedBilling.collectAsState()
    val isPurchasing by viewModel.isPurchasing.collectAsState()
    val purchaseError by viewModel.purchaseError.collectAsState()
    val context = LocalContext.current
    val activity = context.findActivity()
    val uriHandler = LocalUriHandler.current
    var legalDocumentKind by remember { mutableStateOf<String?>(null) }

    val isUnavailable = state is OBTimelinePaywallUiState.Unavailable
    val isLoading = state is OBTimelinePaywallUiState.Loading

    val yearlyPackage = viewModel.packageFor(selectedPlan, OBPaywallBilling.Yearly)
    val monthlyPackage = viewModel.packageFor(selectedPlan, OBPaywallBilling.Monthly)
    val selectedPackage = if (selectedBilling == OBPaywallBilling.Yearly) yearlyPackage else monthlyPackage

    // Onboarding'in önceki adımı kullanıcıya 0,00 TL başlangıcı vaat eder. Plus yıllık ürün
    // yüklendiyse bu son adım aynı 7 günlük deneme akışını korur; Play daha ayrıntılı bir dönem
    // döndürürse mağaza değeri önceliklidir. Satın alma yine yalnız gerçek RevenueCat paketiyle
    // başlatılır ve Google Play onay ekranı nihai fiyat/uygunluk kaynağı olmaya devam eder.
    val trialDays = if (selectedPlan == OBPaywallPlan.Plus) {
        resolvedOnboardingTrialDays(
            hasYearlyPackage = yearlyPackage != null,
            storePeriodIso8601 = yearlyPackage?.freeTrialPeriodIso8601,
        )
    } else {
        null
    }

    val designState = rdPaywallDesignState(
        tier = selectedPlan.designTier,
        selectedBilling = selectedBilling.designBilling,
        yearlyPrice = yearlyPackage?.formattedPrice,
        yearlyMonthlyEquivalent = PaywallDesignPricing.monthlyEquivalent(yearlyPackage),
        monthlyPrice = monthlyPackage?.formattedPrice,
        trialDays = trialDays,
        discountPercent = PaywallDesignPricing.discountPercent(
            yearlyPriceMicros = yearlyPackage?.priceAmountMicros,
            monthlyPriceMicros = monthlyPackage?.priceAmountMicros,
        ),
        priceUnavailableText = stringResource(
            if (isUnavailable) {
                RdR.string.rd_paywall_design_price_unavailable
            } else {
                RdR.string.rd_paywall_design_price_loading
            },
        ),
        cta = RdPaywallDesignCta(
            title = when {
                isPurchasing -> stringResource(RdR.string.rd_satin_alma_hazirlaniyor)
                isLoading -> stringResource(RdR.string.rd_paywall_design_cta_price_loading)
                selectedPackage == null -> stringResource(RdR.string.rd_tekrar_dene)
                trialDays != null && selectedBilling == OBPaywallBilling.Yearly ->
                    stringResource(RdR.string.rd_paywall_design_cta_start_trial)
                else -> stringResource(RdR.string.rd_aboneligi_baslat)
            },
            isLoading = isPurchasing,
            isDisabled = isPurchasing || isLoading || (selectedPackage != null && activity == null),
        ),
        notice = if (isPurchasing) stringResource(RdR.string.rd_paywall_design_purchase_opening) else null,
        errorMessage = purchaseError?.message
            ?: stringResource(RdR.string.rd_paywall_design_packages_failed).takeIf { isUnavailable },
        showsCrossSell = viewModel.crossSellAvailable(),
    )

    Box(modifier = Modifier.fillMaxSize().background(RdPaywallDesignColor.Surface)) {
        RdPaywallDesignScreen(
            state = designState,
            onClose = onDismiss,
            onSelectBilling = { viewModel.selectBilling(it.obBilling) },
            onCta = {
                val target = selectedPackage
                when {
                    target == null -> viewModel.load()
                    activity != null -> viewModel.purchase(activity, target, onPurchased = onDismiss)
                }
            },
            onRestore = { viewModel.restorePurchases(onRestored = onDismiss) },
            onTerms = { legalDocumentKind = "terms" },
            onPrivacy = { legalDocumentKind = "privacy" },
            onManageSubscription = { uriHandler.openUri(PLAY_SUBSCRIPTIONS_URL) },
            onCrossSell = viewModel::togglePlan,
        )
    }

    if (legalDocumentKind != null) {
        var legalDocuments by remember { mutableStateOf<List<RdLegalDocument>>(emptyList()) }
        LaunchedEffect(Unit) {
            legalDocuments = LegalDocumentAssets.load(context)
                .map { RdLegalDocument(kind = it.kind, title = it.title, text = it.text) }
        }
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(onDismissRequest = { legalDocumentKind = null }, sheetState = sheetState) {
            RdLegalDocumentSheet(
                documents = legalDocuments,
                initialKind = legalDocumentKind,
                onClose = { legalDocumentKind = null },
            )
        }
    }
}

/**
 * Ekran görüntüsü regresyon testleri için mağaza yüklenmiş halin belirlenimci render'ı.
 * Üretim akışı [OBTimelinePaywallScreen] ve gerçek RevenueCat paketiyle çalışır.
 */
@Composable
fun OBTimelinePaywallPreviewSurface(
    yearlyPrice: String = "₺2.499,99",
    monthlyPrice: String = "₺249,99",
    monthlyEquivalent: String = "₺208,33",
    trialDays: Int? = 7,
    discountPercent: Int? = 17,
) {
    val designState = rdPaywallDesignState(
        tier = RdPaywallDesignTier.Plus,
        selectedBilling = RdPaywallDesignBilling.Yearly,
        yearlyPrice = yearlyPrice,
        yearlyMonthlyEquivalent = monthlyEquivalent,
        monthlyPrice = monthlyPrice,
        trialDays = trialDays,
        discountPercent = discountPercent,
        priceUnavailableText = stringResource(RdR.string.rd_paywall_design_price_loading),
        cta = RdPaywallDesignCta(
            title = if (trialDays != null) {
                stringResource(RdR.string.rd_paywall_design_cta_start_trial)
            } else {
                stringResource(RdR.string.rd_aboneligi_baslat)
            },
        ),
    )

    RdPaywallDesignScreen(
        state = designState,
        onClose = {},
        onSelectBilling = {},
        onCta = {},
        onRestore = {},
        onTerms = {},
        onPrivacy = {},
        onManageSubscription = {},
        onCrossSell = {},
    )
}

internal val OBPaywallPlan.designTier: RdPaywallDesignTier
    get() = when (this) {
        OBPaywallPlan.Plus -> RdPaywallDesignTier.Plus
        OBPaywallPlan.Pro -> RdPaywallDesignTier.Pro
    }

internal val OBPaywallBilling.designBilling: RdPaywallDesignBilling
    get() = when (this) {
        OBPaywallBilling.Yearly -> RdPaywallDesignBilling.Yearly
        OBPaywallBilling.Monthly -> RdPaywallDesignBilling.Monthly
    }

internal val RdPaywallDesignBilling.obBilling: OBPaywallBilling
    get() = when (this) {
        RdPaywallDesignBilling.Yearly -> OBPaywallBilling.Yearly
        RdPaywallDesignBilling.Monthly -> OBPaywallBilling.Monthly
    }

/**
 * RevenueCat'in `PurchaseParams.Builder`'ı Google Play satın alma sayfasını açmak için bir
 * Activity ister; `LocalContext.current` her zaman Activity olmayabilir (sarmalanmış olabilir),
 * bu yüzden savunmacı biçimde çözülür.
 */
private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
