package com.riskdetectedan.feature.onboarding

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OBTimelinePaywallPriceTest {
    @Test fun annualTurkishPriceIsDisplayedAsEffectiveMonthlyPrice() {
        assertEquals("₺208,33", effectiveMonthlyPrice(2_499_990_000L, "TRY"))
    }

    @Test fun invalidStoreCurrencyFailsClosed() {
        assertNull(effectiveMonthlyPrice(2_499_990_000L, "INVALID"))
        assertNull(effectiveMonthlyPrice(-1L, "TRY"))
    }

    @Test fun onlyAStoreVerifiedSevenDayPeriodGetsTrialCopy() {
        assertEquals(true, isSevenDayTrialPeriod("P7D"))
        assertEquals(true, isSevenDayTrialPeriod("P1W"))
        assertEquals(false, isSevenDayTrialPeriod("P14D"))
        assertEquals(false, isSevenDayTrialPeriod(null))
    }
}
