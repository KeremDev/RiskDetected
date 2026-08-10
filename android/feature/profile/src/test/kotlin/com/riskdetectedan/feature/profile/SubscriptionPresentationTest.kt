package com.riskdetectedan.feature.profile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SubscriptionPresentationTest {
    @Test
    fun knownPeriodsAreMappedExplicitly() {
        assertEquals(SubscriptionPeriodValue.Monthly, subscriptionPeriodValue("monthly"))
        assertEquals(SubscriptionPeriodValue.Yearly, subscriptionPeriodValue(" YEARLY "))
        assertEquals(SubscriptionPeriodValue.Missing, subscriptionPeriodValue(null))
    }

    @Test
    fun unknownPeriodIsNotMislabelledAsMonthly() {
        assertEquals(SubscriptionPeriodValue.Unknown("trial"), subscriptionPeriodValue("trial"))
    }

    @Test
    fun renewalDateUsesIstanbulTurkishLongDate() {
        assertEquals("10 Ağustos 2026", formatSubscriptionRenewal("2026-08-10T09:00:00Z"))
        assertNull(formatSubscriptionRenewal("not-a-date"))
    }
}
