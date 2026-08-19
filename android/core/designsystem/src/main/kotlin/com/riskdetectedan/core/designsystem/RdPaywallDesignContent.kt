package com.riskdetectedan.core.designsystem

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight

/**
 * Paywall metin ve satır içeriği — `PaywallDesignFlowView.swift`'teki `PaywallDesignCopy` ve
 * görünüm-verisi hesaplayıcılarının karşılığı.
 *
 * Burada durur çünkü hem `feature:paywall` (uygulama içi) hem `feature:onboarding` (11. adım)
 * aynı ekranı gösterir ve iki modül birbirine bağlı değildir; ortak nokta `core:designsystem`.
 * Mağaza/paket bilgisi buraya ham değer olarak gelir (fiyat metni, deneme günü, indirim yüzdesi)
 * — bu dosya hiçbir zaman RevenueCat ya da veri katmanı tipi tanımaz.
 */
object RdPaywallDesignCopy {

    @Composable
    fun tierName(tier: RdPaywallDesignTier): String = when (tier) {
        RdPaywallDesignTier.Plus -> stringResource(R.string.rd_paywall_design_tier_plus)
        RdPaywallDesignTier.Pro -> stringResource(R.string.rd_paywall_design_tier_pro)
    }

    @Composable
    fun freeTierName(): String = stringResource(R.string.rd_paywall_design_tier_free)

    @Composable
    fun timelineFeatures(): List<String> = listOf(
        stringResource(R.string.rd_paywall_design_feature_risk_analysis),
        stringResource(R.string.rd_paywall_design_feature_detailed_analysis),
        stringResource(R.string.rd_paywall_design_feature_multi_photo),
        stringResource(R.string.rd_paywall_design_feature_company_management),
    )

    @Composable
    fun freeVersusPlusRows(): List<RdPaywallDesignRow> = listOf(
        RdPaywallDesignRow(
            title = stringResource(R.string.rd_paywall_design_row_daily_analysis),
            left = RdPaywallDesignMark.Value(
                stringResource(R.string.rd_paywall_design_value_one_per_day),
                RdPaywallDesignColor.Muted,
            ),
            right = RdPaywallDesignMark.Value(
                stringResource(R.string.rd_paywall_design_value_ten_per_day),
                RdPaywallDesignColor.Orange,
            ),
        ),
        RdPaywallDesignRow(
            title = stringResource(R.string.rd_paywall_design_feature_risk_analysis),
            left = RdPaywallDesignMark.Cross,
            right = RdPaywallDesignMark.Check(RdPaywallDesignColor.Orange),
        ),
        RdPaywallDesignRow(
            title = stringResource(R.string.rd_paywall_design_feature_detailed_analysis),
            left = RdPaywallDesignMark.Cross,
            right = RdPaywallDesignMark.Check(RdPaywallDesignColor.Orange),
        ),
        RdPaywallDesignRow(
            title = stringResource(R.string.rd_paywall_design_row_deep_research),
            left = RdPaywallDesignMark.Cross,
            right = RdPaywallDesignMark.Check(RdPaywallDesignColor.Orange),
        ),
        RdPaywallDesignRow(
            title = stringResource(R.string.rd_paywall_design_feature_multi_photo),
            left = RdPaywallDesignMark.Cross,
            right = RdPaywallDesignMark.Check(RdPaywallDesignColor.Orange),
        ),
        RdPaywallDesignRow(
            title = stringResource(R.string.rd_paywall_design_feature_company_management),
            left = RdPaywallDesignMark.Cross,
            right = RdPaywallDesignMark.Check(RdPaywallDesignColor.Orange),
        ),
    )

    @Composable
    fun plusVersusProRows(): List<RdPaywallDesignRow> = listOf(
        RdPaywallDesignRow(
            title = stringResource(R.string.rd_paywall_design_row_daily_analysis),
            left = RdPaywallDesignMark.Value(
                stringResource(R.string.rd_paywall_design_value_ten_per_day),
                RdPaywallDesignColor.Orange,
            ),
            right = RdPaywallDesignMark.Value(
                stringResource(R.string.rd_paywall_design_value_unlimited),
                RdPaywallDesignColor.Green,
            ),
        ),
        RdPaywallDesignRow(
            title = stringResource(R.string.rd_paywall_design_feature_risk_analysis),
            left = RdPaywallDesignMark.Check(RdPaywallDesignColor.Orange),
            right = RdPaywallDesignMark.Check(RdPaywallDesignColor.Green),
        ),
        RdPaywallDesignRow(
            title = stringResource(R.string.rd_paywall_design_feature_detailed_analysis),
            left = RdPaywallDesignMark.Check(RdPaywallDesignColor.Orange),
            right = RdPaywallDesignMark.Check(RdPaywallDesignColor.Green),
        ),
        RdPaywallDesignRow(
            title = stringResource(R.string.rd_paywall_design_row_deep_research),
            left = RdPaywallDesignMark.Check(RdPaywallDesignColor.Orange),
            right = RdPaywallDesignMark.Check(RdPaywallDesignColor.Green),
        ),
        RdPaywallDesignRow(
            title = stringResource(R.string.rd_paywall_design_feature_multi_photo),
            left = RdPaywallDesignMark.Check(RdPaywallDesignColor.Orange),
            right = RdPaywallDesignMark.Check(RdPaywallDesignColor.Green),
        ),
        RdPaywallDesignRow(
            title = stringResource(R.string.rd_paywall_design_row_priority_support),
            left = RdPaywallDesignMark.Cross,
            right = RdPaywallDesignMark.Check(RdPaywallDesignColor.Green),
        ),
    )
}

