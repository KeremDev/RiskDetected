package com.riskdetectedan.core.data.billing

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Paywall'ın mağaza verisinden türettiği her sayı burada sınanır. Kural: veri eksik ya da
 * anlamsızsa hiçbir vaat gösterilmez (deneme rozeti, indirim rozeti, aylık karşılık).
 */
class PaywallDesignPricingTest {

    @Test fun `store verified trial periods convert to days`() {
        assertEquals(7, PaywallDesignPricing.trialDays("P7D"))
        assertEquals(7, PaywallDesignPricing.trialDays("P1W"))
        assertEquals(14, PaywallDesignPricing.trialDays("P2W"))
        assertEquals(30, PaywallDesignPricing.trialDays("P1M"))
        assertEquals(3, PaywallDesignPricing.trialDays("P3D"))
    }

    @Test fun `missing or unparsable trial period shows no trial promise`() {
        assertNull(PaywallDesignPricing.trialDays(null))
        assertNull(PaywallDesignPricing.trialDays(""))
        assertNull(PaywallDesignPricing.trialDays("7 gün"))
        assertNull(PaywallDesignPricing.trialDays("P0D"))
    }

    @Test fun `yearly discount is computed against twelve monthly payments`() {
        // 2.499,99 ₺/yıl ile 249,99 ₺/ay: 2.999,88 ₺ yerine 2.499,99 ₺ → %17.
        assertEquals(17, PaywallDesignPricing.discountPercent(2_499_990_000L, 249_990_000L))
    }

    @Test fun `no discount badge without a real saving`() {
        assertNull(PaywallDesignPricing.discountPercent(2_999_880_000L, 249_990_000L))
        assertNull(PaywallDesignPricing.discountPercent(3_500_000_000L, 249_990_000L))
        assertNull(PaywallDesignPricing.discountPercent(null, 249_990_000L))
        assertNull(PaywallDesignPricing.discountPercent(2_499_990_000L, null))
        assertNull(PaywallDesignPricing.discountPercent(2_499_990_000L, 0L))
    }

    @Test fun `discounts below the five percent threshold stay hidden`() {
        // 2.899,00 ₺/yıl ile 249,99 ₺/ay → yaklaşık %3, rozet gösterilmez.
        assertNull(PaywallDesignPricing.discountPercent(2_899_000_000L, 249_990_000L))
    }

    @Test fun `annual price is shown as an effective monthly price`() {
        assertEquals("₺208,33", PaywallDesignPricing.monthlyEquivalent(2_499_990_000L, "TRY"))
    }

    @Test fun `invalid store currency fails closed`() {
        assertNull(PaywallDesignPricing.monthlyEquivalent(2_499_990_000L, "INVALID"))
        assertNull(PaywallDesignPricing.monthlyEquivalent(-1L, "TRY"))
        assertNull(PaywallDesignPricing.monthlyEquivalent(2_499_990_000L, " "))
    }

    @Test fun `billing period is resolved from the store identifiers`() {
        assertTrue(PaywallDesignPricing.matchesYearly(ANNUAL_ID, "riskdetected_plus_yearly:yearly"))
        assertTrue(PaywallDesignPricing.matchesMonthly(MONTHLY_ID, "riskdetected_plus_monthly:monthly"))
        assertFalse(PaywallDesignPricing.matchesMonthly(ANNUAL_ID, "riskdetected_plus_yearly:yearly"))
        assertFalse(PaywallDesignPricing.matchesYearly(MONTHLY_ID, "riskdetected_plus_monthly:monthly"))
    }

    @Test fun `an unrecognised identifier matches no period`() {
        assertFalse(PaywallDesignPricing.matchesYearly("lifetime", "riskdetected_plus_lifetime"))
        assertFalse(PaywallDesignPricing.matchesMonthly("lifetime", "riskdetected_plus_lifetime"))
    }

    private companion object {
        const val ANNUAL_ID = "annual_package"
        const val MONTHLY_ID = "monthly_package"
    }
}
