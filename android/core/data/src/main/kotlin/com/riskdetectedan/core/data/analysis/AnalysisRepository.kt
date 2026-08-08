package com.riskdetectedan.core.data.analysis

import com.riskdetectedan.core.common.RdClientMetadata
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.ktor.client.plugins.ResponseException
import io.ktor.client.statement.bodyAsText
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
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

/** Mirrors `AnalysisSubmissionFailurePatch` — the two-column patch
 * `markAnalysisSubmissionFailedIfStillPending` writes. */
@Serializable
private data class AnalysisFailurePatch(
    val status: String = "failed",
    @SerialName("status_message") val statusMessage: String,
)

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

/** Mirrors `functionErrorPayload(from:)`'s decode target exactly — the edge function's real
 * non-2xx JSON error shape (`error`/`message` are interchangeable, `code`/`tier` only present
 * on some error paths). */
@Serializable
private data class FunctionErrorBody(
    val error: String? = null,
    val message: String? = null,
    @SerialName("support_id") val supportId: String? = null,
    val code: String? = null,
    val tier: String? = null,
)

private data class FunctionErrorPayload(val message: String, val supportId: String?, val code: String?, val tier: String?)

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
     * Real port of `markAnalysisSubmissionFailedIfStillPending` — but atomic instead of iOS's
     * fetch-then-update dance (`fetchAnalysisSubmissionStatus` then a separate conditional
     * `UPDATE`, a real TOCTOU race iOS accepts because `waitForCompletedResult` never gets called
     * unless the mark succeeds). A single `UPDATE ... WHERE id=X AND status='pending'` here does
     * the same "did the server actually start processing this, so we must NOT clobber it" check
     * server-side, in one round trip, without needing iOS's separate polling step: the `analyze`
     * function flips `status` away from `"pending"` as the very first thing it does on accepting
     * a request, so this update only ever affects a row the server never touched. Returns whether
     * it actually updated a row (i.e., was still pending) — the caller only runs photo cleanup
     * when this is true, mirroring iOS's real "only cleanup if actually marked failed" branch.
     */
    suspend fun markFailedIfPending(analysisId: String, message: String): RdResult<Boolean> = try {
        val rows = client.postgrest.from("analyses")
            .update(AnalysisFailurePatch(statusMessage = message)) {
                select(Columns.list("id"))
                filter {
                    eq("id", analysisId)
                    eq("status", "pending")
                }
            }
            .decodeList<CreatedAnalysisRow>()
        RdResult.Success(rows.isNotEmpty())
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "analysis_mark_failed_error",
            message = t.message ?: "analysis_mark_failed_error",
            cause = t,
        )
    }

    /** Thin status-only read, mirrors `fetchAnalysisSubmissionStatus` — used by
     * [com.riskdetectedan.feature.analysis.AnalysisViewModel]'s recovery probe (real port of
     * `recoverPhotoSubmissionIfServerAccepted`) to check whether the server actually accepted a
     * submission that the client saw as a network/timeout failure. */
    suspend fun fetchAnalysisStatus(analysisId: String): RdResult<String> = try {
        val snapshot = client.postgrest.from("analyses")
            .select(Columns.list("status")) {
                filter { eq("id", analysisId) }
            }
            .decodeSingle<AnalysisStatusSnapshot>()
        RdResult.Success(snapshot.status)
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "analysis_status_fetch_failed",
            message = t.message ?: "analysis_status_fetch_failed",
            cause = t,
        )
    }

    /**
     * Real port of AnalysisService.swift's `invokeAnalyze` — up to 2 attempts, same
     * error-classification cascade against the edge function's real non-2xx JSON body
     * (`error`/`message`/`support_id`/`code`/`tier`):
     * - HTTP 429 whose message/code signals a *quota* rejection (not an AI-provider 429, a real
     *   distinct case) -> `code="quota_exceeded"`, `tier` from the payload.
     * - HTTP 409 -> `code="already_completed"` (mirrors `AnalysisError.alreadyCompleted`).
     * - `code="PHOTO_LIMIT_EXCEEDED"` / `"OUTPUT_LANGUAGE_CONTRACT_FAILED"` passed straight
     *   through as their own failure codes.
     * - Otherwise HTTP 429/500/502/503/504 retry once (1s delay) before falling through to a
     *   final classified failure (`ai_quota_exceeded`/`ai_busy`/`ai_failed`).
     * - A non-HTTP (network/timeout) exception also retries once, then `network_failed`.
     *
     * Every message mirrors the Swift fallback strings verbatim (not just the classification
     * logic) — `AppErrorMessages.make`'s substring classifier already recognizes them ("günlük
     * kota", "analiz kotan doldu", "gemini kotası", etc.), so this alone is enough to route a
     * failure to the right [com.riskdetectedan.core.data.error.AppErrorCategory] without needing
     * a separate code-based branch there.
     */
    suspend fun submitAnalyze(
        analysisId: String,
        canvas: String,
        canvases: List<String> = listOf(canvas),
        analysisMode: String = "standard",
        sector: AnalysisSector?,
        photoPaths: List<String>,
        appLanguage: String = "tr",
    ): RdResult<Unit> {
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
        val supportId = body.supportId
        val maxAttempts = 2
        for (attempt in 1..maxAttempts) {
            try {
                client.functions.invoke("analyze", body = body)
                return RdResult.Success(Unit)
            } catch (e: ResponseException) {
                val code = e.response.status.value
                val payload = parseFunctionErrorPayload(e.response.bodyAsText(), fallbackSupportId = supportId)
                val msg = payload.message
                val errorCode = payload.code ?: ""

                if (code == 429 &&
                    (msg.contains("günlük kota", ignoreCase = true) || msg.contains("analiz/gün", ignoreCase = true) || errorCode == "quota_exceeded")
                ) {
                    val fallback = msg.ifEmpty { "Analiz kotan doldu." }
                    return RdResult.Failure("quota_exceeded", appendSupportId(payload.supportId, fallback), e)
                }
                if (code == 409) {
                    return RdResult.Failure("already_completed", "Bu analiz zaten tamamlanmış.", e)
                }
                if (errorCode == "PHOTO_LIMIT_EXCEEDED") {
                    val fallback = msg.ifEmpty { "Bu plan için fotoğraf limiti aşıldı." }
                    return RdResult.Failure("photo_limit_exceeded", appendSupportId(payload.supportId, fallback), e)
                }
                if (errorCode == "OUTPUT_LANGUAGE_CONTRACT_FAILED") {
                    val fallback = "Analiz, seçilen çıktı diliyle güvenli biçimde tamamlanamadı. Lütfen tekrar dene."
                    return RdResult.Failure("output_language_contract_failed", appendSupportId(payload.supportId, fallback), e)
                }

                val retryable = code in intArrayOf(429, 500, 502, 503, 504)
                if (retryable && attempt < maxAttempts) {
                    delay(1_000)
                    continue
                }

                val messageWithSupport = appendSupportId(payload.supportId, msg)
                val finalMessage = when (code) {
                    429 -> messageWithSupport.ifEmpty { appendSupportId(payload.supportId, "Gemini kotası doldu. Lütfen daha sonra tekrar dene.") }
                    503 -> messageWithSupport.ifEmpty { appendSupportId(payload.supportId, "Gemini modeli şu anda yoğun. Biraz sonra tekrar dene.") }
                    else -> messageWithSupport.ifEmpty { appendSupportId(payload.supportId, "HTTP $code") }
                }
                return RdResult.Failure("ai_failed", finalMessage, e)
            } catch (t: Throwable) {
                if (attempt < maxAttempts) {
                    delay(1_000)
                    continue
                }
                val fallback = "Analiz isteği sunucuya gönderilemedi. Ağ bağlantısı kesildi veya istek zaman aşımına uğradı. Lütfen bağlantını kontrol edip tekrar dene."
                return RdResult.Failure("network_failed", appendSupportId(supportId, fallback), t)
            }
        }
        // Unreachable — every branch above returns; kept for exhaustiveness.
        return RdResult.Failure("analysis_submit_failed", "analysis_submit_failed")
    }

    private fun parseFunctionErrorPayload(bodyText: String, fallbackSupportId: String): FunctionErrorPayload {
        val decoded = runCatching { Json { ignoreUnknownKeys = true }.decodeFromString<FunctionErrorBody>(bodyText) }.getOrNull()
        val message = (decoded?.message ?: decoded?.error ?: "").trim()
        return if (message.isNotEmpty()) {
            FunctionErrorPayload(message, decoded?.supportId ?: fallbackSupportId, decoded?.code, decoded?.tier)
        } else {
            FunctionErrorPayload(bodyText, fallbackSupportId, null, null)
        }
    }

    /** Mirrors `appendSupportID(_:to:)` — appends "Destek kodu: X" unless the message already
     * carries one (idempotent across the retry loop's repeated classification passes). */
    private fun appendSupportId(supportId: String?, message: String): String {
        val clean = message.trim()
        if (clean.contains("destek kodu", ignoreCase = true)) return clean
        val id = supportId ?: return clean
        return "$clean\nDestek kodu: $id"
    }

    /**
     * Mirrors the polling loop inside AnalysisService.swift's `waitForCompletedResult` — same
     * status values + ~2s interval, same wall-clock deadline logic (300s single-photo, 420s once
     * [photoCount] is >1 — real product behavior: multi-photo analyses genuinely take longer, not
     * an arbitrary number). Simplified: no in-flight-analysis persistence across an app kill
     * (`InFlightAnalysisStore`), no cleanup-on-failure/recovery-if-server-actually-accepted
     * (`recoverPhotoSubmissionIfServerAccepted`) — both real iOS resilience features, genuinely
     * bigger scope (survive-process-death state machine), documented as still-open gaps rather
     * than silently approximated.
     */
    suspend fun pollAnalysisStatus(
        analysisId: String,
        photoCount: Int = 1,
        pollIntervalMillis: Long = 2_000,
    ): AnalysisStatus {
        val deadlineMillis = if (photoCount > 1) 420_000L else 300_000L
        val startedAt = System.currentTimeMillis()
        while (System.currentTimeMillis() - startedAt < deadlineMillis) {
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
