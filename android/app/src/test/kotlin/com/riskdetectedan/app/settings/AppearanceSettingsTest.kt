package com.riskdetectedan.app.settings

import android.app.Application
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import com.github.takahirom.roborazzi.captureRoboImage
import com.riskdetectedan.core.designsystem.RiskDetectedTheme
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(application = Application::class, sdk = [35], qualifiers = "w393dp-h852dp-xxhdpi")
class AppearanceSettingsTest {

    @get:Rule
    val composeRule = createComposeRule()

    private val context: Context = ApplicationProvider.getApplicationContext()

    @Before
    fun clearPreference() {
        context.getSharedPreferences("appearance", Context.MODE_PRIVATE).edit().clear().commit()
    }

    @Test
    fun selection_changes_immediately_even_when_app_is_forced_dark() {
        var selected by mutableStateOf(AppearanceMode.Dark)
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = true) {
                AppearanceSettingsContent(
                    selected = selected,
                    onSelect = { selected = it },
                    onBack = {},
                )
            }
        }

        composeRule.onNodeWithText("Karanlık").assertIsSelected()
        composeRule.onNodeWithText("Aydınlık").performClick()
        composeRule.onNodeWithText("Aydınlık").assertIsSelected()
        assertEquals(AppearanceMode.Light, selected)
    }

    @Test
    fun appearance_preferences_light() {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                AppearanceSettingsContent(
                    selected = AppearanceMode.System,
                    onSelect = {},
                    onBack = {},
                )
            }
        }

        composeRule.onNodeWithText("Sistem").assertIsSelected()
        composeRule.onRoot().captureRoboImage()
    }

    @Test
    fun appearance_preferences_dark() {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = true) {
                AppearanceSettingsContent(
                    selected = AppearanceMode.Dark,
                    onSelect = {},
                    onBack = {},
                )
            }
        }

        composeRule.onNodeWithText("Karanlık").assertIsSelected()
        composeRule.onRoot().captureRoboImage()
    }

    @Test
    fun preference_survives_repository_recreation() {
        AppearancePreferences(context).set(AppearanceMode.Dark)

        assertEquals(AppearanceMode.Dark, AppearancePreferences(context).mode.value)
    }
}