/**
 * Mağazadan gelen ham değerleri ekranın beklediği duruma çevirir.
 *
 * @param trialDays Google Play'de bu hesap için gerçekten geçerli olan ücretsiz deneme gün
 *   sayısı; `null` ise deneme anlatımı yerine karşılaştırma tablosu gösterilir (iOS ile aynı
 *   kural — teklif yoksa deneme vaadi de yoktur).
 * @param discountPercent Yıllık paketin aylık×12'ye göre gerçek indirimi; anlamlı değilse `null`.
 */
@Composable
fun rdPaywallDesignState(
    tier: RdPaywallDesignTier,
    selectedBilling: RdPaywallDesignBilling,
    yearlyPrice: String?,
    yearlyMonthlyEquivalent: String?,
    monthlyPrice: String?,
    trialDays: Int?,
    discountPercent: Int?,
    priceUnavailableText: String,
    cta: RdPaywallDesignCta,
    notice: String? = null,
    errorMessage: String? = null,
    showsCrossSell: Boolean = true,
): RdPaywallDesignState {
    val tierName = RdPaywallDesignCopy.tierName(tier)
    val freeName = RdPaywallDesignCopy.freeTierName()
    val plusName = RdPaywallDesignCopy.tierName(RdPaywallDesignTier.Plus)
    val proName = RdPaywallDesignCopy.tierName(RdPaywallDesignTier.Pro)

    // Deneme anlatımı yalnızca PLUS + yıllık pakette ve gerçek bir Play teklifi varsa görünür.
    val showsTrialTimeline = tier == RdPaywallDesignTier.Plus && trialDays != null

    val heroLabel = if (showsTrialTimeline && selectedBilling == RdPaywallDesignBilling.Yearly) {
        stringResource(R.string.rd_paywall_design_hero_trial)
    } else {
        stringResource(R.string.rd_paywall_design_hero_benefits_format, tierName)
    }

    val annual = RdPaywallDesignPlanOption(
        title = stringResource(R.string.rd_yillik),
        price = yearlyPrice ?: priceUnavailableText,
        caption = yearlyMonthlyEquivalent
            ?.let { stringResource(R.string.rd_paywall_design_plan_per_month_format, it) }
            ?: stringResource(R.string.rd_paywall_design_plan_yearly_caption),
        trialNote = trialDays?.let {
            stringResource(R.string.rd_paywall_design_plan_trial_note_format, it.toString())
        },
        badgeLabel = stringResource(R.string.rd_paywall_design_plan_badge_popular),
        badgeDiscount = discountPercent?.let {
            stringResource(R.string.rd_paywall_design_plan_discount_format, it.toString())
        },
    )

    val monthly = RdPaywallDesignPlanOption(
        title = stringResource(R.string.rd_aylik),
        price = monthlyPrice ?: priceUnavailableText,
        caption = stringResource(R.string.rd_paywall_design_plan_monthly_caption),
    )

    val crossSell = when {
        !showsCrossSell -> null
        tier == RdPaywallDesignTier.Plus -> RdPaywallDesignCrossSell(
            target = RdPaywallDesignTier.Pro,
            prefix = stringResource(R.string.rd_paywall_design_cross_sell_pro_prefix),
            highlight = proName,
            suffix = stringResource(R.string.rd_paywall_design_cross_sell_pro_suffix),
        )
        else -> RdPaywallDesignCrossSell(
            target = RdPaywallDesignTier.Plus,
            prefix = stringResource(R.string.rd_paywall_design_cross_sell_plus_prefix),
            highlight = plusName,
            suffix = stringResource(R.string.rd_paywall_design_cross_sell_plus_suffix),
        )
    }

    return RdPaywallDesignState(
        tier = tier,
        heroLabel = heroLabel,
        tierName = tierName,
        showsTrialTimeline = showsTrialTimeline,
        trialDays = trialDays ?: 7,
        timelineFeatures = RdPaywallDesignCopy.timelineFeatures(),
        comparisonLeft = when (tier) {
            RdPaywallDesignTier.Plus -> RdPaywallDesignColumn(freeName, RdPaywallDesignColor.Muted, FontWeight.SemiBold)
            RdPaywallDesignTier.Pro -> RdPaywallDesignColumn(plusName, RdPaywallDesignColor.Orange, FontWeight.SemiBold)
        },
        comparisonRight = when (tier) {
            RdPaywallDesignTier.Plus -> RdPaywallDesignColumn(plusName, RdPaywallDesignColor.Orange, FontWeight.Bold)
            RdPaywallDesignTier.Pro -> RdPaywallDesignColumn(proName, RdPaywallDesignColor.Green, FontWeight.Bold)
        },
        comparisonRows = when (tier) {
            RdPaywallDesignTier.Plus -> RdPaywallDesignCopy.freeVersusPlusRows()
            RdPaywallDesignTier.Pro -> RdPaywallDesignCopy.plusVersusProRows()
        },
        annual = annual,
        monthly = monthly,
        selectedBilling = selectedBilling,
        cta = cta,
        notice = notice,
        errorMessage = errorMessage,
        crossSell = crossSell,
    )
}
