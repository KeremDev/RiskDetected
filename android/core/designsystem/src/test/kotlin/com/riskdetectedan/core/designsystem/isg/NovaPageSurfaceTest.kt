package com.riskdetectedan.core.designsystem.isg

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.inspector.WindowInspector
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.unit.dp
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/** Native Skia/JVM regression; not emulator, production form or live-service evidence. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], qualifiers = "w440dp-h956dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class NovaPageSurfaceTest {
    @get:Rule val compose = createComposeRule()
    @Test fun allDestinationsKeepLightCanvasAndSeparateWhiteCards() = verify(dark = false)
    @Test fun allDestinationsKeepDarkCanvasAndSeparateCards() = verify(dark = true)

    private fun verify(dark: Boolean) {
        var state by mutableStateOf(NovaNavigationState("page-fixture", NovaDestination.entries.toSet()))
        compose.setContent { NovaTheme(dark) {
            NovaExpertShell(state, "Test Kullanıcısı", onEvent = { event, epoch -> state = state.apply(event, epoch) }) { destination ->
                Column(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    NovaPageTitle(destination)
                    NovaCard(Modifier.fillMaxWidth().testTag("page.card"), padding = 20) {
                        NovaText("Sentetik test ekranı. Canlı veri veya işlem yok.", style = NovaTypeToken.meta)
                    }
                }
            }
        } }
        for (route in NovaDestination.entries) {
            compose.runOnIdle { state = state.navigate(route, state.epoch) }
            compose.onNodeWithTag("page.card").assertIsDisplayed()
            val card = compose.onNodeWithTag("page.card").fetchSemanticsNode().boundsInRoot
            val bitmap = compose.runOnIdle {
                val view = WindowInspector.getGlobalWindowViews().first { it.width > 0 && it.height > 0 }
                Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888).also { view.draw(Canvas(it)) }
            }
            val canvas = NovaColorToken.canvas.rgba(dark)
            val surface = NovaColorToken.surface.rgba(dark)
            fun assertColor(x: Int, y: Int, expected: NovaRGBA, label: String) {
                val pixel = bitmap.getPixel(x, y)
                assertEquals("${route.name} $label", android.graphics.Color.rgb(expected.red, expected.green, expected.blue), pixel)
            }
            for (y in listOf(200, 350, 500, 650)) assertColor(3, y, canvas, "continuous canvas")
            // The white card has a broad text-free interior below its text and above its bottom edge.
            // Find a solid surface run on the center line; status bar/header backgrounds cannot satisfy it.
            val expected = android.graphics.Color.rgb(surface.red, surface.green, surface.blue)
            assertTrue("${route.name} separate card pixels", (card.top.toInt()..(card.bottom.toInt() + 32))
                .count { y -> bitmap.getPixel(bitmap.width / 2, y) == expected } >= 10)
            if (route == NovaDestination.newVisit) {
                val file = File("build/reports/nova-page-surfaces/newVisit-${if (dark) "dark" else "light"}.png")
                requireNotNull(file.parentFile).mkdirs()
                file.outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
            }
            bitmap.recycle()
        }
    }
}
