package com.riskdetectedan.feature.paywall

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.billing.PaywallDesignPricing
import com.riskdetectedan.core.data.legal.LegalDocumentAssets
import com.riskdetectedan.core.designsystem.RdEmptyState
import com.riskdetectedan.core.designsystem.RdLegalDocument
import com.riskdetectedan.core.designsystem.RdLegalDocumentSheet
import com.riskdetectedan.core.designsystem.RdPaywallDesignBilling
import com.riskdetectedan.core.designsystem.RdPaywallDesignColor
import com.riskdetectedan.core.designsystem.RdPaywallDesignCta
import com.riskdetectedan.core.designsystem.RdPaywallDesignScreen
import com.riskdetectedan.core.designsystem.RdPaywallDesignTier
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.rdPaywallDesignState
import com.riskdetectedan.core.designsystem.R as RdR

private const val PLAY_SUBSCRIPTIONS_URL = "https://play.google.com/store/account/subscriptions"

/**
 * Uygulama içi paywall — Claude Design ekranının (`PaywallDesignFlowView.swift`) Android
 * karşılığı. PLUS ve PRO ekranları arasında çapraz satış kartıyla geçilir, fiyat/deneme/indirim
 * bilgisi yalnızca Google Play'in döndürdüğü pakete dayanır, satın alma sayfası Play'in kendi
 * yerel sayfasıdır.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaywallScreen(
    onBack: (() -> Unit)? = null,
    initialPlan: PaywallPlan? = null,
    resultAnalysisId: String? = null,
    resultSection: String? = null,
    resultFunnelSessionId: String? = null,
    entryPoint: String,
    entryTargetTier: String? = null,
    entryItemId: String? = null,
    entryKind: String? = null,
    entryPlacement: String? = null,
    entryPromotionVariant: String? = null,
    entrySourceSection: String? = null,
    entryCurrentTier: String? = null,
    entryPreviewNumber: String? = null,
    viewModel: PaywallViewModel = hiltViewModel(),
) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()
    val selectedPlan by viewModel.selectedPlan.collectAsState()
    val selectedBilling by viewModel.selectedBilling.collectAsState()
    val isPurchasing by viewModel.isPurchasing.collectAsState()
    val purchaseError by viewModel.purchaseError.collectAsState()
    val context = LocalContext.current
    val activity = context.findActivity()
    val uriHandler = LocalUriHandler.current
    var legalDocumentKind by remember { mutableStateOf<String?>(null) }
    var didApplyInitialPlan by remember(initialPlan) { mutableStateOf(false) }

    LaunchedEffect(
        resultAnalysisId,
        resultSection,
        resultFunnelSessionId,
        entryPoint,
        entryTargetTier,
        entryItemId,
        entryKind,
        entryPlacement,
        entryPromotionVariant,
        entrySourceSection,
        entryCurrentTier,
        entryPreviewNumber,
    ) {
        viewModel.begin(
            resultAnalysisId = resultAnalysisId,
            resultSection = resultSection,
            inheritedFunnelSessionId = resultFunnelSessionId,
            entryPoint = entryPoint,
            entryTargetTier = entryTargetTier,
            entryItemId = entryItemId,
            entryAttributes = buildMap {
                entryKind?.takeIf(String::isNotBlank)?.let { put("entry_kind", it) }
                entryPlacement?.takeIf(String::isNotBlank)?.let { put("placement", it) }
                entryPromotionVariant?.takeIf(String::isNotBlank)?.let { put("promotion_variant", it) }
                entrySourceSection?.takeIf(String::isNotBlank)?.let { put("source_section", it) }
                entryCurrentTier?.takeIf(String::isNotBlank)?.let { put("current_tier", it) }
                entryPreviewNumber?.takeIf(String::isNotBlank)?.let { put("preview_number", it) }
            },
        )
    }

    LaunchedEffect(state, initialPlan) {
        if (!didApplyInitialPlan && initialPlan != null && state is PaywallUiState.Loaded) {
            viewModel.applyInitialPlan(initialPlan)
            didApplyInitialPlan = true
        }
    }

    Box(modifier = Modifier.fillMaxSize().background(RdPaywallDesignColor.Surface)) {
        when (val current = state) {
            PaywallUiState.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.onyx)
            }

            PaywallUiState.SignedOut -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                RdEmptyState(
                    icon = Icons.Filled.WorkspacePremium,
                    title = stringResource(RdR.string.rd_oturum_yok),
                    subtitle = stringResource(RdR.string.rd_plan_yukseltmek_icin_giris),
                )
                if (onBack != null) {
                    TextButton(onClick = onBack) { Text(stringResource(RdR.string.rd_kapat)) }
                }
            }

            // Yükleme hatası da tasarım ekranında gösterilir: kullanıcı hatayı paywall'ın kendi
            // uyarı kartında görür ve CTA "Tekrar dene" olur (iOS ile aynı davranış).
            is PaywallUiState.Failed -> PaywallDesignSurface(
                viewModel = viewModel,
                selectedPlan = selectedPlan,
                selectedBilling = selectedBilling,
                isPurchasing = isPurchasing,
                loadError = current.error.message,
                currentPlanIncludesSelection = false,
                activity = activity,
                onBack = onBack,
                onTerms = { legalDocumentKind = "terms" },
                onPrivacy = { legalDocumentKind = "privacy" },
                onManage = { uriHandler.openUri(PLAY_SUBSCRIPTIONS_URL) },
                purchaseErrorMessage = purchaseError?.message,
            )

            is PaywallUiState.Loaded -> PaywallDesignSurface(
                viewModel = viewModel,
                selectedPlan = selectedPlan,
                selectedBilling = selectedBilling,
                isPurchasing = isPurchasing,
                loadError = null,
                currentPlanIncludesSelection = viewModel.selectionIsCurrentPlan(),
                activity = activity,
                onBack = onBack,
                onTerms = { legalDocumentKind = "terms" },
                onPrivacy = { legalDocumentKind = "privacy" },
                onManage = { uriHandler.openUri(PLAY_SUBSCRIPTIONS_URL) },
                purchaseErrorMessage = purchaseError?.message,
            )
        }
    }

    if (legalDocumentKind != null) {
        var documents by remember { mutableStateOf<List<RdLegalDocument>>(emptyList()) }
        LaunchedEffect(Unit) {
            documents = LegalDocumentAssets.load(context)
                .map { RdLegalDocument(kind = it.kind, title = it.title, text = it.text) }
        }
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(onDismissRequest = { legalDocumentKind = null }, sheetState = sheetState) {
            RdLegalDocumentSheet(
                documents = documents,
                initialKind = legalDocumentKind,
                onClose = { legalDocumentKind = null },
            )
        }
    }
}

@Composable
private fun PaywallDesignSurface(
    viewModel: PaywallViewModel,
    selectedPlan: PaywallPlan,
    selectedBilling: PaywallBilling,
    isPurchasing: Boolean,
    loadError: String?,
    currentPlanIncludesSelection: Boolean,
    activity: Activity?,
    onBack: (() -> Unit)?,
    onTerms: () -> Unit,
    onPrivacy: () -> Unit,
    onManage: () -> Unit,
    purchaseErrorMessage: String?,
) {
    val yearlyPackage = viewModel.packageFor(selectedPlan, PaywallBilling.Yearly)
    val monthlyPackage = viewModel.packageFor(selectedPlan, PaywallBilling.Monthly)
    val selectedPackage = if (selectedBilling == PaywallBilling.Yearly) yearlyPackage else monthlyPackage

    // Deneme rozeti yalnızca Play'in bu hesap için gerçekten döndürdüğü teklife dayanır.
    val trialDays = if (selectedPlan == PaywallPlan.Plus) {
        PaywallDesignPricing.trialDays(yearlyPackage?.freeTrialPeriodIso8601)
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
            if (loadError == null) {
                RdR.string.rd_paywall_design_price_loading
            } else {
                RdR.string.rd_paywall_design_price_unavailable
            },
        ),
        cta = RdPaywallDesignCta(
            title = ctaTitle(
                plan = selectedPlan,
                isPurchasing = isPurchasing,
                currentPlanIncludesSelection = currentPlanIncludesSelection,
                hasPackage = selectedPackage != null,
                hasLoadError = loadError != null,
                offersTrial = trialDays != null && selectedBilling == PaywallBilling.Yearly,
            ),
            isLoading = isPurchasing,
            isDisabled = isPurchasing ||
                currentPlanIncludesSelection ||
                (selectedPackage == null && loadError == null) ||
                activity == null,
        ),
        notice = if (isPurchasing) stringResource(RdR.string.rd_paywall_design_purchase_opening) else null,
        errorMessage = purchaseErrorMessage
            ?: loadError
            ?: stringResource(RdR.string.rd_paywall_design_package_missing).takeIf { selectedPackage == null },
    )

    RdPaywallDesignScreen(
        state = designState,
        onClose = {
            viewModel.recordClose()
            onBack?.invoke()
        },
        onSelectBilling = { viewModel.selectBilling(it.paywallBilling) },
        onCta = {
            viewModel.recordCtaTap()
            val target = selectedPackage
            when {
                target == null -> viewModel.load()
                activity != null -> viewModel.purchase(activity, target)
            }
        },
        onRestore = viewModel::restorePurchases,
        onTerms = onTerms,
        onPrivacy = onPrivacy,
        onManageSubscription = onManage,
        onCrossSell = viewModel::togglePlan,
    )
}

@Composable
private fun ctaTitle(
    plan: PaywallPlan,
    isPurchasing: Boolean,
    currentPlanIncludesSelection: Boolean,
    hasPackage: Boolean,
    hasLoadError: Boolean,
    offersTrial: Boolean,
): String = when {
    isPurchasing -> stringResource(RdR.string.rd_satin_alma_hazirlaniyor)
    currentPlanIncludesSelection -> stringResource(RdR.string.rd_planin_aktif)
    !hasPackage && hasLoadError -> stringResource(RdR.string.rd_tekrar_dene)
    !hasPackage -> stringResource(RdR.string.rd_paywall_design_cta_price_loading)
    offersTrial -> stringResource(RdR.string.rd_paywall_design_cta_start_trial)
    else -> stringResource(
        if (plan == PaywallPlan.Plus) RdR.string.rd_paywall_dark_plus_cta
        else RdR.string.rd_paywall_dark_pro_cta,
    )
}

/**
 * Ekran görüntüsü regresyon testleri için birebir aynı üretim bileşenlerinin belirlenimci
 * render'ı — mağaza/oturum bağımlılığı olmadan.
 */
