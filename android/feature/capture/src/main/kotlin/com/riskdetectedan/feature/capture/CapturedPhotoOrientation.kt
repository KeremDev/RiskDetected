package com.riskdetectedan.feature.capture

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.io.FileOutputStream
import kotlin.math.ceil
import kotlin.math.max

private const val MAX_CAPTURE_LONG_EDGE = 2400

/**
 * Bakes CameraX's EXIF transform into JPEG pixels before preview, annotation and upload.
 * BitmapFactory ignores EXIF orientation; without this step a portrait camera photo was flattened
 * as landscape by AnnotateScreen and the cropped landscape pixels reached the analysis backend.
 */
internal fun normalizeCapturedPhoto(source: File): Result<File> = runCatching {
    val exif = ExifInterface(source)
    val rotation = exif.rotationDegrees
    val flipped = exif.isFlipped
    if (rotation == 0 && !flipped) return@runCatching source

    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(source.absolutePath, bounds)
    check(bounds.outWidth > 0 && bounds.outHeight > 0) { "captured_photo_unreadable" }
    val sample = max(1, ceil(max(bounds.outWidth, bounds.outHeight) / MAX_CAPTURE_LONG_EDGE.toFloat()).toInt())
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
