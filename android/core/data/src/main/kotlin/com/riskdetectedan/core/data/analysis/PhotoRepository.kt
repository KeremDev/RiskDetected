package com.riskdetectedan.core.data.analysis

import android.graphics.BitmapFactory
import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.storage.storage
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors AnalysisService.swift's uploadPhotosForAnalysis: same bucket (RDConfig.Bucket.photos
 * = "photos"), same storage path convention (`{userId}/{analysisId}/p{sequenceIndex}.jpg`),
 * same `photos` table insert. Deliberately does NOT send `compression_metadata` or
 * `upload_payload_version` — iOS's values there (`photo-batch-storage-v1`,
 * jpeg_quality/quality_policy from its multi-candidate compression ladder) describe iOS's own
 * adaptive-compression pipeline, which Android doesn't have yet (CaptureScreen writes a single
 * CameraX JPEG as-is). Both columns have real DB defaults (`{}`, `'photo-single-v1'`) that are
 * honest for what Android actually does right now — sending fabricated iOS-shaped metadata
 * would be worse than omitting it.
 */
@Serializable
private data class PhotoInsertPayload(
    @SerialName("analysis_id") val analysisId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("storage_path") val storagePath: String,
    val width: Int?,
    val height: Int?,
    @SerialName("size_bytes") val sizeBytes: Int,
    @SerialName("byte_size") val byteSize: Int,
    @SerialName("mime_type") val mimeType: String = "image/jpeg",
    @SerialName("sequence_index") val sequenceIndex: Int,
    @SerialName("client_photo_id") val clientPhotoId: String,
    @SerialName("is_primary") val isPrimary: Boolean,
)

/** Partial mirror of `AnalysisPhotoRow` — just the columns [com.riskdetectedan.core.data.reports.PdfReportGenerator]
 * needs to lay out photos on a report page. */
@Serializable
data class AnalysisPhoto(
    @SerialName("storage_path") val storagePath: String,
    @SerialName("sequence_index") val sequenceIndex: Int = 1,
    @SerialName("is_primary") val isPrimary: Boolean = false,
)

/** Decode target for [PhotoRepository.firstPhotoPaths]'s batched query — a different column
 * subset than [AnalysisPhoto] (needs `analysis_id` to build the map key, doesn't need
 * `is_primary`). */
@Serializable
private data class PhotoPathRow(
    @SerialName("analysis_id") val analysisId: String,
    @SerialName("storage_path") val storagePath: String,
    @SerialName("sequence_index") val sequenceIndex: Int = 1,
)

