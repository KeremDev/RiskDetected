package com.riskdetectedan.core.data.analysis

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors AnalysisService.swift's `createAnalysis` insert contract exactly — same column
 * names, same "canvas = primary sorted id, single-id contract for now" comment (multi-canvas
 * goes through a `canvases` array once the backend supports it, not yet).
 */
@Serializable
private data class CreateAnalysisPayload(
    @SerialName("user_id") val userId: String,
    val kind: String,
    val canvas: String,
    val title: String,
    @SerialName("text_input") val textInput: String? = null,
    @SerialName("company_id") val companyId: String? = null,
    val status: String = "pending",
    @SerialName("analysis_sector") val analysisSector: String? = null,
    @SerialName("analysis_sector_source") val analysisSectorSource: String? = null,
    @SerialName("analysis_sector_prompt_version") val analysisSectorPromptVersion: String? = null,
    @SerialName("primary_method") val primaryMethod: String? = null,
)

@Serializable
private data class CreatedAnalysisRow(val id: String)

data class CreateAnalysisRequest(
    val userId: String,
    val title: String,
    val canvas: String = "general",
    val sector: AnalysisSector? = null,
    val companyId: String? = null,
    val textInput: String? = null,
)

@Singleton
class AnalysisRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    /**
     * Creates the `analyses` row (status "pending") — the first half of the submit flow.
     * Calling `analyze` itself (photo upload + AI routing) is separate, larger, not built yet;
     * this proves the write path (RLS as the authenticated user) end to end first.
     */
    suspend fun createAnalysis(request: CreateAnalysisRequest): RdResult<String> = try {
        // ANALYSIS_SECTOR_PROMPT_VERSION mirrors AnalysisSectorID.activeAnalysisPromptVersion —
        // hardcoded here until that value needs to change; not worth a remote-config round trip
        // for a single constant string yet.
        val row = client.postgrest.from("analyses")
            .insert(
                CreateAnalysisPayload(
                    userId = request.userId,
                    kind = "photo",
                    canvas = request.canvas,
                    title = request.title,
                    textInput = request.textInput,
                    companyId = request.companyId,
                    analysisSector = request.sector?.id,
                    analysisSectorSource = request.sector?.let { "user_selected" },
                    analysisSectorPromptVersion = request.sector?.let { ANALYSIS_SECTOR_PROMPT_VERSION },
                ),
            ) {
                select(Columns.list("id"))
            }
            .decodeSingle<CreatedAnalysisRow>()
        RdResult.Success(row.id)
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "analysis_create_failed",
            message = t.message ?: "analysis_create_failed",
            cause = t,
        )
    }

    private companion object {
        // Must match AnalysisSectorID.activeAnalysisPromptVersion in App/Models/AnalysisSector.swift
        // exactly — this is a real value read by the backend, not a placeholder.
        const val ANALYSIS_SECTOR_PROMPT_VERSION = "active-sector-v1"
    }
}
