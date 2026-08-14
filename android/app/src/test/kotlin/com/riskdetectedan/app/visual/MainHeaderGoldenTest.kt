package com.riskdetectedan.app.visual

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onRoot
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import com.riskdetectedan.app.home.AppMainHeader
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.data.profile.UserProfile
import com.riskdetectedan.core.designsystem.RiskDetectedTheme
import com.riskdetectedan.core.designsystem.RdTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(application = Application::class, sdk = [35], qualifiers = "w393dp-h116dp-xxhdpi")
class MainHeaderGoldenTest {
    @get:Rule val composeRule = createComposeRule()

    private val exactPixelOptions = RoborazziOptions(
        compareOptions = RoborazziOptions.CompareOptions(changeThreshold = 0f),
    )

    @Test
    fun analyses_header_free_targets_plus() = captureHeader(SubscriptionTier.Free)

    @Test
    fun reports_header_plus_targets_pro() = captureHeader(SubscriptionTier.Plus)

    private fun captureHeader(tier: SubscriptionTier) {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                Column(Modifier.fillMaxSize().background(RdTheme.colors.paper)) {
                    AppMainHeader(
                        profile = UserProfile(
                            id = "user-1",
                            fullName = "Ayşe Yılmaz",
                            initials = "AY",
                            tier = tier,
                        ),
                        onLogo = {},
                        onProfile = {},
                        onUpgradeTier = {},
                    )
                }
            }
        }
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }
}