@Singleton
class PhotoRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    /** Real port of `firstPhotoPaths`/the photos-list half of `fetchOptionalPhotos` — ordered by
     * `sequence_index`, used by on-device PDF report generation to know which photos an
     * already-completed (possibly long-past) analysis has, since the local capture files are
     * long gone by the time a report gets (re)generated from History. */
    suspend fun listPhotos(analysisId: String): RdResult<List<AnalysisPhoto>> = try {
        val photos = client.postgrest.from("photos")
            .select(Columns.list("storage_path", "sequence_index", "is_primary")) {
                filter { eq("analysis_id", analysisId) }
                order("sequence_index", Order.ASCENDING)
            }
            .decodeList<AnalysisPhoto>()
        RdResult.Success(photos)
    } catch (t: Throwable) {
        RdResult.Failure("photo_list_failed", t.message ?: "photo_list_failed", t)
    }

    /** Real port of `firstPhotoPaths(analysisIDs:)` — batch-fetches just the first (lowest
     * `sequence_index`, `storage_path` as tiebreaker — same double `order()` as the Swift query)
     * photo path per analysis, for list-card thumbnails (Home's recent-analyses ring — see
     * [com.riskdetectedan.core.data.analysis.AnalysisPhoto]'s sibling doc comment for the
     * long-past-History-item rationale, same one applies here). Empty input short-circuits to an
     * empty map without a network call, matching the Swift guard. */
    suspend fun firstPhotoPaths(analysisIds: List<String>): RdResult<Map<String, String>> {
        if (analysisIds.isEmpty()) return RdResult.Success(emptyMap())
        return try {
            val rows = client.postgrest.from("photos")
                .select(Columns.list("analysis_id", "storage_path", "sequence_index")) {
                    filter { isIn("analysis_id", analysisIds) }
                    order("sequence_index", Order.ASCENDING)
                    order("storage_path", Order.ASCENDING)
                }
                .decodeList<PhotoPathRow>()
            val paths = LinkedHashMap<String, String>()
            for (row in rows) {
                paths.getOrPut(row.analysisId) { row.storagePath }
            }
            RdResult.Success(paths)
        } catch (t: Throwable) {
            RdResult.Failure("photo_paths_fetch_failed", t.message ?: "photo_paths_fetch_failed", t)
        }
    }

    /** Real port of `photoData(path:requestID:supportID:)` — downloads a previously-uploaded
     * photo's bytes back from Storage (the "photos" bucket is private, same authenticated
     * download pattern [com.riskdetectedan.core.data.reports.ReportsRepository.downloadReportBytes]
     * already uses for the "reports" bucket). */
    suspend fun downloadPhoto(storagePath: String): RdResult<ByteArray> = try {
        val bytes = client.storage.from(BUCKET).downloadAuthenticated(storagePath)
        RdResult.Success(bytes)
    } catch (t: Throwable) {
        RdResult.Failure("photo_download_failed", t.message ?: "photo_download_failed", t)
    }

    /** sequenceIndex is 1-based, matching iOS's `p1.jpg`/`is_primary = sequenceIndex == 1`. */
    suspend fun uploadPhoto(
        userId: String,
        analysisId: String,
        sequenceIndex: Int,
        jpegBytes: ByteArray,
    ): RdResult<String> = try {
        val storagePath = "${userId.lowercase()}/${analysisId.lowercase()}/p$sequenceIndex.jpg"

        client.storage.from(BUCKET).upload(storagePath, jpegBytes) {
            upsert = true
        }

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size, bounds)

        client.postgrest.from("photos").insert(
            PhotoInsertPayload(
                analysisId = analysisId,
                userId = userId,
                storagePath = storagePath,
                width = bounds.outWidth.takeIf { it > 0 },
                height = bounds.outHeight.takeIf { it > 0 },
                sizeBytes = jpegBytes.size,
                byteSize = jpegBytes.size,
                sequenceIndex = sequenceIndex,
                clientPhotoId = UUID.randomUUID().toString(),
                isPrimary = sequenceIndex == 1,
            ),
        )

        RdResult.Success(storagePath)
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "photo_upload_failed",
            message = t.message ?: "photo_upload_failed",
            cause = t,
        )
    }

    /**
     * Real port of `cleanupUploadedPhotos` — removes the just-uploaded Storage objects + their
     * `photos` rows when an analysis submission ultimately fails. Best-effort: iOS itself only
     * logs a cleanup failure rather than surfacing it (the analysis is already being marked
     * failed regardless — a stray orphaned photo object is a much smaller problem than hiding
     * the real failure behind a secondary cleanup error), so this never returns [RdResult.Failure]
     * to a UI-facing caller — it's fire-and-forget by design, matching iOS's own `catch { log }`.
     */
    suspend fun deleteUploadedPhotos(userId: String, analysisId: String, storagePaths: List<String>) {
        try {
            if (storagePaths.isNotEmpty()) {
                client.storage.from(BUCKET).delete(storagePaths)
            }
            client.postgrest.from("photos").delete {
                filter {
                    eq("analysis_id", analysisId)
                    eq("user_id", userId)
                }
            }
        } catch (_: Throwable) {
            // Best-effort, see doc comment — a failed cleanup here doesn't change the outcome
            // the caller already surfaced (the analysis submission itself failed).
        }
    }

    private companion object {
        const val BUCKET = "photos"
    }
}
