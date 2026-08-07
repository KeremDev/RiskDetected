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
/** Mirrors normalizeMeasures()'s output shape in mutate-analysis-finding/index.ts exactly —
 * `kind` is only ever "corrective" or "preventive" server-side (anything else is coerced to
 * "corrective"), `title` max 80 chars, `text` max 900. */
@Serializable
data class FindingMeasure(
    val kind: String = "corrective",
    val title: String = "",
    val text: String = "",
)

@Serializable
data class Finding(
    val id: String,
    val ordinal: Int,
    val title: String,
    val category: String? = null,
    val description: String? = null,
    @SerialName("recommended_action") val recommendedAction: String? = null,
    @SerialName("recommended_measures") val recommendedMeasures: List<FindingMeasure>? = null,
    val confidence: Double = 0.0,
    @SerialName("fk_probability") val fkProbability: Double? = null,
    @SerialName("fk_frequency") val fkFrequency: Double? = null,
    @SerialName("fk_severity") val fkSeverity: Double? = null,
    @SerialName("fk_score") val fkScore: Double? = null,
    @SerialName("fk_band") val fkBand: String,
    @SerialName("m5_probability") val m5Probability: Int? = null,
    @SerialName("m5_severity") val m5Severity: Int? = null,
    @SerialName("m5_score") val m5Score: Int? = null,
    @SerialName("m5_band") val m5Band: String,
    @SerialName("references_text") val referencesText: String? = null,
    @SerialName("root_cause_text") val rootCauseText: String? = null,
    @SerialName("finding_version") val findingVersion: Int = 1,
)

/**
 * Mirrors mutate-analysis-finding/index.ts's "update" patch shape in full — text fields, the
 * fk_/m5_ risk-rescoring numbers, and `recommended_measures`. `title`/`description` mirror the
 * edge function's `requiredText` validation client-side (non-blank); fk_probability/
 * fk_frequency/fk_severity and m5_probability/m5_severity are validated against the exact same
 * allowed sets the server checks (`FK_PROBABILITY_VALUES`/`FK_FREQUENCY_VALUES`/
 * `FK_SEVERITY_VALUES`, 1-5 for m5) — [FindingsRepository.updateFinding] fails fast on a save
 * that's guaranteed to 400 rather than round-tripping. Sending only probability/frequency/
 * severity and never a band matches the "backend is sole authority" invariant — the server
 * recomputes fk_band/m5_band, this client never does (same reasoning [Finding]'s own doc
 * comment gives for the read side). [recommendedMeasures], when non-null, overrides
 * [recommendedAction] server-side (`normalizeMeasures` sets `recommended_action` to the first
 * measure's text) — matches the edge function's own precedence, not re-derived client-side.
 */
@Serializable
data class FindingPatch(
    val title: String? = null,
    val category: String? = null,
    val description: String? = null,
    @SerialName("recommended_action") val recommendedAction: String? = null,
    @SerialName("recommended_measures") val recommendedMeasures: List<FindingMeasure>? = null,
    @SerialName("references_text") val referencesText: String? = null,
    @SerialName("root_cause_text") val rootCauseText: String? = null,
    @SerialName("fk_probability") val fkProbability: Double? = null,
    @SerialName("fk_frequency") val fkFrequency: Double? = null,
    @SerialName("fk_severity") val fkSeverity: Double? = null,
    @SerialName("m5_probability") val m5Probability: Int? = null,
    @SerialName("m5_severity") val m5Severity: Int? = null,
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

/** Exact mirror of mutate-analysis-finding/index.ts's FK_PROBABILITY_VALUES/FK_FREQUENCY_VALUES/
 * FK_SEVERITY_VALUES (classic Fine-Kinney option sets) — checked in the SDK, not guessed. */
object FineKinneyValues {
    val PROBABILITY = listOf(0.2, 0.5, 1.0, 3.0, 6.0, 10.0)
    val FREQUENCY = listOf(0.5, 1.0, 2.0, 3.0, 6.0, 10.0)
    val SEVERITY = listOf(1.0, 3.0, 7.0, 15.0, 40.0, 100.0)
}

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
        if (patch.fkProbability != null && patch.fkProbability !in FineKinneyValues.PROBABILITY) {
            return RdResult.Failure("validation_failed", "Geçersiz olasılık değeri.")
        }
        if (patch.fkFrequency != null && patch.fkFrequency !in FineKinneyValues.FREQUENCY) {
            return RdResult.Failure("validation_failed", "Geçersiz frekans değeri.")
        }
        if (patch.fkSeverity != null && patch.fkSeverity !in FineKinneyValues.SEVERITY) {
            return RdResult.Failure("validation_failed", "Geçersiz şiddet değeri.")
        }
        if (patch.m5Probability != null && patch.m5Probability !in 1..5) {
            return RdResult.Failure("validation_failed", "Olasılık 1-5 arasında olmalı.")
        }
        if (patch.m5Severity != null && patch.m5Severity !in 1..5) {
            return RdResult.Failure("validation_failed", "Şiddet 1-5 arasında olmalı.")
        }
        // Mirrors normalizeMeasures()'s own "measures.length === 0 after filtering blanks"
        // rejection — an all-blank-text list is a guaranteed 400, same reasoning as the other
        // fast-fail checks above.
        if (patch.recommendedMeasures != null && patch.recommendedMeasures.none { it.text.isNotBlank() }) {
            return RdResult.Failure("validation_failed", "En az bir önlem metni girilmeli.")
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
