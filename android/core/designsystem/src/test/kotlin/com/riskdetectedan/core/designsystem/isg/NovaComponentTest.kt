package com.riskdetectedan.core.designsystem.isg

import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.unit.Density
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Host JVM/Compose behavior checks, not emulator or screenshot-golden evidence. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], qualifiers = "w320dp-h692dp-mdpi")
class NovaComponentTest {
    @get:Rule val compose = createComposeRule()

    private fun checkButtonMatrix(dark: Boolean) {
        var variant by mutableStateOf(NovaButtonVariant.Primary)
        var enabled by mutableStateOf(true)
        var loading by mutableStateOf(false)
        var calls = 0
        compose.setContent {
            NovaTheme(dark) {
                NovaButton("Eylem", { calls++ }, variant = variant, enabled = enabled, loading = loading)
            }
        }
        for (v in NovaButtonVariant.entries) {
            for ((e, l) in listOf(true to false, false to false, true to true)) {
                compose.runOnIdle { variant = v; enabled = e; loading = l; calls = 0 }
                val node = compose.onNodeWithText("Eylem").assertIsDisplayed()
                if (e && !l) node.assertIsEnabled() else node.assertIsNotEnabled()
                node.performTouchInput { click() }
                compose.runOnIdle { assertEquals("$v enabled=$e loading=$l", if (e && !l) 1 else 0, calls) }
            }
        }
    }

    @Test fun lightButtonVariantsAndDisabledLoadingBehavior() = checkButtonMatrix(false)
    @Test fun darkButtonVariantsAndDisabledLoadingBehavior() = checkButtonMatrix(true)

    @Test fun largeTextGalleryRemainsScrollableAndInteractive() {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, fontScale = 2f)) {
                NovaTheme(false) { NovaComponentGallery() }
            }
        }
        compose.onNodeWithContentDescription("İşlem tamamlandı").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Örnek eylem (0)").performScrollTo().performClick()
        compose.onNodeWithText("Örnek eylem (1)").assertIsDisplayed()
        compose.onNodeWithText("İşlem sürüyor").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("Kullanılamıyor").performScrollTo().assertIsNotEnabled()
    }
}
