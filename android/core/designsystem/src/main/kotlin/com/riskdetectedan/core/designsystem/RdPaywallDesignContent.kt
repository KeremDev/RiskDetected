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

    /**
     * Şerit etiketleri. Yalnızca PRO'da bulunan bir özellik PLUS ekranında gösterilmez:
     * karşılaştırma tablosunda çarpı görünen bir özelliği aynı ekranda reklam etmemek için.
     */
    @Composable
    fun timelineFeatures(tier: RdPaywallDesignTier): List<RdPaywallDesignFeature> = listOfNotNull(
        RdPaywallDesignFeature(
            title = stringResource(R.string.rd_paywall_design_feature_risk_analysis),
            glyph = RdPaywallDesignGlyph.Shield,
        ),
        RdPaywallDesignFeature(
            title = stringResource(R.string.rd_paywall_design_feature_detailed_analysis),
            glyph = RdPaywallDesignGlyph.Chart,
        ),
        RdPaywallDesignFeature(
            title = stringResource(R.string.rd_paywall_design_feature_multi_photo),
            glyph = RdPaywallDesignGlyph.Photos,
        ),
        RdPaywallDesignFeature(
            title = stringResource(R.string.rd_paywall_design_feature_company_management),
            glyph = RdPaywallDesignGlyph.Building,
        ),
        RdPaywallDesignFeature(
            title = stringResource(R.string.rd_paywall_design_feature_fine_kinney),
            glyph = RdPaywallDesignGlyph.Gauge,
        ),
        RdPaywallDesignFeature(
            title = stringResource(R.string.rd_paywall_design_feature_matrix_5x5),
            glyph = RdPaywallDesignGlyph.Grid,
        ),
        RdPaywallDesignFeature(
            title = stringResource(R.string.rd_paywall_design_row_deep_research),
            glyph = RdPaywallDesignGlyph.Magnifier,
        ).takeIf { tier == RdPaywallDesignTier.Pro },
        RdPaywallDesignFeature(
            title = stringResource(R.string.rd_paywall_design_feature_report_customization),
            glyph = RdPaywallDesignGlyph.Sliders,
        ),
        RdPaywallDesignFeature(
            title = stringResource(R.string.rd_paywall_design_feature_archive_management),
            glyph = RdPaywallDesignGlyph.Archive,
        ),
        RdPaywallDesignFeature(
            title = stringResource(R.string.rd_paywall_design_feature_assignee),
            glyph = RdPaywallDesignGlyph.Assignee,
        ),
        RdPaywallDesignFeature(
            title = stringResource(R.string.rd_paywall_design_feature_focused_analysis),
            glyph = RdPaywallDesignGlyph.Target,
        ).takeIf { tier == RdPaywallDesignTier.Pro },
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
            right = RdPaywallDesignMark.Cross,
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
            left = RdPaywallDesignMark.Cross,
            right = RdPaywallDesignMark.Check(RdPaywallDesignColor.Green),
        ),
        RdPaywallDesignRow(
            title = stringResource(R.string.rd_paywall_design_feature_multi_photo),
            left = RdPaywallDesignMark.Check(RdPaywallDesignColor.Orange),
            right = RdPaywallDesignMark.Check(RdPaywallDesignColor.Green),
        ),
        RdPaywallDesignRow(
            title = stringResource(R.string.rd_paywall_design_feature_focused_analysis),
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

    // Öne çıkan satır aylık karşılık, altındaki küçük satır yıllık toplamdır: kullanıcı
    // aylık plana göre kıyaslayabilsin. Mağaza aylık karşılığı vermezse eski sıraya düşülür.
    val yearlyTotal = yearlyPrice ?: priceUnavailableText
    val annual = RdPaywallDesignPlanOption(
        title = stringResource(R.string.rd_yillik),
        price = yearlyMonthlyEquivalent
            ?.let { stringResource(R.string.rd_paywall_design_plan_per_month_format, it) }
            ?: yearlyTotal,
        caption = if (yearlyMonthlyEquivalent == null) {
            stringResource(R.string.rd_paywall_design_plan_yearly_caption)
        } else {
            stringResource(R.string.rd_paywall_design_plan_per_year_format, yearlyTotal)
        },
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
        timelineFeatures = RdPaywallDesignCopy.timelineFeatures(tier),
        comparisonLeft = when (tier) {
            RdPaywallDesignTier.Plus -> RdPaywallDesignColumn(
                freeName,
                RdPaywallDesignColor.Muted,
                FontWeight.SemiBold,
            )
            RdPaywallDesignTier.Pro -> RdPaywallDesignColumn(
                plusName,
                RdPaywallDesignColor.Orange,
                FontWeight.SemiBold,
                RdPaywallDesignEmblem.Crown,
            )
        },
        comparisonRight = when (tier) {
            RdPaywallDesignTier.Plus -> RdPaywallDesignColumn(
                plusName,
                RdPaywallDesignColor.Orange,
                FontWeight.Bold,
                RdPaywallDesignEmblem.Crown,
            )
            RdPaywallDesignTier.Pro -> RdPaywallDesignColumn(
                proName,
                RdPaywallDesignColor.Green,
                FontWeight.Bold,
                RdPaywallDesignEmblem.Star,
            )
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
        purchaseDisclosure = when {
            selectedBilling == RdPaywallDesignBilling.Yearly && trialDays != null && yearlyPrice != null ->
                stringResource(
                    R.string.rd_paywall_dark_trial_disclosure_yearly_format,
                    trialDays,
                    yearlyPrice,
                )
            selectedBilling == RdPaywallDesignBilling.Yearly && yearlyPrice != null ->
                stringResource(
                    R.string.rd_paywall_dark_cancellable_disclosure_format,
                    stringResource(R.string.rd_paywall_design_footer_renewal_yearly_format, yearlyPrice),
                )
            selectedBilling == RdPaywallDesignBilling.Monthly && monthlyPrice != null ->
                stringResource(
                    R.string.rd_paywall_dark_cancellable_disclosure_format,
                    stringResource(R.string.rd_paywall_design_footer_renewal_monthly_format, monthlyPrice),
                )
            else -> null
        },
        crossSell = crossSell,
    )
}
