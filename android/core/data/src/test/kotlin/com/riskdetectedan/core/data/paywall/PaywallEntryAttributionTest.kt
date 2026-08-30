package com.riskdetectedan.core.data.paywall

import com.riskdetectedan.core.data.profile.SubscriptionTier
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

class PaywallEntryAttributionTest {
    @Test
    fun `entry attribution serializes backend column names and training section`() {
        val encoded = Json.parseToJsonElement(
            Json.encodeToString(
                PaywallEntryAttribution(
                    entryPoint = "result_hub_training_promotion",
                    entrySurface = "training_recommendations",
                    entryComponent = "result_membership_promotion",
                    entryTargetTier = SubscriptionTier.Pro,
                    analysisId = "11111111-1111-4111-8111-111111111111",
                    resultSection = "training_recommendations",
                    itemId = "training-card-1",
                    attributes = mapOf("client_platform" to "android"),
                ),
            ),
        ).jsonObject

        assertEquals("result_hub_training_promotion", encoded.getValue("entry_point").jsonPrimitive.content)
        assertEquals("training_recommendations", encoded.getValue("entry_surface").jsonPrimitive.content)
        assertEquals("result_membership_promotion", encoded.getValue("entry_component").jsonPrimitive.content)
        assertEquals("pro", encoded.getValue("entry_target_tier").jsonPrimitive.content)
        assertEquals("training_recommendations", encoded.getValue("result_section").jsonPrimitive.content)
    }
}
