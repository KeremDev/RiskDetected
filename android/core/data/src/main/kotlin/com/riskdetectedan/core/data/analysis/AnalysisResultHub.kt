package com.riskdetectedan.core.data.analysis

import com.riskdetectedan.core.common.RdClientMetadata
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.ktor.client.call.body
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
enum class AnalysisResultSectionId {
    @SerialName("risk_analysis") RiskAnalysis,
    @SerialName("expert_recommendations") ExpertRecommendations,
    @SerialName("training_recommendations") TrainingRecommendations,
    @SerialName("approved_notebook") ApprovedNotebook,
}

internal fun AnalysisResultSectionId.feedbackTargetKind(): String = when (this) {
    AnalysisResultSectionId.ApprovedNotebook -> "notebook_entry"
    AnalysisResultSectionId.TrainingRecommendations -> "training_card"
    AnalysisResultSectionId.RiskAnalysis,
    AnalysisResultSectionId.ExpertRecommendations -> "finding"
}

internal fun sanitizeResultFeedbackNote(note: String?): String? =
    note?.trim()?.take(1000)?.takeIf(String::isNotBlank)

@Serializable
enum class AnalysisResultAccess { @SerialName("full") Full, @SerialName("teaser") Teaser }

@Serializable
enum class AnalysisItemReaction { @SerialName("none") None, @SerialName("like") Like, @SerialName("dislike") Dislike }

@Serializable
data class AnalysisResultHubResponse(
    val enabled: Boolean = false,
    @SerialName("contract_version") val contractVersion: String = "analysis-result-sections-v1",
    @SerialName("ui_version") val uiVersion: String? = null,
    @SerialName("analysis_id") val analysisId: String? = null,
    @SerialName("analysis_edit_version") val analysisEditVersion: Int? = null,
    val tier: String? = null,
    val language: String? = null,
    val disclaimers: AnalysisResultDisclaimers? = null,
    val sections: List<AnalysisResultSection> = emptyList(),
    val reason: String? = null,
)

@Serializable
data class AnalysisResultDisclaimers(val expert: String = "", val notebook: String = "")

@Serializable
data class AnalysisResultSection(
    val id: AnalysisResultSectionId,
    val access: AnalysisResultAccess,
    val count: Int,
    @SerialName("can_edit") val canEdit: Boolean = false,
    @SerialName("can_report") val canReport: Boolean = false,
    @SerialName("observation_basis") val observationBasis: String? = null,
    val items: List<AnalysisResultHubItem> = emptyList(),
)

