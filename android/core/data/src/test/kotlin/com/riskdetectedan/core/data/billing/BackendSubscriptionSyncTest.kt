package com.riskdetectedan.core.data.billing

import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.profile.SubscriptionTier
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BackendSubscriptionSyncTest {
    @Test
    fun androidPlatformIsAlwaysPresentInSyncRequest() {
        val encoded = Json.encodeToString(
            BackendSubscriptionSyncRequest(clientPlatform = "android"),
        )
        assertTrue(encoded.contains("\"client_platform\":\"android\""))
    }

    @Test
    fun matchingBackendTierIsAccepted() {
        assertEquals(
            RdResult.Success(SubscriptionTier.Plus),
            validateBackendSubscriptionTier(
                expected = SubscriptionTier.Plus,
                resolved = SubscriptionTier.Plus,
            ),
        )
    }

    @Test
    fun missingOrDifferentBackendTierFailsClosed() {
        assertTrue(
            validateBackendSubscriptionTier(
                expected = SubscriptionTier.Plus,
                resolved = null,
            ) is RdResult.Failure,
        )
        assertTrue(
            validateBackendSubscriptionTier(
                expected = SubscriptionTier.Plus,
                resolved = SubscriptionTier.Free,
            ) is RdResult.Failure,
        )
    }
}
