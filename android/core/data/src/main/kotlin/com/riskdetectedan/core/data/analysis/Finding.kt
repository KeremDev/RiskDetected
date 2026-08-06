package com.riskdetectedan.core.data.analysis

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Partial mirror of App/Models/Finding.swift, but reads server-computed columns directly
 * instead of recalculating: `findings.fk_score`/`fk_band`/`m5_score`/`m5_band` are Postgres
 * `generated always as` columns (fk_score) and server-set enum columns (fk_band) — the backend
 * already ran RiskBands.fineKinney()-equivalent logic, so this doesn't need to port that
 * calculation (see App/Models/Finding.swift's RiskBands enum) to get a correct band label/color,
 * just to display what the server already decided. Matches the "backend is the single
 * authority" invariant (master §37) — the client was never supposed to be the one computing
 * risk bands anyway.
 */
@Serializable
data class Finding(
    val id: String,
    val ordinal: Int,
    val title: String,
    val category: String? = null,
    val description: String? = null,
    @SerialName("recommended_action") val recommendedAction: String? = null,
    val confidence: Double = 0.0,
    @SerialName("fk_score") val fkScore: Double? = null,
    @SerialName("fk_band") val fkBand: String,
    @SerialName("m5_score") val m5Score: Int? = null,
    @SerialName("m5_band") val m5Band: String,
    @SerialName("references_text") val referencesText: String? = null,
    @SerialName("root_cause_text") val rootCauseText: String? = null,
)

@Singleton
class FindingsRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    /** Excludes is_user_deleted rows — matches iOS's "findings visible in the UI" set. */
    suspend fun fetchFindings(analysisId: String): RdResult<List<Finding>> = try {
        val findings = client.postgrest.from("findings")
            .select {
                filter {
                    eq("analysis_id", analysisId)
                    eq("is_user_deleted", false)
                }
                order("ordinal", io.github.jan.supabase.postgrest.query.Order.ASCENDING)
            }
            .decodeList<Finding>()
        RdResult.Success(findings)
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "findings_fetch_failed",
            message = t.message ?: "findings_fetch_failed",
            cause = t,
        )
    }
}