@Serializable
data class AnalysisResultHubItem(
    val id: String,
    @SerialName("analysis_id") val analysisId: String? = null,
    @SerialName("catalog_code") val catalogCode: String? = null,
    val ordinal: Int? = null,
    val title: String? = null,
    val category: String? = null,
    @SerialName("category_label") val categoryLabel: String? = null,
    @SerialName("audience_label") val audienceLabel: String? = null,
    val text: String? = null,
    @SerialName("group_code") val groupCode: String? = null,
    @SerialName("duration_label") val durationLabel: String? = null,
    @SerialName("duration_value") val durationValue: String? = null,
    @SerialName("duration_note") val durationNote: String? = null,
    val description: String? = null,
    @SerialName("recommended_action") val recommendedAction: String? = null,
    @SerialName("recommended_measures") val recommendedMeasures: List<FindingMeasure>? = null,
    @SerialName("references_text") val referencesText: String? = null,
    @SerialName("root_cause_text") val rootCauseText: String? = null,
    val confidence: Double? = null,
    @SerialName("needs_field_verification") val needsFieldVerification: Boolean? = null,
    @SerialName("fk_probability") val fkProbability: Double? = null,
    @SerialName("fk_frequency") val fkFrequency: Double? = null,
    @SerialName("fk_severity") val fkSeverity: Double? = null,
    @SerialName("fk_score") val fkScore: Double? = null,
    @SerialName("fk_band") val fkBand: String? = null,
    @SerialName("m5_probability") val m5Probability: Int? = null,
    @SerialName("m5_severity") val m5Severity: Int? = null,
    @SerialName("m5_score") val m5Score: Int? = null,
    @SerialName("m5_band") val m5Band: String? = null,
    @SerialName("source_photo_indices") val sourcePhotoIndices: List<Int> = emptyList(),
    @SerialName("display_order") val displayOrder: Int? = null,
    @SerialName("item_class") val itemClass: String? = null,
    @SerialName("is_scored") val isScored: Boolean? = null,
    val locked: Boolean = false,
    @SerialName("user_reaction") val userReaction: AnalysisItemReaction = AnalysisItemReaction.None,
    @SerialName("finding_text") val findingText: String? = null,
    @SerialName("recommendation_text") val recommendationText: String? = null,
    @SerialName("reference_text") val referenceText: String? = null,
    @SerialName("source_finding_ids") val sourceFindingIds: List<String> = emptyList(),
    @SerialName("is_user_edited") val isUserEdited: Boolean = false,
    @SerialName("is_stale") val isStale: Boolean = false,
) {
    val displayTitle: String
        get() = title?.takeIf(String::isNotBlank)
            ?: findingText?.takeIf(String::isNotBlank)
            ?: if (RdClientMetadata.APP_LANGUAGE == "en") "Record" else "Kayıt"
    val displayBody: String get() = description?.takeIf(String::isNotBlank)
        ?: text?.takeIf(String::isNotBlank)
        ?: recommendationText.orEmpty()

    fun toFinding(fallbackAnalysisId: String): Finding = Finding(
        id = id,
        ordinal = ordinal ?: (displayOrder ?: 1).coerceAtLeast(1),
        title = title?.takeIf(String::isNotBlank) ?: findingText?.takeIf(String::isNotBlank) ?: displayTitle,
        category = category,
        description = description?.takeIf(String::isNotBlank) ?: findingText,
        recommendedAction = recommendedAction?.takeIf(String::isNotBlank) ?: recommendationText,
        recommendedMeasures = recommendedMeasures,
        confidence = confidence ?: 0.0,
        itemClass = itemClass ?: if (isScored == false) "verification_request" else "observed_finding",
        isScored = isScored != false,
        needsFieldVerification = needsFieldVerification == true,
        sourcePhotoIndices = sourcePhotoIndices,
        fkProbability = fkProbability,
        fkFrequency = fkFrequency,
        fkSeverity = fkSeverity,
        fkScore = fkScore,
        fkBand = fkBand ?: "unknown",
        m5Probability = m5Probability,
        m5Severity = m5Severity,
        m5Score = m5Score,
        m5Band = m5Band ?: "unknown",
        referencesText = referencesText?.takeIf(String::isNotBlank) ?: referenceText,
        rootCauseText = rootCauseText,
        findingVersion = 1,
        displayOrder = displayOrder,
    )
}

@Serializable
data class AnalysisReportIntent(
    val id: String,
    @SerialName("analysis_id") val analysisId: String,
    @SerialName("content_scope") val contentScope: AnalysisResultSectionId,
    val format: String,
    @SerialName("selected_item_keys") val selectedItemKeys: List<String>,
)

@Serializable
private data class ResultHubBody(
    val action: String,
    @SerialName("analysis_id") val analysisId: String,
    val language: String = RdClientMetadata.APP_LANGUAGE,
    @SerialName("client_capabilities") val clientCapabilities: Map<String, Boolean>,
    @SerialName("client_platform") val clientPlatform: String,
    @SerialName("client_app_version") val clientAppVersion: String,
    @SerialName("client_app_build") val clientAppBuild: String,
    val section: AnalysisResultSectionId? = null,
    val format: String? = null,
    @SerialName("selected_item_keys") val selectedItemKeys: List<String>? = null,
    @SerialName("request_id") val requestId: String? = null,
    @SerialName("target_kind") val targetKind: String? = null,
    @SerialName("target_key") val targetKey: String? = null,
    val rating: Int? = null,
    @SerialName("reason_code") val reasonCode: String? = null,
    val note: String? = null,
    @SerialName("client_event_id") val clientEventId: String? = null,
    @SerialName("funnel_session_id") val funnelSessionId: String? = null,
    @SerialName("event_name") val eventName: String? = null,
    @SerialName("entry_id") val entryId: String? = null,
    val mutation: String? = null,
    @SerialName("finding_text") val findingText: String? = null,
    @SerialName("recommendation_text") val recommendationText: String? = null,
)

