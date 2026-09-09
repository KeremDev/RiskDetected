package com.riskdetectedan.feature.capture

import android.graphics.Bitmap
import androidx.exifinterface.media.ExifInterface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.io.FileOutputStream

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CapturedPhotoOrientationTest {
    @Test
    fun `camera jpeg orientation is baked into output pixels`() {
        val source = File.createTempFile("camera_landscape_pixels", ".jpg")
        val bitmap = Bitmap.createBitmap(300, 200, Bitmap.Config.ARGB_8888)
        FileOutputStream(source).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 100, it) }
        ExifInterface(source).apply {
            setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_ROTATE_90.toString())
            saveAttributes()
        }

        val normalized = normalizeCapturedPhoto(source).getOrThrow()
        val output = android.graphics.BitmapFactory.decodeFile(normalized.absolutePath)

        assertEquals(200, output.width)
        assertEquals(300, output.height)
        assertEquals(ExifInterface.ORIENTATION_NORMAL, ExifInterface(normalized).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_UNDEFINED,
        ))
        assertNotEquals(source.absolutePath, normalized.absolutePath)
    }

    @Test
    fun `oversized photo is bounded before analysis`() {
        val source = File.createTempFile("oversized_photo", ".jpg")
        val bitmap = Bitmap.createBitmap(2_600, 1_300, Bitmap.Config.ARGB_8888)
        FileOutputStream(source).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 95, it) }
        bitmap.recycle()

        val prepared = prepareAnalysisPhoto(source).getOrThrow()
        val output = android.graphics.BitmapFactory.decodeFile(prepared.absolutePath)

        assertTrue(maxOf(output.width, output.height) <= 2_400)
        assertNotEquals(source.absolutePath, prepared.absolutePath)
        output.recycle()
    }

    @Test
    fun `gallery source is rewritten as jpeg even without exif transform`() {
        val source = File.createTempFile("gallery_png", ".bin")
        val bitmap = Bitmap.createBitmap(300, 500, Bitmap.Config.ARGB_8888)
        FileOutputStream(source).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()

        val prepared = prepareAnalysisPhoto(source, forceJpegEncoding = true).getOrThrow()
        val signature = prepared.inputStream().use { input -> ByteArray(2).also { input.read(it) } }
        val output = android.graphics.BitmapFactory.decodeFile(prepared.absolutePath)

        assertEquals(0xFF.toByte(), signature[0])
        assertEquals(0xD8.toByte(), signature[1])
        assertEquals(300, output.width)
        assertEquals(500, output.height)
        output.recycle()
    }
}
