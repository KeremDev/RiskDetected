package com.riskdetectedan.app.home

import com.riskdetectedan.core.designsystem.R as RdR

import android.os.ParcelFileDescriptor
import androidx.activity.ComponentActivity
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.SheetValue
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.AnalysisSectorBadge
import com.riskdetectedan.core.data.analysis.AnalysisSectorPickerItem
import com.riskdetectedan.core.data.onboarding.OnboardingSector
import com.riskdetectedan.core.designsystem.RiskDetectedLightOnlyTheme
import com.riskdetectedan.feature.onboarding.OBSectorScreen
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Real Android-renderer coverage for the three iOS parity regressions reported on 2026-08-30. */
@RunWith(AndroidJUnit4::class)
@OptIn(ExperimentalMaterial3Api::class)
class HomeParityOnDeviceTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun sectorPickerEntersExpandedWithContinueVisible() {
        var observedSheetState: SheetState? = null
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val title = context.getString(RdR.string.rd_analiz_kapsamini_sec)
        val continueLabel = context.getString(RdR.string.rd_devam_et)
        val items = AnalysisSector.entries.map { sector ->
            AnalysisSectorPickerItem(
                sector = sector,
                badges = when (sector) {
                    AnalysisSector.Construction -> setOf(AnalysisSectorBadge.Recommended)
                    AnalysisSector.Manufacturing -> setOf(AnalysisSectorBadge.LastUsed)
                    else -> emptySet()
                },
            )
        }

        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
                observedSheetState = state
                ModalBottomSheet(
                    onDismissRequest = {},
                    sheetState = state,
                ) {
                    SectorPickerSheet(items = items, onSelect = {})
                }
            }
        }

        composeRule.waitUntil(timeoutMillis = 5_000) {
            observedSheetState?.currentValue == SheetValue.Expanded
        }
        assertEquals(SheetValue.Expanded, observedSheetState?.currentValue)
        composeRule.onNodeWithText(title).assertIsDisplayed()
        composeRule.onNodeWithText(continueLabel).assertIsDisplayed()
        capture("sector_picker_initial_expanded")
    }

    @Test
    fun onboardingSectorSubtitlesStayVisibleAtLargeFontScale() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val constructionSubtitle = context.getString(RdR.string.rd_sector_construction_subtitle)
        val manufacturingSubtitle = context.getString(RdR.string.rd_sector_manufacturing_subtitle)
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 1.3f)) {
                    OBSectorScreen(
                        selected = emptyList(),
                        onToggle = {},
                        onNext = {},
                        onBack = {},
                    )
                }
            }
        }

        // Tile click semantics merge descendants in the accessibility tree; use the unmerged
        // tree to verify the actual subtitle text nodes remain inside the rendered cards.
        composeRule.onNodeWithText(constructionSubtitle, useUnmergedTree = true).assertIsDisplayed()
        composeRule.onNodeWithText(manufacturingSubtitle, useUnmergedTree = true).assertIsDisplayed()
        capture("onboarding_sector_font_scale_1_3")
    }

    private fun capture(name: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        ParcelFileDescriptor.AutoCloseInputStream(
            instrumentation.uiAutomation.executeShellCommand(
                "screencap -p /sdcard/Download/$name.png",
            ),
        ).use { commandOutput -> commandOutput.readBytes() }
    }
}
