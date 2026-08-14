package com.riskdetectedan.core.data.billing

import com.revenuecat.purchases.models.StoreReplacementMode
import com.riskdetectedan.core.data.profile.SubscriptionTier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SubscriptionChangePolicyTest {
    @Test
    fun `same product ignores Play base plan suffix`() {
        assertTrue(sameStoreProduct("riskdetected_plus_monthly:monthly", "riskdetected_plus_monthly"))
        assertFalse(sameStoreProduct("riskdetected_plus_monthly", "riskdetected_plus_yearly"))
    }

    @Test
    fun `billing-period change on same tier is deferred`() {
        assertEquals(
            StoreReplacementMode.DEFERRED,
            replacementModeFor(SubscriptionTier.Plus, SubscriptionTier.Plus),
        )
    }

    @Test
    fun `plus to pro uses prorated upgrade`() {
        assertEquals(
            StoreReplacementMode.CHARGE_PRORATED_PRICE,
            replacementModeFor(SubscriptionTier.Plus, SubscriptionTier.Pro),
        )
    }
}
