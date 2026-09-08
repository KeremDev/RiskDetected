package com.riskdetectedan.feature.capture

import android.graphics.Bitmap
import androidx.exifinterface.media.ExifInterface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
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
}
