package com.riskdetectedan.core.data.analysis

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.storage.storage
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Partial mirror of App/Models/HistoryItem.swift's `AnalysisRow` — just the columns that
 * feed HistoryItem's `init(row:)` mapping (title, canvas, status, finding_count,
 * highest_band_fk/m5, company_id, kind, created_at). The richer per-finding detail lives in
 * [Finding]/[FindingsRepository] — this is the list-row shape, not the detail shape.
 */
@Serializable
data class HistoryItem(
    val id: String,
    val title: String,
    val canvas: String,
    val status: String,
    val kind: String,
    @SerialName("finding_count") val findingCount: Int = 0,
    @SerialName("highest_band_fk") val highestBandFk: String? = null,
    @SerialName("highest_band_m5") val highestBandM5: String? = null,
    @SerialName("company_id") val companyId: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
) {
    /** Same fallback order as HistoryItem.swift's init(row:): highestBandFK ?? highestBandM5 ?? "unknown". */
    val riskBand: String get() = highestBandFk ?: highestBandM5 ?: "unknown"

    /** Same status mapping as iOS: status == "completed" ? .reviewed : .open — iOS's third
     * state (.closed) has no server-side signal yet on either platform (it's a future manual
     * "mark closed" action, not derived from `status`), so it's not reachable from this mapping
     * on either platform today. */
    val historyStatus: String get() = if (status == "completed") "reviewed" else "open"
}

@Serializable
private data class StoragePathRow(@SerialName("storage_path") val storagePath: String)

@Singleton
class HistoryRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    suspend fun listHistory(userId: String, limit: Long = 50): RdResult<List<HistoryItem>> = try {
        val items = client.postgrest.from("analyses")
            .select {
                filter { eq("user_id", userId) }
                order("created_at", Order.DESCENDING)
                limit(limit)
            }
            .decodeList<HistoryItem>()
        RdResult.Success(items)
    } catch (t: Throwable) {
        RdResult.Failure("history_fetch_failed", t.message ?: "history_fetch_failed", t)
    }

    /** Real gap sweep finding (2026-08-09): Android's History list had no delete action at all —
     * mirrors `AnalysisService.swift`'s `deleteAnalysis(analysisID:...)` exactly: remove the
     * analysis's photos from the `photos` storage bucket, its generated reports from the
     * `reports` storage bucket, then delete the `analyses` row itself (cascades to
     * findings/photos/reports rows via FK, same as iOS relies on). Storage removal failures are
     * non-fatal here — an orphaned storage object with no DB row pointing at it is a harmless
     * leak, not a correctness problem, same reasoning iOS's own `runCatching`-style storage
     * cleanup in [com.riskdetectedan.core.data.reports.ReportsRepository] already uses. */
    suspend fun deleteAnalysis(analysisId: String): RdResult<Unit> = try {
        val photoPaths = client.postgrest.from("photos")
            .select(Columns.list("storage_path")) { filter { eq("analysis_id", analysisId) } }
            .decodeList<StoragePathRow>()
            .map { it.storagePath }
        val reportPaths = client.postgrest.from("reports")
            .select(Columns.list("storage_path")) { filter { eq("analysis_id", analysisId) } }
            .decodeList<StoragePathRow>()
            .map { it.storagePath }

        if (photoPaths.isNotEmpty()) {
            runCatching { client.storage.from("photos").delete(photoPaths) }
        }
        if (reportPaths.isNotEmpty()) {
            runCatching { client.storage.from("reports").delete(reportPaths) }
        }

        client.postgrest.from("analyses").delete { filter { eq("id", analysisId) } }
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure("analysis_delete_failed", t.message ?: "analysis_delete_failed", t)
    }
}