@Composable
fun PaywallParityPreviewSurface(
    plan: PaywallPlan,
    billing: PaywallBilling,
    formattedPrice: String,
    monthlyPrice: String = formattedPrice,
    monthlyEquivalent: String? = null,
    trialDays: Int? = null,
    discountPercent: Int? = null,
) {
    val designState = rdPaywallDesignState(
        tier = plan.designTier,
        selectedBilling = billing.designBilling,
        yearlyPrice = formattedPrice,
        yearlyMonthlyEquivalent = monthlyEquivalent,
        monthlyPrice = monthlyPrice,
        trialDays = trialDays,
        discountPercent = discountPercent,
        priceUnavailableText = stringResource(RdR.string.rd_paywall_design_price_loading),
        cta = RdPaywallDesignCta(
            title = ctaTitle(
                plan = plan,
                isPurchasing = false,
                currentPlanIncludesSelection = false,
                hasPackage = true,
                hasLoadError = false,
                offersTrial = trialDays != null && billing == PaywallBilling.Yearly,
            ),
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

internal val PaywallPlan.designTier: RdPaywallDesignTier
    get() = when (this) {
        PaywallPlan.Plus -> RdPaywallDesignTier.Plus
        PaywallPlan.Pro -> RdPaywallDesignTier.Pro
    }

internal val PaywallBilling.designBilling: RdPaywallDesignBilling
    get() = when (this) {
        PaywallBilling.Yearly -> RdPaywallDesignBilling.Yearly
        PaywallBilling.Monthly -> RdPaywallDesignBilling.Monthly
    }

internal val RdPaywallDesignBilling.paywallBilling: PaywallBilling
    get() = when (this) {
        RdPaywallDesignBilling.Yearly -> PaywallBilling.Yearly
        RdPaywallDesignBilling.Monthly -> PaywallBilling.Monthly
    }

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
