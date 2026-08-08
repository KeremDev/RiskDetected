package com.riskdetectedan.core.data.analysis

import android.graphics.BitmapFactory
import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
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

@Singleton
class PhotoRepository @Inject constructor(
    private val client: SupabaseClient,
) {
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