@Serializable private data class ReportIntentResponse(@SerialName("report_intent") val reportIntent: AnalysisReportIntent)
@Serializable private data class ResultHubAck(val ok: Boolean? = null)

@Singleton
class AnalysisResultHubRepository @Inject constructor(
    private val client: SupabaseClient,
    private val environmentConfig: RdEnvironmentConfig,
) {
    private fun body(action: String, analysisId: String) = ResultHubBody(
        action = action,
        analysisId = analysisId,
        clientCapabilities = RdClientMetadata.capabilities,
        clientPlatform = RdClientMetadata.PLATFORM,
        clientAppVersion = environmentConfig.appVersionName,
        clientAppBuild = environmentConfig.appVersionCode.toString(),
    )

    suspend fun load(analysisId: String): RdResult<AnalysisResultHubResponse> = try {
        val response = client.functions.invoke("analysis-result-sections", body = body("load", analysisId))
            .body<AnalysisResultHubResponse>()
        RdResult.Success(response)
    } catch (t: Throwable) {
        RdResult.Failure("result_hub_load_failed", t.message ?: "result_hub_load_failed", t)
    }

    suspend fun setFeedback(
        analysisId: String,
        section: AnalysisResultSectionId,
        item: AnalysisResultHubItem,
        reaction: AnalysisItemReaction,
        reasonCode: String? = null,
        note: String? = null,
    ): RdResult<Unit> = try {
        client.functions.invoke(
            "analysis-result-sections",
            body = body("feedback", analysisId).copy(
                section = section,
                targetKind = section.feedbackTargetKind(),
                targetKey = item.id,
                rating = when (reaction) { AnalysisItemReaction.Like -> 1; AnalysisItemReaction.Dislike -> -1; AnalysisItemReaction.None -> 0 },
                reasonCode = reasonCode,
                note = sanitizeResultFeedbackNote(note),
            ),
        ).body<ResultHubAck>()
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure("result_feedback_failed", t.message ?: "result_feedback_failed", t)
    }

    suspend fun createReportIntent(
        analysisId: String,
        section: AnalysisResultSectionId,
        format: String,
        selected: List<String>,
        requestId: String = UUID.randomUUID().toString(),
    ): RdResult<AnalysisReportIntent> = try {
        val result = client.functions.invoke(
            "analysis-result-sections",
            body = body("create_report_intent", analysisId).copy(
                section = section,
                format = format,
                selectedItemKeys = selected,
                requestId = requestId,
            ),
        ).body<ReportIntentResponse>()
        RdResult.Success(result.reportIntent)
    } catch (t: Throwable) {
        RdResult.Failure("report_intent_failed", t.message ?: "report_intent_failed", t)
    }

    suspend fun mutateNotebook(
        analysisId: String,
        entryId: String,
        mutation: String,
        findingText: String? = null,
        recommendationText: String? = null,
    ): RdResult<Unit> = try {
        client.functions.invoke(
            "analysis-result-sections",
            body = body("mutate_notebook", analysisId).copy(
                entryId = entryId,
                mutation = mutation,
                findingText = findingText,
                recommendationText = recommendationText,
            ),
        ).body<ResultHubAck>()
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure("notebook_mutation_failed", t.message ?: "notebook_mutation_failed", t)
    }

    suspend fun recordEvent(
        analysisId: String,
        name: String,
        section: AnalysisResultSectionId?,
        funnelSessionId: String,
        itemId: String? = null,
    ) {
        runCatching {
            client.functions.invoke(
                "analysis-result-sections",
                body = body("event", analysisId).copy(
                    section = section,
                    clientEventId = UUID.randomUUID().toString(),
                    funnelSessionId = funnelSessionId,
                    eventName = name,
                    targetKey = itemId,
                ),
            ).body<ResultHubAck>()
        }
    }
}
