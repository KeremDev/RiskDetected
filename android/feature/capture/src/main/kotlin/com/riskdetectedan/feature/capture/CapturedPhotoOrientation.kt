package com.riskdetectedan.feature.capture

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max

private const val MAX_CAPTURE_LONG_EDGE = 2400

/**
 * Prepares a camera or gallery image for preview, annotation and upload.
 *
 * BitmapFactory ignores EXIF orientation, and decoding an unrestricted modern camera image can
 * exhaust the app heap. This function therefore bakes the EXIF transform into the JPEG pixels and
 * bounds the decoded long edge. [forceJpegEncoding] is used for gallery imports because a picked
 * HEIC/PNG is first copied to a temporary file and must not be uploaded with JPEG file metadata
 * while retaining its original byte encoding.
 */
fun prepareAnalysisPhoto(
    source: File,
    forceJpegEncoding: Boolean = false,
): Result<File> = runCatching {
    val exif = ExifInterface(source)
    val rotation = exif.rotationDegrees
    val flipped = exif.isFlipped

    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(source.absolutePath, bounds)
    check(bounds.outWidth > 0 && bounds.outHeight > 0) { "captured_photo_unreadable" }
    val needsResize = max(bounds.outWidth, bounds.outHeight) > MAX_CAPTURE_LONG_EDGE
    if (rotation == 0 && !flipped && !needsResize && !forceJpegEncoding) {
        return@runCatching source
    }
    var sample = 1
    while (max(bounds.outWidth, bounds.outHeight) / sample > MAX_CAPTURE_LONG_EDGE) {
        sample *= 2
    }
    val original = checkNotNull(
        BitmapFactory.decodeFile(source.absolutePath, BitmapFactory.Options().apply { inSampleSize = sample }),
    ) { "captured_photo_unreadable" }

    val matrix = Matrix().apply {
        if (flipped) postScale(-1f, 1f)
        if (rotation != 0) postRotate(rotation.toFloat())
    }
    val oriented = Bitmap.createBitmap(original, 0, 0, original.width, original.height, matrix, true)
    val output = File.createTempFile("rd_capture_oriented_", ".jpg", source.parentFile)
    try {
        FileOutputStream(output).use { stream ->
            check(oriented.compress(Bitmap.CompressFormat.JPEG, 94, stream)) { "captured_photo_write_failed" }
        }
        ExifInterface(output).apply {
            setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL.toString())
            saveAttributes()
        }
        output
    } catch (t: Throwable) {
        output.delete()
        throw t
    } finally {
        if (oriented !== original) oriented.recycle()
        original.recycle()
    }
}

internal fun normalizeCapturedPhoto(source: File): Result<File> = prepareAnalysisPhoto(source)
