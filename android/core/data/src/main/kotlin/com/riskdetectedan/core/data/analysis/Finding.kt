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
 * Mirrors mutate-analysis-finding/index.ts's text-field patch branch — title/category/
 * description/recommended_action/references_text/root_cause_text only. The fk_/m5_ risk-score
 * fields (probability/frequency/severity re-scoring, which drive the server-recomputed
 * fk_band/m5_band) and `recommended_measures` (structured multi-measure list, which overrides
 * recommendedAction when present) aren't ported — a numeric risk-rescoring UI is a bigger,
 * more deliberate design surface than a first text-edit slice needs, and isn't silently
 * dropped: findings keep whatever risk score the AI/analysis already assigned. `title` and
 * `description` mirror the edge function's `requiredText` validation (non-blank, else
 * `validation_failed`) client-side too, so a blank save fails fast instead of round-tripping.
 */
@Serializable
data class FindingPatch(
    val title: String? = null,
    val category: String? = null,
    val description: String? = null,
    @SerialName("recommended_action") val recommendedAction: String? = null,
    @SerialName("references_text") val referencesText: String? = null,
    @SerialName("root_cause_text") val rootCauseText: String? = null,
)

@Serializable
private data class MutateFindingBody(
    val action: String,
    @SerialName("analysis_id") val analysisId: String,
    @SerialName("finding_id") val findingId: String,
    @SerialName("expected_finding_version") val expectedFindingVersion: Int,
    @SerialName("client_app_version") val clientAppVersion: String,
    @SerialName("request_id") val requestId: String,
    @SerialName("support_id") val supportId: String,
    val patch: FindingPatch? = null,
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

    /**
     * Mirrors the "update" branch of mutate-analysis-finding for the text-field subset (see
     * [FindingPatch]'s doc comment for what's excluded). `title`/`description` are validated
     * non-blank client-side first, matching the edge function's own `requiredText` rejection —
     * failing fast here avoids a round trip for a save that's guaranteed to 400.
     */
    suspend fun updateFinding(
        analysisId: String,
        findingId: String,
        expectedFindingVersion: Int,
        patch: FindingPatch,
    ): RdResult<Unit> {
        if (patch.title != null && patch.title.isBlank()) {
            return RdResult.Failure("validation_failed", "Başlık boş olamaz.")
        }
        if (patch.description != null && patch.description.isBlank()) {
            return RdResult.Failure("validation_failed", "Açıklama boş olamaz.")
        }
        return try {
            val result = client.functions.invoke(
                "mutate-analysis-finding",
                body = MutateFindingBody(
                    action = "update",
                    analysisId = analysisId,
                    findingId = findingId,
                    expectedFindingVersion = expectedFindingVersion,
                    clientAppVersion = environmentConfig.appVersionName,
                    requestId = UUID.randomUUID().toString(),
                    supportId = UUID.randomUUID().toString(),
                    patch = patch,
                ),
            ).body<MutateFindingResult>()

            if (result.ok == true) {
                RdResult.Success(Unit)
            } else {
                RdResult.Failure(
                    code = result.error ?: "finding_update_failed",
                    message = result.message ?: "Bulgu güncellenemedi.",
                )
            }
        } catch (t: Throwable) {
            RdResult.Failure(
                code = "finding_update_failed",
                message = t.message ?: "Bulgu güncellenemedi.",
                cause = t,
            )
        }
    }
}
