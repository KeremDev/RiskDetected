package com.riskdetectedan.app.home

import android.app.Application
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import com.riskdetectedan.core.designsystem.RiskDetectedTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(application = Application::class, sdk = [35], qualifiers = "tr-rTR-w393dp-h852dp-xxhdpi")
class PhotoUploadCardTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun paid_photo_card_displays_three_photo_capacity() {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                PhotoUploadCard(
                    photoPaths = emptyList(),
                    maxPhotoCount = 3,
                    onOpenTray = {},
                    onRemove = {},
                )
            }
        }

        composeRule.onNodeWithText("0/3").assertIsDisplayed()
    }

    @Test
    fun free_photo_card_displays_single_photo_capacity() {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                PhotoUploadCard(
                    photoPaths = emptyList(),
                    maxPhotoCount = 1,
                    onOpenTray = {},
                    onRemove = {},
                )
            }
        }

        composeRule.onNodeWithText("0/1").assertIsDisplayed()
    }
}
