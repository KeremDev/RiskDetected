package com.riskdetectedan.feature.paywall

import com.riskdetectedan.core.data.profile.SubscriptionTier
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PaywallSelectionPolicyTest {
    @Test
    fun `monthly plus member can select yearly plus`() {
        assertFalse(
            selectionIsUnavailableAsCurrentOrLower(
                currentTier = SubscriptionTier.Plus,
                currentProductId = "riskdetected_plus_monthly:monthly",
                targetTier = SubscriptionTier.Plus,
                targetProductId = "riskdetected_plus_yearly:yearly",
            ),
        )
    }

    @Test
    fun `monthly plus member cannot repurchase exact monthly product`() {
        assertTrue(
            selectionIsUnavailableAsCurrentOrLower(
                currentTier = SubscriptionTier.Plus,
                currentProductId = "riskdetected_plus_monthly:monthly",
                targetTier = SubscriptionTier.Plus,
                targetProductId = "riskdetected_plus_monthly",
            ),
        )
    }

    @Test
    fun `plus member can select both pro periods`() {
        listOf("riskdetected_pro_monthly:monthly", "riskdetected_pro_yearly:yearly").forEach { productId ->
            assertFalse(
                selectionIsUnavailableAsCurrentOrLower(
                    currentTier = SubscriptionTier.Plus,
                    currentProductId = "riskdetected_plus_monthly:monthly",
                    targetTier = SubscriptionTier.Pro,
                    targetProductId = productId,
                ),
            )
        }
    }

    @Test
    fun `pro member cannot select plus downgrade`() {
        assertTrue(
            selectionIsUnavailableAsCurrentOrLower(
                currentTier = SubscriptionTier.Pro,
                currentProductId = "riskdetected_pro_monthly:monthly",
                targetTier = SubscriptionTier.Plus,
                targetProductId = "riskdetected_plus_yearly:yearly",
            ),
        )
    }
}
