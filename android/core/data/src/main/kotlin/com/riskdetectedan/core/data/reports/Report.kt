package com.riskdetectedan.core.data.reports

import com.riskdetectedan.core.common.RdClientMetadata
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.profile.SubscriptionTier
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Count
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.storage.storage
import io.ktor.client.call.body
import io.ktor.client.plugins.ResponseException
import io.ktor.client.statement.bodyAsText
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Partial mirror of the `reports` row `generate-excel-report/index.ts` inserts and returns
 * (`.select().single()` on the full row) / [ReportsRepository.listReports]'s list query — decodes
 * just the columns the client needs (fetch+present the file, or show it in a list row);
 * ignoreUnknownKeys handles the rest, same pattern as [com.riskdetectedan.core.data.analysis.Finding]'s
 * mutation result. `kind`/`method`/`createdAt` are only populated by the list query (Faz R) — the
 * generate-report response doesn't select them, they stay null there, harmless (nothing reads them
 * on that path). DEC-09: Android's own report *rendering* (PDF) is on-device
 * (`android.graphics.pdf.PdfDocument`, not ported yet) — this is the separate, already-server-side
 * XLSX path (`generate-excel-report`), which both platforms have always used as-is; nothing here
 * duplicates DEC-09's device-side PDF decision.
 */
@Serializable
data class Report(
    val id: String,
    @SerialName("document_no") val documentNo: String? = null,
    val format: String? = null,
    val kind: String? = null,
    val method: String? = null,
    val title: String? = null,
    @SerialName("company_id") val companyId: String? = null,
    @SerialName("storage_path") val storagePath: String,
    @SerialName("file_name") val fileName: String? = null,
    @SerialName("mime_type") val mimeType: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
)

/** Read-only UI guidance matching iOS `monthlyReportQuotaUsage` and
 * `freeRiskAnalysisTrialUsage`. Inserts remain server-owned and every generation request is still
 * revalidated by the Edge Function/database trigger. */
data class ReportQuotaUsage(
    val standardUsed: Int,
    val standardLimit: Int,
    val riskTrialUsed: Boolean,
) {
    val isStandardQuotaExhausted: Boolean get() = standardUsed >= standardLimit
}

@Serializable
private data class GenerateExcelReportBody(
    @SerialName("analysis_id") val analysisId: String,
    val method: String,
    @SerialName("report_kind") val reportKind: String,
    @SerialName("report_language") val reportLanguage: String,
    @SerialName("company_id") val companyId: String? = null,
    @SerialName("request_id") val requestId: String,
    @SerialName("support_id") val supportId: String,
    @SerialName("client_app_version") val clientAppVersion: String,
    @SerialName("client_app_build") val clientAppBuild: String,
    @SerialName("client_platform") val clientPlatform: String,
    @SerialName("api_contract_version") val apiContractVersion: Int,
    @SerialName("client_capabilities") val clientCapabilities: Map<String, Boolean>,
    @SerialName("app_language") val appLanguage: String,
    @SerialName("content_locale") val contentLocale: String,
    @SerialName("work_jurisdiction_country") val workJurisdictionCountry: String,
    @SerialName("safety_profile_id") val safetyProfileId: String,
    @SerialName("safety_profile_version") val safetyProfileVersion: Int,
)

@Serializable
private data class GenerateExcelReportResult(val report: Report? = null, val message: String? = null)

/** Mirrors `RegisterReportBody`'s real shape — checked directly in
 * `supabase/functions/register-report/index.ts`, not guessed. Only `analysis_id`/`storage_path`/
 * `file_name`/`mime_type`/`file_size` are actually validated server-side (must be a completed
 * analysis owned by the caller, `storage_path` must start with `{userId}/{analysisId}/`,
 * `mime_type` must be exactly `"application/pdf"`, `0 < file_size <= 20MB`) — everything else has
 * a server-side default. `findings_snapshot_json`/`photos_snapshot_json` are deliberately NOT
 * sent: traced the function's own source and confirmed it re-derives the real stored snapshot
 * itself via its own `analysis_id`-scoped query (`REPORT_FINDINGS_SELECT`/`REPORT_PHOTOS_SELECT`)
 * — anything the client sent in those two fields is parsed into the request type but never read
 * again, so sending them would just be dead weight matching iOS's audit-trail *intent* without
 * doing anything the server actually uses. */
