package com.riskdetectedan.core.data.account

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.storage.storage
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import javax.inject.Inject
import javax.inject.Singleton

data class UserDataExport(val bytes: ByteArray, val fileName: String)

@Serializable
private data class StoragePathRow(@SerialName("storage_path") val storagePath: String)

/** Client-side port of iOS AnalysisService's data-management operations. Every query runs with
 * the user's JWT and an explicit owner filter; RLS remains authoritative. Storage is removed
 * before database rows so a failed object deletion never leaves an archive row pointing to a
 * missing file. */
@Singleton
class UserDataRepository @Inject constructor(private val client: SupabaseClient) {
    private val prettyJson = Json { prettyPrint = true; prettyPrintIndent = "  " }

    suspend fun exportUserData(): RdResult<UserDataExport> = try {
        val user = client.auth.currentUserOrNull()
            ?: return RdResult.Failure("auth_required", "Oturum bulunamadı.")
        suspend fun ownedRows(table: String): List<JsonObject> = client.postgrest.from(table)
            .select { filter { eq("user_id", user.id) } }
            .decodeList()

        val profile = client.postgrest.from("profiles")
            .select { filter { eq("id", user.id) } }
            .decodeSingleOrNull<JsonObject>()
        val payload = buildJsonObject {
            put("exported_at", JsonPrimitive(Instant.now().toString()))
            put("user_id", JsonPrimitive(user.id))
            profile?.let { put("profile", it) }
            put("analyses", JsonArray(ownedRows("analyses")))
            put("findings", JsonArray(ownedRows("findings")))
            put("photos", JsonArray(ownedRows("photos")))
            put("reports", JsonArray(ownedRows("reports")))
        }
        val stamp = DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss")
            .withZone(ZoneId.of("Europe/Istanbul"))
            .format(Instant.now())
        RdResult.Success(
            UserDataExport(
                bytes = prettyJson.encodeToString(JsonObject.serializer(), payload).encodeToByteArray(),
                fileName = "RiskDetected_Verilerim_${user.id.take(8)}_$stamp.json",
            ),
        )
    } catch (t: Throwable) {
        RdResult.Failure("data_export_failed", t.message ?: "data_export_failed", t)
    }

    suspend fun deleteAllReports(): RdResult<Unit> = try {
        val user = client.auth.currentUserOrNull()
            ?: return RdResult.Failure("auth_required", "Oturum bulunamadı.")
        val reports = client.postgrest.from("reports")
            .select(Columns.list("storage_path")) { filter { eq("user_id", user.id) } }
            .decodeList<StoragePathRow>()
        if (reports.isNotEmpty()) {
            client.storage.from("reports").delete(reports.map { it.storagePath })
            client.postgrest.from("reports").delete { filter { eq("user_id", user.id) } }
        }
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure("bulk_report_delete_failed", t.message ?: "bulk_report_delete_failed", t)
    }

    suspend fun deleteAllAnalyses(): RdResult<Unit> = try {
        val user = client.auth.currentUserOrNull()
            ?: return RdResult.Failure("auth_required", "Oturum bulunamadı.")
        val photos = client.postgrest.from("photos")
            .select(Columns.list("storage_path")) { filter { eq("user_id", user.id) } }
            .decodeList<StoragePathRow>()
        val reports = client.postgrest.from("reports")
            .select(Columns.list("storage_path")) { filter { eq("user_id", user.id) } }
            .decodeList<StoragePathRow>()
        if (photos.isNotEmpty()) client.storage.from("photos").delete(photos.map { it.storagePath })
        if (reports.isNotEmpty()) client.storage.from("reports").delete(reports.map { it.storagePath })
        client.postgrest.from("analyses").delete { filter { eq("user_id", user.id) } }
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure("bulk_analysis_delete_failed", t.message ?: "bulk_analysis_delete_failed", t)
    }
}
