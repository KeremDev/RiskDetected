package com.riskdetectedan.feature.onboarding

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OBTimelinePaywallScreenTest {
    @Test
    fun `loaded yearly package keeps onboarding seven day trial when store period is absent`() {
        assertEquals(7, resolvedOnboardingTrialDays(hasYearlyPackage = true, storePeriodIso8601 = null))
    }

    @Test
    fun `store trial period remains authoritative when it is available`() {
        assertEquals(14, resolvedOnboardingTrialDays(hasYearlyPackage = true, storePeriodIso8601 = "P2W"))
    }

    @Test
    fun `missing yearly product cannot advertise a trial`() {
        assertNull(resolvedOnboardingTrialDays(hasYearlyPackage = false, storePeriodIso8601 = null))
    }
}
