package com.riskdetectedan.core.data.analysis

import com.riskdetectedan.core.common.RdClientMetadata
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.coroutines.delay
import java.util.UUID
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

/**
 * Mirrors AnalysisService.swift's `invokeAnalyze` Body struct field-for-field, including field
 * order (not that order matters for JSON, but it makes the two easy to diff by eye). All the
 * localization_* fields are null here — that's the same "no explicit localization request"
 * default path iOS takes on a first-time submit; the backend's resolveLocalizationContext
 * (supabase/functions/_shared/localization-context-resolver.ts, F3-hardened earlier) derives
 * from the profile/persisted snapshot in that case (`source: "legacy_tr_default"`), a real,
 * well-exercised production path — not a shortcut unique to Android.
 */
@Serializable
private data class AnalyzeRequestBody(
    @SerialName("analysis_id") val analysisId: String,
    val canvas: String,
    val canvases: List<String>,
    @SerialName("analysis_mode") val analysisMode: String,
    @SerialName("text_input") val textInput: String? = null,
    @SerialName("request_id") val requestId: String,
    @SerialName("support_id") val supportId: String,
    @SerialName("company_id") val companyId: String? = null,
    @SerialName("analysis_sector") val analysisSector: String? = null,
    @SerialName("analysis_sector_source") val analysisSectorSource: String? = null,
    @SerialName("analysis_sector_prompt_version") val analysisSectorPromptVersion: String? = null,
    @SerialName("app_language") val appLanguage: String,
    @SerialName("output_language") val outputLanguage: String? = null,
    @SerialName("output_locale") val outputLocale: String? = null,
    @SerialName("work_jurisdiction_country") val workJurisdictionCountry: String? = null,
    @SerialName("work_jurisdiction_region") val workJurisdictionRegion: String? = null,
    @SerialName("safety_profile_id") val safetyProfileId: String? = null,
    @SerialName("safety_profile_version") val safetyProfileVersion: Int? = null,
    val method: String? = null,
    @SerialName("photo_paths") val photoPaths: List<String>,
    // iOS's InlinePhotoPart struct list — always empty on the storage-path submission path
    // (only used for a small-photo inline-base64 fallback iOS has that Android doesn't need
    // yet), so List<String> serializes identically ([]) without needing that struct ported.
    @SerialName("photo_base64_parts") val photoBase64Parts: List<String> = emptyList(),
    @SerialName("client_app_version") val clientAppVersion: String,
    @SerialName("client_app_build") val clientAppBuild: String,
    @SerialName("client_platform") val clientPlatform: String,
    @SerialName("api_contract_version") val apiContractVersion: Int,
    @SerialName("client_capabilities") val clientCapabilities: Map<String, Boolean>,
)

@Serializable
private data class AnalysisStatusSnapshot(
    val status: String,
    @SerialName("status_message") val statusMessage: String? = null,
)

sealed interface AnalysisStatus {
    data object Completed : AnalysisStatus
    data class Failed(val message: String?) : AnalysisStatus
    data class InProgress(val status: String) : AnalysisStatus
    data object TimedOut : AnalysisStatus
}

@Singleton
class AnalysisRepository @Inject constructor(
    private val client: SupabaseClient,
    private val environmentConfig: RdEnvironmentConfig,
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

    /**
     * Mirrors AnalysisService.swift's invokeAnalyze — one attempt, no retry-with-classification
     * yet (iOS retries up to 2x on 429/500/502/503/504 with quota/photo-limit/language-contract
     * error-code branching). That retry/error-classification layer is real product behavior,
     * not decoration — tracked as follow-up, not silently dropped.
     */
    suspend fun submitAnalyze(
        analysisId: String,
        canvas: String,
        canvases: List<String> = listOf(canvas),
        analysisMode: String = "standard",
        sector: AnalysisSector?,
        photoPaths: List<String>,
        appLanguage: String = "tr",
    ): RdResult<Unit> = try {
        val body = AnalyzeRequestBody(
            analysisId = analysisId,
            canvas = canvas,
            canvases = canvases,
            analysisMode = analysisMode,
            requestId = UUID.randomUUID().toString(),
            supportId = UUID.randomUUID().toString(),
            analysisSector = sector?.id,
            analysisSectorSource = sector?.let { "user_selected" },
            analysisSectorPromptVersion = sector?.let { ANALYSIS_SECTOR_PROMPT_VERSION },
            appLanguage = appLanguage,
            photoPaths = photoPaths,
            clientAppVersion = environmentConfig.appVersionName,
            clientAppBuild = environmentConfig.appVersionCode.toString(),
            clientPlatform = RdClientMetadata.PLATFORM,
            apiContractVersion = RdClientMetadata.API_CONTRACT_VERSION,
            clientCapabilities = RdClientMetadata.capabilities,
        )
        client.functions.invoke("analyze", body = body)
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "analysis_submit_failed",
            message = t.message ?: "analysis_submit_failed",
            cause = t,
        )
    }

    /**
     * Mirrors the polling loop inside AnalysisService.swift's waitForCompletedResult (status
     * values + ~2s interval), simplified: no in-flight-analysis persistence, no findings
     * hydration (that's the results/reports domain — separate, unbuilt). Times out after
     * [maxAttempts] polls rather than iOS's 300-420s wall-clock deadline — close enough for a
     * first pass, revisit if photo count needs to change the deadline like iOS does.
     */
    suspend fun pollAnalysisStatus(
        analysisId: String,
        maxAttempts: Int = 150,
        pollIntervalMillis: Long = 2_000,
    ): AnalysisStatus {
        repeat(maxAttempts) {
            val snapshot = try {
                client.postgrest.from("analyses")
                    .select(Columns.list("status", "status_message")) {
                        filter { eq("id", analysisId) }
                    }
                    .decodeSingle<AnalysisStatusSnapshot>()
            } catch (_: Throwable) {
                null
            }
            when (snapshot?.status) {
                "completed" -> return AnalysisStatus.Completed
                "failed" -> return AnalysisStatus.Failed(snapshot.statusMessage)
                // "queued"/"pending"/"analyzing", an unrecognized status, or a transient fetch
                // failure (snapshot == null) all just fall through to the delay below and retry.
                else -> Unit
            }
            delay(pollIntervalMillis)
        }
        return AnalysisStatus.TimedOut
    }

    private companion object {
        // Must match AnalysisSectorID.activeAnalysisPromptVersion in App/Models/AnalysisSector.swift
        // exactly — this is a real value read by the backend, not a placeholder.
        const val ANALYSIS_SECTOR_PROMPT_VERSION = "active-sector-v1"
    }
}
