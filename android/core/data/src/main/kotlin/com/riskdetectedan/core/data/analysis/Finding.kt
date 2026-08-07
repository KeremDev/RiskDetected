package com.riskdetectedan.core.data.analysis

import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.postgrest
import io.ktor.client.call.body
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID
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
    @SerialName("finding_version") val findingVersion: Int = 1,
)

/**
 * Mirrors mutate-analysis-finding/index.ts's request body — delete branch only (`action:
 * "delete"`). The update/patch branch (title/category/description/fk_ and m5_ risk fields/
 * measures edits) isn't ported: it's a much larger field-by-field surface than a first mutation slice
 * needs, and delete is the more common quick-triage action from a findings list. `patch` is
 * therefore always omitted here — the edge function only reads it when action is "update".
 */
@Serializable
private data class MutateFindingBody(
    val action: String,
    @SerialName("analysis_id") val analysisId: String,
    @SerialName("finding_id") val findingId: String,
    @SerialName("expected_finding_version") val expectedFindingVersion: Int,
    @SerialName("client_app_version") val clientAppVersion: String,
    @SerialName("request_id") val requestId: String,
    @SerialName("support_id") val supportId: String,
)

/** Only the fields this client actually reads — the edge function also returns a full refreshed
 * `bundle` (analysis/findings/photos/photoSummaries), but the caller just refetches via
 * [FindingsRepository.fetchFindings] instead of decoding that whole shape here. */
@Serializable
private data class MutateFindingResult(
    val ok: Boolean? = null,
    val error: String? = null,
    val message: String? = null,
)

@Singleton
class FindingsRepository @Inject constructor(
    private val client: SupabaseClient,
    private val environmentConfig: RdEnvironmentConfig,
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

    /**
     * Mirrors the "delete" branch of mutate-analysis-finding: server soft-deletes (sets
     * is_user_deleted, doesn't hard-delete the row — see `apply_finding_mutation_atomic`),
     * bumps `analyses.analysis_edit_version`/`user_edit_count`, and recalculates the analysis
     * rollup. `expectedFindingVersion` is the optimistic-concurrency guard the backend checks
     * before applying (`finding_version_conflict` on mismatch — surfaced here as a plain
     * failure, no auto-retry, matching the edge function's "reload and try again" message).
     */
    suspend fun deleteFinding(
        analysisId: String,
        findingId: String,
        expectedFindingVersion: Int,
    ): RdResult<Unit> = try {
        val result = client.functions.invoke(
            "mutate-analysis-finding",
            body = MutateFindingBody(
                action = "delete",
                analysisId = analysisId,
                findingId = findingId,
                expectedFindingVersion = expectedFindingVersion,
                clientAppVersion = environmentConfig.appVersionName,
                requestId = UUID.randomUUID().toString(),
                supportId = UUID.randomUUID().toString(),
            ),
        ).body<MutateFindingResult>()

        if (result.ok == true) {
            RdResult.Success(Unit)
        } else {
            RdResult.Failure(
                code = result.error ?: "finding_delete_failed",
                message = result.message ?: "Bulgu silinemedi.",
            )
        }
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "finding_delete_failed",
            message = t.message ?: "Bulgu silinemedi.",
            cause = t,
        )
    }
}
