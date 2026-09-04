package com.riskdetectedan.feature.paywall

import com.riskdetectedan.core.data.profile.SubscriptionTier
import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
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

    @Test
    fun `result sections map to stable paywall attribution coordinates`() {
        assertEquals("result_hub_risk_analysis_promotion", "risk_analysis".resultPromotionEntryPoint())
        assertEquals("result_hub_expert_advice_promotion", "expert_recommendations".resultPromotionEntryPoint())
        assertEquals("result_hub_training_promotion", "training_recommendations".resultPromotionEntryPoint())
        assertEquals("result_hub_approved_notebook_promotion", "approved_notebook".resultPromotionEntryPoint())
        assertEquals("training_recommendations", paywallEntrySurface("result_hub_training_promotion"))
        assertEquals("result_membership_promotion", paywallEntryComponent("result_hub_training_promotion"))
    }

    @Test
    fun `home paywall coordinates retain the clicked component`() {
        assertEquals("home", paywallEntrySurface("home_photo_tray_locked_slot"))
        assertEquals("photo_tray_locked_slot", paywallEntryComponent("home_photo_tray_locked_slot"))
        assertEquals("quota_status_card", paywallEntryComponent("home_quota_hint"))
        assertEquals("header_upgrade_cta", paywallEntryComponent("reports_header_upgrade"))
    }

    @Test
    fun `result paywall coordinates retain the exact clicked component`() {
        assertEquals("analysis_results", paywallEntrySurface("result_header_upgrade"))
        assertEquals("header_upgrade_cta", paywallEntryComponent("result_header_upgrade"))
        assertEquals("result_summary_hint", paywallEntryComponent("result_summary_upgrade_hint"))
        assertEquals("confidence_chip", paywallEntryComponent("result_confidence_chip"))
        assertEquals("finding_card_locked_feature", paywallEntryComponent("result_finding_locked_feature"))
        assertEquals("locked_finding_preview", paywallEntryComponent("result_locked_finding_preview"))
        assertEquals("finding_detail", paywallEntrySurface("finding_detail_plus_pro_promotion"))
        assertEquals("finding_detail_membership_promotion", paywallEntryComponent("finding_detail_plus_pro_promotion"))
        assertEquals("finding_detail_membership_promotion", paywallEntryComponent("finding_detail_pro_promotion"))
        assertEquals("regulatory_references_lock", paywallEntryComponent("finding_detail_regulatory_references"))
        assertEquals("analysis_results", paywallEntrySurface("result_report_company_picker"))
        assertEquals("company_picker_lock", paywallEntryComponent("result_report_company_picker"))
    }

    @Test
    fun `every registered entry point resolves without an unknown coordinate`() {
        paywallEntryCatalog.forEach { (entryPoint, definition) ->
            assertNotEquals("unknown surface for $entryPoint", "unknown", definition.surface)
            assertNotEquals("unknown component for $entryPoint", "unknown", definition.component)
            assertEquals(definition.surface, paywallEntrySurface(entryPoint))
            assertEquals(definition.component, paywallEntryComponent(entryPoint))
        }
    }
}
