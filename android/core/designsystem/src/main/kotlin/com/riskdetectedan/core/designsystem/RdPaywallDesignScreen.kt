package com.riskdetectedan.core.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp

/**
 * Claude Design paywall ekranının veri güdümlü gövdesi — `PaywallDesignScreen.swift` karşılığı.
 * Aynı düzen hem PLUS hem PRO tasarımını üretir; fark vurgu rengi, karşılaştırma sütunları ve
 * çapraz satış kartıdır. Hiç iş mantığı taşımaz: paket/fiyat/satın alma akışını çağıran özellik
 * modülü (`feature:paywall` uygulama içi, `feature:onboarding` 11. adım) hazırlar.
 */
enum class RdPaywallDesignTier { Plus, Pro }

enum class RdPaywallDesignBilling { Yearly, Monthly }

data class RdPaywallDesignPlanOption(
    val title: String,
    val price: String,
    val caption: String,
    val trialNote: String? = null,
    val badgeLabel: String? = null,
    val badgeDiscount: String? = null,
)

data class RdPaywallDesignCta(
    val title: String,
    val isLoading: Boolean = false,
    val isDisabled: Boolean = false,
)

data class RdPaywallDesignCrossSell(
    val target: RdPaywallDesignTier,
    val prefix: String,
    val highlight: String,
    val suffix: String,
)

data class RdPaywallDesignState(
    val tier: RdPaywallDesignTier,
    val heroLabel: String,
    val tierName: String,
    val showsTrialTimeline: Boolean,
    val trialDays: Int,
    val timelineFeatures: List<String>,
    val comparisonLeft: RdPaywallDesignColumn,
    val comparisonRight: RdPaywallDesignColumn,
    val comparisonRows: List<RdPaywallDesignRow>,
    val annual: RdPaywallDesignPlanOption,
    val monthly: RdPaywallDesignPlanOption,
    val selectedBilling: RdPaywallDesignBilling,
    val cta: RdPaywallDesignCta,
    val notice: String? = null,
    val errorMessage: String? = null,
    val crossSell: RdPaywallDesignCrossSell? = null,
)

val RdPaywallDesignTier.accent: Color
    get() = when (this) {
        RdPaywallDesignTier.Plus -> RdPaywallDesignColor.Orange
        RdPaywallDesignTier.Pro -> RdPaywallDesignColor.Green
    }

val RdPaywallDesignTier.selectedBackground: Color
    get() = when (this) {
        RdPaywallDesignTier.Plus -> RdPaywallDesignColor.OrangeCardBg
        RdPaywallDesignTier.Pro -> RdPaywallDesignColor.GreenCardBg
    }

/** Telefon dışı geniş ekranlarda tasarımın gerilmemesi için içerik sütunu bu genişlikte durur. */
private val MaxContentWidth = 480.dp

