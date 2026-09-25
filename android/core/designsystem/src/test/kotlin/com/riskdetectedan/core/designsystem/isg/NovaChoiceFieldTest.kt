package com.riskdetectedan.core.designsystem.isg

import androidx.compose.runtime.*
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The bottom-sheet chooser every form selection field uses (iOS `testCompanyHazardClassIsChosenFromASheet`). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class NovaChoiceFieldTest {
    @get:Rule val compose = createComposeRule()

    private fun state(tag: String) = compose.onNodeWithTag(tag).fetchSemanticsNode().config[SemanticsProperties.StateDescription]

    @Test fun nothingIsChosenUntilTheUserPicksAndTheSheetClosesAfterAPick() {
        var hazard by mutableStateOf<String?>(null)
        compose.setContent {
            NovaTheme(false) {
                NovaChoiceField("Tehlike sınıfı *", NovaHazardChoice.placeholder, "exclamationmark.triangle", NovaHazardChoice.options,
                    hazard, { hazard = it }, "hazard", message = NovaHazardChoice.message)
            }
        }
        assertEquals("Tehlike sınıfı seçin", state("hazard"))
        compose.onNodeWithTag("hazard").performClick()
        compose.onNodeWithText(NovaHazardChoice.message).assertIsDisplayed()
        compose.onNodeWithTag("hazard.option.2").assertIsDisplayed().performClick()
        assertEquals("high", hazard)
        // The sheet lingers a beat so the tick is seen, then closes by itself.
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("hazard.option.2").fetchSemanticsNodes().isEmpty() }
        assertEquals("Çok Tehlikeli", state("hazard"))
    }

    @Test fun anOptionalFieldOffersItsNoneRowAndLongListsSearch() {
        var workplace by mutableStateOf<String?>("w3")
        val workplaces = (1..12).map { NovaChoiceOption("w$it", "İşyeri $it") }
        compose.setContent {
            NovaTheme(false) {
                NovaChoiceField("İşyeri", "İşyeri seçin", "building.2", workplaces, workplace, { workplace = it }, "workplace",
                    noneTitle = "Seçilmedi", boxed = true)
            }
        }
        assertEquals("İşyeri 3", state("workplace"))
        compose.onNodeWithTag("workplace").performClick()
        compose.onNodeWithTag("workplace.search").performTextInput("İşyeri 1")
        compose.waitForIdle()
        compose.onNodeWithTag("workplace.none").assertDoesNotExist()
        compose.onNodeWithTag("workplace.option.2").assertDoesNotExist()
        compose.onNodeWithTag("workplace.option.11").assertIsDisplayed()
        compose.onNodeWithTag("workplace.search").performTextClearance()
        compose.waitForIdle()
        compose.onNodeWithTag("workplace.none").assertIsDisplayed().performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("workplace.none").fetchSemanticsNodes().isEmpty() }
        assertNull(workplace)
        assertEquals("Seçilmedi", state("workplace"))
    }
}
