package com.riskdetectedan.core.data.billing

import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

/**
 * Paywall'ın mağaza verisinden türettiği sayısal değerler — `PaywallDesignFlowView.swift`'teki
 * `trialDays`, `discountText` ve `displayMonthlyEquivalentPrice` hesaplarının karşılığı.
 *
 * Hiçbir metin/yerelleştirme kararı burada verilmez; yalnızca Google Play'in gerçekten
 * döndürdüğü değerler işlenir. Fiyat vaadi uydurmamak için her hesap, veri eksikse `null` döner
 * (iOS ile aynı kural: teklif yoksa deneme rozeti de indirim rozeti de gösterilmez).
 */
object PaywallDesignPricing {

    /** Yıllık paket rozeti için en düşük anlamlı indirim yüzdesi (iOS ile aynı eşik). */
    const val MIN_DISCOUNT_PERCENT = 5

    /**
     * ISO-8601 abonelik dönemini gün sayısına çevirir (`P7D`, `P1W`, `P1M`…).
     * Play yalnızca mevcut hesabın gerçekten hak kazandığı ücretsiz deneme dönemini döndürür.
     */
    fun trialDays(periodIso8601: String?): Int? {
        val period = periodIso8601?.trim()?.uppercase(Locale.ROOT)?.takeIf { it.isNotEmpty() } ?: return null
        val match = ISO_PERIOD.matchEntire(period) ?: return null
        val (years, months, weeks, days) = match.destructured
        val total = (years.toIntOrNull() ?: 0) * 365 +
            (months.toIntOrNull() ?: 0) * 30 +
            (weeks.toIntOrNull() ?: 0) * 7 +
            (days.toIntOrNull() ?: 0)
        return total.takeIf { it > 0 }
    }

    /**
     * Yıllık paketin, aynı planın aylık paketine göre gerçek indirimi (yüzde).
     * Fark [MIN_DISCOUNT_PERCENT] altındaysa rozet gösterilmez.
     */
    fun discountPercent(yearlyPriceMicros: Long?, monthlyPriceMicros: Long?): Int? {
        val yearly = yearlyPriceMicros?.takeIf { it > 0 } ?: return null
        val monthly = monthlyPriceMicros?.takeIf { it > 0 } ?: return null
        val fullYear = monthly * 12
        if (fullYear <= yearly) return null
        val percent = Math.round((fullYear - yearly).toDouble() / fullYear.toDouble() * 100.0).toInt()
        return percent.takeIf { it >= MIN_DISCOUNT_PERCENT }
    }

    /** Yıllık paketin aylığa bölünmüş, mağazanın kendi para biriminde biçimlenmiş karşılığı. */
    fun monthlyEquivalent(billingPackage: BillingPackage?, locale: Locale = Locale.getDefault()): String? {
        val micros = billingPackage?.priceAmountMicros ?: return null
        val currencyCode = billingPackage.currencyCode?.takeIf { it.isNotBlank() } ?: return null
        return monthlyEquivalent(micros, currencyCode, locale)
    }

    fun monthlyEquivalent(
        priceAmountMicros: Long,
        currencyCode: String,
        locale: Locale = Locale.getDefault(),
    ): String? {
        if (priceAmountMicros < 0 || currencyCode.isBlank()) return null
        return runCatching {
            val formatted = NumberFormat.getCurrencyInstance(locale).apply {
                currency = Currency.getInstance(currencyCode)
                maximumFractionDigits = 2
                minimumFractionDigits = 2
            }.format(priceAmountMicros / 1_000_000.0 / 12.0)
            // Some locale/currency pairs (for example en-US + TRY) are emitted as
            // `TRY208.33`. Google Play's own formatted prices separate the ISO code from
            // the amount; keep the derived monthly equivalent equally readable.
            ISO_CURRENCY_CODE_TOUCHING_AMOUNT.find(formatted)?.let { prefix ->
                val insertionIndex = prefix.range.last + 1
                formatted.replaceRange(insertionIndex, insertionIndex, "\u00A0")
            } ?: formatted
        }.getOrNull()
    }

    /**
     * RevenueCat paket/ürün kimliğinden faturalama dönemini çözer — iOS'taki
     * `matchesDesignPaywall(_:)` ile aynı belirteç listesi.
     */
    fun matchesYearly(billingPackage: BillingPackage): Boolean =
        matchesYearly(billingPackage.id, billingPackage.productId)

    fun matchesMonthly(billingPackage: BillingPackage): Boolean =
        matchesMonthly(billingPackage.id, billingPackage.productId)

    fun matchesYearly(packageId: String, productId: String): Boolean =
        token(packageId, productId).let { token -> YEARLY_TOKENS.any { token.contains(it) } }

    /** Yıllık belirteci taşıyan bir kimlik asla aylık sayılmaz ("yearly" içinde "year" var, ama
     * "aylık" içinde de "ay" var — sıralama önemli). */
    fun matchesMonthly(packageId: String, productId: String): Boolean =
        !matchesYearly(packageId, productId) &&
            token(packageId, productId).let { token -> MONTHLY_TOKENS.any { token.contains(it) } }

    private fun token(packageId: String, productId: String): String =
        "$packageId $productId".lowercase(Locale.ROOT)

    private val YEARLY_TOKENS = listOf("annual", "yearly", "year", "yillik", "yıllık")
    private val MONTHLY_TOKENS = listOf("monthly", "month", "aylik", "aylık")

    private val ISO_CURRENCY_CODE_TOUCHING_AMOUNT = Regex("^[A-Z]{3}(?=\\d)")

    private val ISO_PERIOD =
        Regex("""^P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)W)?(?:(\d+)D)?$""")
}