@Composable
fun RdPaywallDesignScreen(
    state: RdPaywallDesignState,
    onClose: () -> Unit,
    onSelectBilling: (RdPaywallDesignBilling) -> Unit,
    onCta: () -> Unit,
    onRestore: () -> Unit,
    onTerms: () -> Unit,
    onPrivacy: () -> Unit,
    onManageSubscription: () -> Unit,
    onCrossSell: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scrollState = rememberScrollState()
    // Ekran değiştiğinde (PLUS ↔ PRO) kaydırma konumu başa dönsün; aksi halde kullanıcı yeni
    // ekranın ortasına düşüyor (iOS'taki `.id(screen)` davranışının karşılığı).
    LaunchedEffect(state.tier) { scrollState.scrollTo(0) }

    val showsTimeline = state.showsTrialTimeline && state.selectedBilling == RdPaywallDesignBilling.Yearly
    val screenTag = when (state.tier) {
        RdPaywallDesignTier.Plus -> RdPaywallDesignTag.Plus
        RdPaywallDesignTier.Pro -> RdPaywallDesignTag.Pro
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(RdPaywallDesignColor.Surface)
            .testTag(screenTag),
    ) {
        Box(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentAlignment = Alignment.TopCenter,
        ) {
            Column(
                modifier = Modifier
                    .widthIn(max = MaxContentWidth)
                    .fillMaxHeight()
                    .verticalScroll(scrollState),
            ) {
                RdPaywallDesignHero(label = state.heroLabel, onClose = onClose)

                RdPaywallDesignSocialProof()

                if (showsTimeline) {
                    RdPaywallDesignTrialTimeline(
                        trialDays = state.trialDays,
                        tierName = state.tierName,
                    )
                    // Özellikler artık ilk satırın altındaki ızgarada değil,
                    // zaman çizelgesinin altında sürekli akan bir şeritte.
                    RdPaywallDesignFeatureMarquee(
                        features = state.timelineFeatures,
                        accent = state.tier.accent,
                    )
                } else {
                    RdPaywallDesignComparisonTable(
                        left = state.comparisonLeft,
                        right = state.comparisonRight,
                        rows = state.comparisonRows,
                    )
                }

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(
                            top = 22.dp,
                            start = RdPaywallDesignMetric.ScreenPadding,
                            end = RdPaywallDesignMetric.ScreenPadding,
                            // PLUS tasarımında plan kartları ile çapraz satış arası 24dp, PRO'da 22dp.
                            bottom = if (state.tier == RdPaywallDesignTier.Plus) 24.dp else 22.dp,
                        )
                        .height(IntrinsicSize.Min),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    PlanCard(
                        option = state.annual,
                        state = state,
                        billing = RdPaywallDesignBilling.Yearly,
                        tag = RdPaywallDesignTag.PlanYearly,
                        onSelectBilling = onSelectBilling,
                        modifier = Modifier.weight(1f),
                    )
                    PlanCard(
                        option = state.monthly,
                        state = state,
                        billing = RdPaywallDesignBilling.Monthly,
                        tag = RdPaywallDesignTag.PlanMonthly,
                        onSelectBilling = onSelectBilling,
                        modifier = Modifier.weight(1f),
                    )
                }

                state.crossSell?.let { crossSell ->
                    CrossSellCard(
                        crossSell = crossSell,
                        onTap = onCrossSell,
                        modifier = Modifier
                            .padding(
                                start = RdPaywallDesignMetric.ScreenPadding,
                                end = RdPaywallDesignMetric.ScreenPadding,
                                bottom = 22.dp,
                            ),
                    )
                }
            }
        }

        Box(
            modifier = Modifier.fillMaxWidth().background(RdPaywallDesignColor.Surface),
            contentAlignment = Alignment.TopCenter,
        ) {
            RdPaywallDesignFooter(
                ctaTitle = state.cta.title,
                isLoading = state.cta.isLoading,
                isDisabled = state.cta.isDisabled,
                accent = state.tier.accent,
                notice = state.notice,
                errorMessage = state.errorMessage,
                onCta = onCta,
                onRestore = onRestore,
                onTerms = onTerms,
                onPrivacy = onPrivacy,
                onManageSubscription = onManageSubscription,
                modifier = Modifier.widthIn(max = MaxContentWidth),
            )
        }
    }
}

@Composable
private fun PlanCard(
    option: RdPaywallDesignPlanOption,
    state: RdPaywallDesignState,
    billing: RdPaywallDesignBilling,
    tag: String,
    onSelectBilling: (RdPaywallDesignBilling) -> Unit,
    modifier: Modifier = Modifier,
) {
    RdPaywallDesignPlanCard(
        title = option.title,
        price = option.price,
        caption = option.caption,
        trialNote = option.trialNote,
        badgeLabel = option.badgeLabel,
        badgeDiscount = option.badgeDiscount,
        accent = state.tier.accent,
        selectedBackground = state.tier.selectedBackground,
        isSelected = state.selectedBilling == billing,
        testTag = tag,
        onTap = { onSelectBilling(billing) },
        modifier = modifier,
    )
}

@Composable
private fun CrossSellCard(
    crossSell: RdPaywallDesignCrossSell,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isPro = crossSell.target == RdPaywallDesignTier.Pro
    RdPaywallDesignUpsellCard(
        icon = {
            if (isPro) {
                RdPaywallStarIcon(color = RdPaywallDesignColor.Green)
            } else {
                RdPaywallCrownIcon(color = RdPaywallDesignColor.Amber)
            }
        },
        borderColor = if (isPro) RdPaywallDesignColor.Green else RdPaywallDesignColor.Amber,
        background = if (isPro) RdPaywallDesignColor.GreenCardBg else RdPaywallDesignColor.AmberCardBg,
        prefix = crossSell.prefix,
        highlight = crossSell.highlight,
        highlightColor = if (isPro) RdPaywallDesignColor.Green else RdPaywallDesignColor.AmberInk,
        suffix = crossSell.suffix,
        testTag = if (isPro) RdPaywallDesignTag.CrossSellPro else RdPaywallDesignTag.CrossSellPlus,
        onTap = onTap,
        modifier = modifier,
    )
}
