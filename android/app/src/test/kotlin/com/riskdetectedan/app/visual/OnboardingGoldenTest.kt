package com.riskdetectedan.app.visual

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onRoot
import com.github.takahirom.roborazzi.captureRoboImage
import com.github.takahirom.roborazzi.RoborazziOptions
import com.riskdetectedan.core.data.onboarding.OnboardingCertificate
import com.riskdetectedan.core.data.onboarding.OnboardingFrequency
import com.riskdetectedan.core.data.onboarding.OnboardingHazardClass
import com.riskdetectedan.core.data.onboarding.OnboardingSector
import com.riskdetectedan.core.designsystem.RiskDetectedTheme
import com.riskdetectedan.core.designsystem.RiskDetectedLightOnlyTheme
import com.riskdetectedan.feature.onboarding.OBCertificateScreen
import com.riskdetectedan.feature.onboarding.OBFrequencyScreen
import com.riskdetectedan.feature.onboarding.OBHazardClassScreen
import com.riskdetectedan.feature.onboarding.OBLoadingScreen
import com.riskdetectedan.feature.onboarding.OBNotificationPermissionScreen
import com.riskdetectedan.feature.onboarding.OBPainPointScreen
import com.riskdetectedan.feature.onboarding.OBSectorScreen
import com.riskdetectedan.feature.onboarding.OBSplashScreen
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w393dp-h852dp-xxhdpi")
class OnboardingGoldenTest {

    @get:Rule
    val composeRule = createComposeRule()

    private val exactPixelOptions = RoborazziOptions(
        compareOptions = RoborazziOptions.CompareOptions(changeThreshold = 0f),
    )

    @Test
    fun splash_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                OBSplashScreen(onNext = {}, onSkip = {})
            }
        }

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun pain_point_checks_completed_light() {
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                OBPainPointScreen(onNext = {})
            }
        }
        composeRule.mainClock.advanceTimeBy(2_100L)

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun certificate_empty_light() {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                OBCertificateScreen(
                    selected = null,
                    onSelect = {},
                    onNext = {},
                    onBack = {},
                )
            }
        }

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun hazard_multi_selected_light() {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                OBHazardClassScreen(
                    selected = setOf(OnboardingHazardClass.Critical, OnboardingHazardClass.High),
                    onToggle = {},
                    onNext = {},
                    onBack = {},
                )
            }
        }

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun sector_grid_selected_light() {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                OBSectorScreen(
                    selected = listOf(OnboardingSector.Construction, OnboardingSector.Manufacturing),
                    onToggle = {},
                    onNext = {},
                    onBack = {},
                )
            }
        }

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun frequency_selected_system_dark_stays_light() {
        composeRule.setContent {
            // Mirrors the app route: the outer app theme may be dark, but live iOS pins the
            // onboarding/auth/paywall product surfaces to light mode.
            RiskDetectedTheme(darkTheme = true) {
                RiskDetectedLightOnlyTheme {
                    OBFrequencyScreen(
                        selected = OnboardingFrequency.TwoToFive,
                        onSelect = {},
                        onNext = {},
                        onBack = {},
                    )
                }
            }
        }

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun loading_second_step_light() {
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                OBLoadingScreen(
                    onFinished = {},
                    primarySectorLabel = "İnşaat",
                    hazardsLabel = "Çok Tehlikeli · Tehlikeli",
                    certificateLabel = "A Sınıfı",
                )
            }
        }
        composeRule.mainClock.advanceTimeBy(1_850L)

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun notification_permission_light() {
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                OBNotificationPermissionScreen(onContinue = {})
            }
        }

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }
}
