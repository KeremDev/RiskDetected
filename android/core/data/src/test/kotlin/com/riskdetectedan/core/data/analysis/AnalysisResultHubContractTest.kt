package com.riskdetectedan.core.data.analysis

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AnalysisResultHubContractTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `four-section v4 response decodes training and notebook contract`() {
        val response = json.decodeFromString<AnalysisResultHubResponse>(
            """
            {
              "enabled": true,
              "contract_version": "analysis-result-sections-v1",
              "ui_version": "analysis-result-hub-v2",
              "analysis_id": "11111111-1111-4111-8111-111111111111",
              "analysis_edit_version": 4,
              "tier": "plus",
              "language": "tr",
              "sections": [
                {"id":"risk_analysis","access":"full","count":1,"can_edit":true,"can_report":true,"items":[{"id":"risk-1","title":"Koruyucusuz ekipman"}]},
                {"id":"expert_recommendations","access":"full","count":1,"can_edit":true,"can_report":true,"items":[{"id":"expert-1","title":"Saha teyidi"}]},
                {"id":"training_recommendations","access":"full","count":1,"can_edit":false,"can_report":false,"items":[{
                  "id":"training-1",
                  "catalog_code":"tr-work-equipment-01",
                  "title":"İş ekipmanlarının güvenli kullanımı",
                  "category_label":"İş Ekipmanı",
                  "audience_label":"Ekipmanı kullanan çalışanlar",
                  "text":"Uygun kullanım ve koruyucu kontroller ele alınmalıdır.",
                  "group_code":"work_equipment",
                  "duration_label":"Az tehlikeli / Tehlikeli / Çok tehlikeli",
                  "duration_value":"8 / 12 / 16 saat",
                  "duration_note":"Tehlike sınıfına göre uygulanır."
                }]},
                {"id":"approved_notebook","access":"full","count":1,"can_edit":true,"can_report":true,"observation_basis":"direct_site_observation","items":[{"id":"book-1","finding_text":"Tespit","recommendation_text":"Öneri"}]}
              ]
            }
            """.trimIndent(),
        )

        assertTrue(response.enabled)
        assertEquals("analysis-result-hub-v2", response.uiVersion)
        assertEquals(4, response.analysisEditVersion)
        assertEquals(
            listOf(
                AnalysisResultSectionId.RiskAnalysis,
                AnalysisResultSectionId.ExpertRecommendations,
                AnalysisResultSectionId.TrainingRecommendations,
                AnalysisResultSectionId.ApprovedNotebook,
            ),
            response.sections.map { it.id },
        )
        val training = response.sections[2]
        assertEquals(false, training.canReport)
        assertEquals("tr-work-equipment-01", training.items.single().catalogCode)
        assertEquals("Uygun kullanım ve koruyucu kontroller ele alınmalıdır.", training.items.single().displayBody)
        assertEquals("direct_site_observation", response.sections[3].observationBasis)
    }

    @Test
    fun `feedback targets and free-form note match backend contract`() {
        assertEquals("finding", AnalysisResultSectionId.RiskAnalysis.feedbackTargetKind())
        assertEquals("finding", AnalysisResultSectionId.ExpertRecommendations.feedbackTargetKind())
        assertEquals("training_card", AnalysisResultSectionId.TrainingRecommendations.feedbackTargetKind())
        assertEquals("notebook_entry", AnalysisResultSectionId.ApprovedNotebook.feedbackTargetKind())
        assertNull(sanitizeResultFeedbackNote("   "))
        assertEquals("a".repeat(1000), sanitizeResultFeedbackNote("  ${"a".repeat(1005)}  "))
    }
}