@Serializable
private data class RegisterReportBody(
    @SerialName("analysis_id") val analysisId: String,
    val kind: String,
    val method: String,
    val title: String,
    @SerialName("storage_path") val storagePath: String,
    @SerialName("file_name") val fileName: String,
    @SerialName("mime_type") val mimeType: String = "application/pdf",
    @SerialName("file_size") val fileSize: Int,
    @SerialName("size_bytes") val sizeBytes: Int,
    @SerialName("page_count") val pageCount: Int,
    @SerialName("company_id") val companyId: String? = null,
    @SerialName("report_language") val reportLanguage: String = "tr",
    @SerialName("client_app_version") val clientAppVersion: String,
    @SerialName("client_app_build") val clientAppBuild: String,
    @SerialName("client_platform") val clientPlatform: String,
    @SerialName("api_contract_version") val apiContractVersion: Int,
    @SerialName("client_capabilities") val clientCapabilities: Map<String, Boolean>,
    @SerialName("app_language") val appLanguage: String,
    @SerialName("content_locale") val contentLocale: String,
    @SerialName("work_jurisdiction_country") val workJurisdictionCountry: String,
    @SerialName("safety_profile_id") val safetyProfileId: String,
    @SerialName("safety_profile_version") val safetyProfileVersion: Int,
    @SerialName("request_id") val requestId: String,
    @SerialName("support_id") val supportId: String,
)

