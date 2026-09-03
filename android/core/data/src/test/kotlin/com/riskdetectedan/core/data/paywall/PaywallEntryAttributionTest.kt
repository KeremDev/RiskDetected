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

    @Test
    fun `entry context mirrors ios nesting used by attribution dashboard`() {
        val context = PaywallEntryAttribution(
            entryPoint = "result_hub_training_promotion",
            entrySurface = "training_recommendations",
            entryComponent = "result_membership_promotion",
            entryTargetTier = SubscriptionTier.Plus,
            analysisId = "11111111-1111-4111-8111-111111111111",
            resultSection = "training_recommendations",
            itemId = "training-card-1",
            attributes = mapOf(
                "entry_kind" to "content_gate",
                "placement" to "locked_content_teaser",
                "source_section" to "training_recommendations",
            ),
            clientOccurredAt = "2026-09-03T19:00:00Z",
        ).toEntryContext("22222222-2222-4222-8222-222222222222")

        val attributes = context.getValue("attributes").jsonObject
        assertEquals("22222222-2222-4222-8222-222222222222", context.getValue("funnel_session_id").jsonPrimitive.content)
        assertEquals("training_recommendations", context.getValue("result_section").jsonPrimitive.content)
        assertEquals("content_gate", attributes.getValue("entry_kind").jsonPrimitive.content)
        assertEquals("locked_content_teaser", attributes.getValue("placement").jsonPrimitive.content)
        assertEquals("training_recommendations", attributes.getValue("source_section").jsonPrimitive.content)
    }

    /** `paywall_events_event_name_check` is a shared constraint: a wire value the DB doesn't list
     * is rejected outright, and the event is lost silently (analytics never surface insert
     * errors to the purchase flow). */
    @Test
    fun `event wire values stay inside the shared database allowlist`() {
        val allowed = setOf(
            "entry_tap", "view", "close", "cta_tap", "plan_select", "billing_select",
            "purchase_started", "purchase_succeeded", "purchase_failed", "purchase_cancelled",
            "restore_tap", "payment_pending", "personal_plan_view", "personal_plan_continue",
            "trial_invite_view", "trial_invite_cta_tap",
        )

        PaywallEventName.entries.forEach { event ->
            assertEquals(
                "unlisted paywall event wire value: ${event.wireValue}",
                true,
                event.wireValue in allowed,
            )
        }
        assertEquals("purchase_cancelled", PaywallEventName.PurchaseCancelled.wireValue)
    }
}
