package com.riskdetectedan.core.designsystem.isg

import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Native Compose interaction in host JVM; not emulator, TalkBack or live domain E2E. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], qualifiers = "w320dp-h692dp-mdpi")
class NovaShellTest {
    @get:Rule val compose = createComposeRule()
    private var state by mutableStateOf(NovaNavigationState("a", NovaDestination.entries.toSet()))
    private fun mount(dark: Boolean = false, scale: Float = 1f) {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, fontScale = scale)) {
                NovaTheme(dark) {
                    NovaExpertShell(state, "Örnek Uzman", onEvent = { event, epoch -> state = state.apply(event, epoch) }) {
                        NovaText("content:${it.name}")
                    }
                }
            }
        }
    }
    @Test fun quickAddPreservesTabAndRoutesOnlyWhenChosen() {
        mount()
        compose.onNodeWithTag("nova.tab.companies").performClick().assertIsSelected()
        compose.onNodeWithTag("nova.add").performClick()
        compose.runOnIdle { assertEquals(NovaTab.companies, state.selected); assertEquals(NovaOverlay.quickAdd, state.overlay) }
        compose.onNodeWithTag("nova.panel.close").performClick()
        compose.onNodeWithTag("nova.tab.companies").assertIsSelected()
        compose.onNodeWithTag("nova.add").performClick()
        compose.onNodeWithTag("nova.destination.newFinding").performScrollTo().performClick()
        compose.onNodeWithText("content:newFinding").assertIsDisplayed()
        compose.onNodeWithTag("nova.tab.findings").assertIsSelected()
        compose.onNodeWithTag("nova.back").performClick()
        compose.onNodeWithText("content:findings").assertIsDisplayed()
    }
    @Test fun everyTabSelectionAndReselectionWorksInDarkTheme() {
        mount(dark = true)
        NovaTab.entries.forEach { tab ->
            compose.onNodeWithTag("nova.tab.${tab.name}").performClick().assertIsSelected()
            compose.onNodeWithText("content:${tab.name}").assertIsDisplayed()
        }
        compose.onNodeWithTag("nova.notifications").performClick()
        compose.onNodeWithText("content:notifications").assertIsDisplayed()
        compose.onNodeWithTag("nova.tab.profile").performClick()
        compose.onNodeWithTag("nova.tab.home").performClick()
        compose.onNodeWithText("content:notifications").assertIsDisplayed()
        compose.onNodeWithTag("nova.tab.home").performClick()
        compose.onNodeWithText("content:home").assertIsDisplayed()
    }
    @Test fun lockedRoutesAndNotificationsAreNotInteractive() {
        state = NovaNavigationState("a", emptySet())
        mount()
        compose.onNodeWithTag("nova.tab.findings").assertIsNotEnabled().performTouchInput { click() }
        compose.onNodeWithTag("nova.notifications").assertIsNotEnabled().performTouchInput { click() }
        compose.onNodeWithTag("nova.add").performClick()
        NovaDestination.quickAdd.forEach {
            compose.onNodeWithTag("nova.destination.${it.name}").performScrollTo().assertIsNotEnabled().performTouchInput { click() }
            compose.runOnIdle { assertEquals(NovaDestination.home, state.current); assertEquals(NovaOverlay.quickAdd, state.overlay) }
        }
        compose.onNodeWithTag("nova.panel.close").assertIsDisplayed().performClick()
    }
    @Test fun drawerScrollAndCloseRemainAvailableAtDoubleFontScale() {
        mount(scale = 2f)
        compose.onNodeWithTag("nova.menu").performClick()
        NovaDestination.drawer.forEach {
            compose.onNodeWithTag("nova.destination.${it.name}").performScrollTo().assertIsDisplayed()
            compose.onNodeWithTag("nova.panel.close").assertIsDisplayed()
        }
        compose.onNodeWithTag("nova.destination.notifications").performClick()
        compose.onNodeWithText("content:notifications").assertIsDisplayed()
    }
    @Test fun accountResetClearsPanelContentAndOldCallbackCannotReopenIt() {
        mount()
        compose.onNodeWithTag("nova.notifications").performClick()
        compose.onNodeWithTag("nova.add").performClick()
        // Mirrors captured UI event delivery into the latest host state, not an old snapshot.
        val oldCallback = { state = state.apply(NovaNavigationEvent.Navigate(NovaDestination.notifications), "a") }
        compose.runOnIdle { state = state.resetAccount("b", emptySet()) }
        compose.onNodeWithTag("nova.panel.close").assertDoesNotExist()
        compose.onNodeWithText("content:home").assertIsDisplayed()
        compose.runOnIdle { oldCallback(); assertEquals("b", state.epoch); assertEquals(NovaDestination.home, state.current) }
        compose.onNodeWithText("content:notifications").assertDoesNotExist()
    }
    @Test fun doubleFontScaleTabsScrollToEveryActionAndAutoRevealSelection() {
        mount(scale = 2f)
        listOf(0 to NovaTab.home, 1 to NovaTab.findings, 3 to NovaTab.companies, 4 to NovaTab.profile).forEach { (index, tab) ->
            compose.onNodeWithTag("nova.tabs.scroll").performScrollToIndex(index)
            compose.onNodeWithTag("nova.tab.${tab.name}").assertIsDisplayed().performClick().assertIsSelected()
            compose.onNodeWithText("content:${tab.name}").assertIsDisplayed()
        }
        compose.onNodeWithTag("nova.tabs.scroll").performScrollToIndex(2)
        compose.onNodeWithTag("nova.add").performClick()
        compose.onNodeWithTag("nova.destination.newFinding").performScrollTo().performClick()
        compose.onNodeWithTag("nova.tab.findings").assertIsDisplayed().assertIsSelected()
    }
    private fun checkEveryMenuEntry(dark: Boolean) {
        mount(dark = dark)
        for ((panel, destinations) in listOf(NovaOverlay.drawer to NovaDestination.drawer, NovaOverlay.quickAdd to NovaDestination.quickAdd)) {
            destinations.forEach { destination ->
                // Two explicit taps also return to home root if this tab retained a path.
                compose.onNodeWithTag("nova.tab.home").performClick().performClick()
                compose.onNodeWithTag(if (panel == NovaOverlay.drawer) "nova.menu" else "nova.add").performClick()
                compose.onNodeWithTag("nova.destination.${destination.name}").performScrollTo().performClick()
                compose.onNodeWithText("content:${destination.name}").assertIsDisplayed()
                compose.onNodeWithTag("nova.panel.close").assertDoesNotExist()
                compose.onNodeWithTag("nova.tab.${destination.tab.name}").assertIsSelected()
            }
        }
    }
    @Test fun everyDrawerAndQuickAddEntryRoutesInLightTheme() = checkEveryMenuEntry(false)
    @Test fun everyDrawerAndQuickAddEntryRoutesInDarkTheme() = checkEveryMenuEntry(true)
    @Test fun shellControlsMeet48DpTargetsAtCompactWidth() {
        mount()
        for (tag in listOf("nova.menu", "nova.notifications", "nova.profile", "nova.tab.home", "nova.tab.findings", "nova.add", "nova.tab.companies", "nova.tab.profile")) {
            compose.onNodeWithTag(tag).assertWidthIsAtLeast(48.dp).assertHeightIsAtLeast(48.dp)
        }
        compose.onNodeWithTag("nova.menu").performClick()
        compose.onNodeWithTag("nova.panel.close").assertWidthIsAtLeast(48.dp).assertHeightIsAtLeast(48.dp).performClick()
        compose.onNodeWithTag("nova.add").performClick()
        compose.onNodeWithTag("nova.panel.close").assertWidthIsAtLeast(48.dp).assertHeightIsAtLeast(48.dp)
    }
}
