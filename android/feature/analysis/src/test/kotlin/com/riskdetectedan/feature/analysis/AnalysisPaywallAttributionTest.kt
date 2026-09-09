package com.riskdetectedan.feature.analysis

import com.riskdetectedan.core.data.analysis.AnalysisResultSectionId
import com.riskdetectedan.core.data.profile.SubscriptionTier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class AnalysisPaywallAttributionTest {
    @Test
    fun `each result section has a distinct paywall entry point`() {
        val entryPoints = AnalysisResultSectionId.entries.map { it.paywallPromotionEntryPoint() }

        assertEquals(AnalysisResultSectionId.entries.size, entryPoints.distinct().size)
        assertEquals("result_hub_expert_advice_promotion", AnalysisResultSectionId.ExpertRecommendations.paywallPromotionEntryPoint())
        assertEquals("result_hub_training_promotion", AnalysisResultSectionId.TrainingRecommendations.paywallPromotionEntryPoint())
        assertEquals("result_hub_approved_notebook_promotion", AnalysisResultSectionId.ApprovedNotebook.paywallPromotionEntryPoint())
    }

    @Test
    fun `each paywall presentation gets its own funnel and complete analysis context`() {
        fun request() = analysisPaywallRequest(
            targetTier = SubscriptionTier.Plus,
            analysisId = "11111111-1111-4111-8111-111111111111",
            entryPoint = AnalysisResultSectionId.TrainingRecommendations.paywallPromotionEntryPoint(),
            resultSection = AnalysisResultSectionId.TrainingRecommendations,
            itemId = "training-card-1",
            placement = "locked_content_teaser",
            entryKind = "content_gate",
            promotionVariant = "plus_pro",
            currentTier = SubscriptionTier.Free,
        )

        val first = request()
        val second = request()

        assertNotEquals(first.funnelSessionId, second.funnelSessionId)
        assertEquals("11111111-1111-4111-8111-111111111111", first.analysisId)
        assertEquals(AnalysisResultSectionId.TrainingRecommendations, first.resultSection)
        assertEquals("training-card-1", first.itemId)
        assertEquals("locked_content_teaser", first.attributes["placement"])
        assertEquals("training_recommendations", first.attributes["source_section"])
        assertEquals("plus_pro", first.attributes["promotion_variant"])
    }
}
