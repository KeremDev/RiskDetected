package com.riskdetectedan.app.visual

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onRoot
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import com.riskdetectedan.app.home.CanvasSheet
import com.riskdetectedan.core.data.analysis.AnalysisCanvas
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.RiskDetectedTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(application = Application::class, sdk = [35], qualifiers = "tr-rTR-w393dp-h382dp-xxhdpi")
class CanvasSheetGoldenTest {
    @get:Rule val composeRule = createComposeRule()

    private val exactPixelOptions = RoborazziOptions(
        compareOptions = RoborazziOptions.CompareOptions(changeThreshold = 0f),
    )

    @Test
    fun free_user_sees_distinct_plus_and_pro_canvas_identities() {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                Box(Modifier.fillMaxSize().background(RdTheme.colors.paper)) {
                    CanvasSheet(
                        selected = setOf(AnalysisCanvas.warningSigns),
                        onSelectedChange = {},
                        userTier = SubscriptionTier.Free,
                        onConfirm = {},
                        onDismiss = {},
                        onUpgradeRequested = {},
                    )
                }
            }
        }

        composeRule.onAllNodesWithText("PLUS").assertCountEquals(2)
        composeRule.onAllNodesWithText("PRO").assertCountEquals(2)
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }
}
