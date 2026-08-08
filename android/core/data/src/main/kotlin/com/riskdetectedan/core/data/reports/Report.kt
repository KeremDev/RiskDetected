package com.riskdetectedan.core.data.reports

import com.riskdetectedan.core.common.RdClientMetadata
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.storage.storage
import io.ktor.client.call.body
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
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
    @SerialName("storage_path") val storagePath: String,
    @SerialName("file_name") val fileName: String? = null,
    @SerialName("mime_type") val mimeType: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
)

@Serializable
private data class GenerateExcelReportBody(
    @SerialName("analysis_id") val analysisId: String,
    val method: String,
    @SerialName("request_id") val requestId: String,
    @SerialName("support_id") val supportId: String,
    @SerialName("client_app_version") val clientAppVersion: String,
    @SerialName("client_app_build") val clientAppBuild: String,
    @SerialName("client_platform") val clientPlatform: String,
    @SerialName("api_contract_version") val apiContractVersion: Int,
    @SerialName("client_capabilities") val clientCapabilities: Map<String, Boolean>,
)

@Serializable
private data class GenerateExcelReportResult(val report: Report? = null, val message: String? = null)

@Singleton
class ReportsRepository @Inject constructor(
    private val client: SupabaseClient,
    private val environmentConfig: RdEnvironmentConfig,
) {
    /**
     * Mirrors the `generate-excel-report` request contract. `method` is the risk-scoring method
     * the report renders under — same two wire values as [com.riskdetectedan.core.data.profile.RiskMethodWire]
     * ("fine_kinney"/"matrix_5x5"), always "fine_kinney" here since the profile's preferred
     * method isn't threaded through to this call site yet (matches: no preferredMethod editor
     * either, see ProfileRepository). Server-side quota/entitlement checks (report_quota_exceeded,
     * free_risk_analysis_trial_exhausted, plan-tier gates) surface as plain failures here — this
     * client makes no local entitlement decision, per the "backend is sole authority" invariant.
     */
    suspend fun generateExcelReport(analysisId: String, method: String = "fine_kinney"): RdResult<Report> = try {
        val result = client.functions.invoke(
            "generate-excel-report",
            body = GenerateExcelReportBody(
                analysisId = analysisId,
                method = method,
                requestId = UUID.randomUUID().toString(),
                supportId = UUID.randomUUID().toString(),
                clientAppVersion = environmentConfig.appVersionName,
                clientAppBuild = environmentConfig.appVersionCode.toString(),
                clientPlatform = RdClientMetadata.PLATFORM,
                apiContractVersion = RdClientMetadata.API_CONTRACT_VERSION,
                clientCapabilities = RdClientMetadata.capabilities,
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

    private companion object {
        const val BUCKET = "reports"
    }
}