@Singleton
class ReportsRepository @Inject constructor(
    private val client: SupabaseClient,
    private val environmentConfig: RdEnvironmentConfig,
) {
    suspend fun fetchQuotaUsage(userId: String, tier: SubscriptionTier): RdResult<ReportQuotaUsage> = try {
        coroutineScope {
            val zone = ZoneId.of("Europe/Istanbul")
            val today = LocalDate.now(zone)
            val periodStart = if (tier == SubscriptionTier.Free) {
                today.atStartOfDay(zone).toInstant()
            } else {
                today.withDayOfMonth(1).atStartOfDay(zone).toInstant()
            }
            val standard = async {
                client.postgrest.from("usage_events").select(columns = Columns.list("id")) {
                    head = true
                    count(Count.EXACT)
                    filter {
                        eq("user_id", userId)
                        eq("feature", "report_standard")
                        eq("event_type", "completed")
                        gte("created_at", DateTimeFormatter.ISO_INSTANT.format(periodStart))
                    }
                }.countOrNull()?.toInt() ?: 0
            }
            val riskTrial = async {
                client.postgrest.from("usage_events").select(columns = Columns.list("id")) {
                    head = true
                    count(Count.EXACT)
                    filter {
                        eq("user_id", userId)
                        eq("feature", "report_risk_analysis_trial")
                        eq("event_type", "completed")
                    }
                }.countOrNull()?.toInt() ?: 0
            }
            val limit = when (tier) {
                SubscriptionTier.Free -> 1
                SubscriptionTier.Plus -> 150
                SubscriptionTier.Pro -> 750
            }
            RdResult.Success(
                ReportQuotaUsage(
                    standardUsed = standard.await(),
                    standardLimit = limit,
                    riskTrialUsed = riskTrial.await() > 0,
                ),
            )
        }
    } catch (t: Throwable) {
        RdResult.Failure("report_quota_fetch_failed", t.message ?: "report_quota_fetch_failed", t)
    }

    /**
     * Mirrors the `generate-excel-report` request contract. `method` is the risk-scoring method
     * the report renders under — same two wire values as [com.riskdetectedan.core.data.profile.RiskMethodWire]
     * ("fine_kinney"/"matrix_5x5"), always "fine_kinney" here since the profile's preferred
     * method isn't threaded through to this call site yet (matches: no preferredMethod editor
     * either, see ProfileRepository). Server-side quota/entitlement checks (report_quota_exceeded,
     * free_risk_analysis_trial_exhausted, plan-tier gates) surface as plain failures here — this
     * client makes no local entitlement decision, per the "backend is sole authority" invariant.
     */
    suspend fun generateExcelReport(
        analysisId: String,
        method: String = "fine_kinney",
        companyId: String? = null,
        reportLanguage: String = "tr",
    ): RdResult<Report> = try {
        val result = client.functions.invoke(
            "generate-excel-report",
            body = GenerateExcelReportBody(
                analysisId = analysisId,
                method = method,
                reportKind = "risk_analysis",
                reportLanguage = reportLanguage,
                companyId = companyId,
                requestId = UUID.randomUUID().toString(),
                supportId = UUID.randomUUID().toString(),
                clientAppVersion = environmentConfig.appVersionName,
                clientAppBuild = environmentConfig.appVersionCode.toString(),
                clientPlatform = RdClientMetadata.PLATFORM,
                apiContractVersion = RdClientMetadata.API_CONTRACT_VERSION,
                clientCapabilities = RdClientMetadata.capabilities,
                appLanguage = RdClientMetadata.APP_LANGUAGE,
                contentLocale = RdClientMetadata.CONTENT_LOCALE,
                workJurisdictionCountry = RdClientMetadata.WORK_JURISDICTION_COUNTRY,
                safetyProfileId = RdClientMetadata.SAFETY_PROFILE_ID,
                safetyProfileVersion = RdClientMetadata.SAFETY_PROFILE_VERSION,
            ),
        ).body<GenerateExcelReportResult>()

        val report = result.report
        if (report != null) {
            RdResult.Success(report)
        } else {
            RdResult.Failure(
                code = "report_generate_failed",
                message = result.message ?: "Rapor oluşturulamadı.",
            )
        }
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "report_generate_failed",
            message = t.message ?: "Rapor oluşturulamadı.",
            cause = t,
        )
    }

    /**
     * Faz R — the real "Raporlar" tab's list query, mirrors iOS's own real fetch of `ReportRow`
     * (a genuinely different table/list than [com.riskdetectedan.core.data.analysis.HistoryRepository.listHistory]'s
     * `analyses` history — iOS's "reports" tab is generated PDF/XLSX archives, not analysis
     * records). Same Postgrest-select-order-limit shape as `listHistory`.
     */
    suspend fun listReports(userId: String, limit: Long = 50): RdResult<List<Report>> = try {
        val items = client.postgrest.from("reports")
            .select {
                filter { eq("user_id", userId) }
                order("created_at", Order.DESCENDING)
                limit(limit)
            }
            .decodeList<Report>()
        RdResult.Success(items)
    } catch (t: Throwable) {
        RdResult.Failure("reports_list_fetch_failed", t.message ?: "reports_list_fetch_failed", t)
    }

    /**
     * Real port of `storeReport` — uploads on-device-generated PDF bytes (from
     * [PdfReportGenerator]) to the private "reports" bucket, then calls the real `register-report`
     * edge function (shared server-side infra — real quota enforcement, `analysis.status ==
     * "completed"` check, path-ownership validation all happen there, matching the "backend is
     * sole authority" invariant every other repository in this app follows). On a register
     * failure, best-effort removes the just-uploaded orphan object (matches iOS's own cleanup —
     * a PDF sitting in Storage with no `reports` row pointing at it is worse than briefly
     * duplicating the delete call).
     *
     * [fileNameSlug] mirrors `safeReportFileName`'s real shape (`riskdetected_{title}_
     * risk-analizi_{kind}_{method}_{shortId}_{timestamp}.pdf`) — the caller builds it (feature
     * layer already has the analysis title in hand) rather than this repository re-deriving it,
     * keeping the transliteration/slugify logic in one place ([PdfReportFileName]).
     */
    suspend fun uploadAndRegisterPdfReport(
        userId: String,
        analysisId: String,
        pdfBytes: ByteArray,
        fileNameSlug: String,
        kind: String,
        method: String,
        title: String,
        pageCount: Int,
        companyId: String? = null,
        reportLanguage: String = "tr",
    ): RdResult<Report> {
        val storagePath = "${userId.lowercase()}/${analysisId.lowercase()}/$fileNameSlug"
        try {
            client.storage.from(BUCKET).upload(storagePath, pdfBytes) {
                upsert = true
            }
        } catch (t: Throwable) {
            return RdResult.Failure("report_pdf_upload_failed", t.message ?: "PDF dosyası rapor arşivine yüklenemedi.", t)
        }

        return try {
            val requestId = UUID.randomUUID().toString()
            val supportId = UUID.randomUUID().toString()
            val row: Report = client.functions.invoke(
                "register-report",
                body = RegisterReportBody(
                    analysisId = analysisId,
                    kind = kind,
                    method = method,
                    title = title,
                    storagePath = storagePath,
                    fileName = fileNameSlug,
                    fileSize = pdfBytes.size,
                    sizeBytes = pdfBytes.size,
                    pageCount = pageCount,
                    companyId = companyId,
                    reportLanguage = reportLanguage,
                    clientAppVersion = environmentConfig.appVersionName,
                    clientAppBuild = environmentConfig.appVersionCode.toString(),
                    clientPlatform = RdClientMetadata.PLATFORM,
                    apiContractVersion = RdClientMetadata.API_CONTRACT_VERSION,
                    clientCapabilities = RdClientMetadata.capabilities,
                    appLanguage = RdClientMetadata.APP_LANGUAGE,
                    contentLocale = RdClientMetadata.CONTENT_LOCALE,
                    workJurisdictionCountry = RdClientMetadata.WORK_JURISDICTION_COUNTRY,
                    safetyProfileId = RdClientMetadata.SAFETY_PROFILE_ID,
                    safetyProfileVersion = RdClientMetadata.SAFETY_PROFILE_VERSION,
                    requestId = requestId,
                    supportId = supportId,
                ),
            ).body<Report>()
            RdResult.Success(row)
        } catch (t: Throwable) {
            runCatching { client.storage.from(BUCKET).delete(listOf(storagePath)) }
            // Real error body ({error, message, request_id, support_id}) only exists on a
            // ResponseException (a real HTTP 4xx/5xx) — a plain network exception's `.message`
            // never contains it, so this only attempts the parse when there's an actual response
            // to read (mirrors AnalysisRepository.submitAnalyze's ResponseException handling).
            val errorCode = if (t is ResponseException) {
                runCatching {
                    val bodyText = t.response.bodyAsText()
                    Json.parseToJsonElement(bodyText).jsonObject["error"]
                        ?.let { it as? JsonPrimitive }?.contentOrNull
                }.getOrNull()
            } else {
                null
            }
            val classified = when (errorCode) {
                "free_risk_analysis_trial_exhausted" -> "free_risk_analysis_trial_exhausted:1/1"
                "report_quota_exceeded" -> "report_quota_exceeded"
                else -> t.message?.ifEmpty { null } ?: "Rapor arşiv kaydı tamamlanamadı."
            }
            RdResult.Failure("report_register_failed", classified, t)
        }
    }

    /** Downloads the just-generated (or previously generated) file's bytes from the private
     * "reports" storage bucket — same bucket name the edge function uploads to. The caller
     * (feature layer, which has an Android `Context`) is responsible for writing these bytes to
     * a shareable location; this repository stays platform-storage-only, no `Context` here. */
    suspend fun downloadReportBytes(storagePath: String): RdResult<ByteArray> = try {
        val bytes = client.storage.from(BUCKET).downloadAuthenticated(storagePath)
        RdResult.Success(bytes)
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "report_download_failed",
            message = t.message ?: "Rapor indirilemedi.",
            cause = t,
        )
    }

    /** Real gap sweep finding (2026-08-09): the generated-reports list had no delete action —
     * real port of `AnalysisService.swift`'s `deleteReport(_:...)`: remove the file from the
     * `reports` storage bucket, then delete the `reports` row. Unlike [downloadReportBytes]'s
     * storage-only scope, this also touches the row — matches iOS exactly (storage failure is
     * fatal here, unlike [com.riskdetectedan.core.data.analysis.HistoryRepository.deleteAnalysis]'s
     * best-effort cleanup, since deleting *only* the row would silently orphan a real file a user
     * might expect gone). */
    suspend fun deleteReport(report: Report): RdResult<Unit> = try {
        client.storage.from(BUCKET).delete(listOf(report.storagePath))
        client.postgrest.from("reports").delete { filter { eq("id", report.id) } }
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "report_delete_failed",
            message = t.message ?: "Rapor silinemedi.",
            cause = t,
        )
    }

    private companion object {
        const val BUCKET = "reports"
    }
}
