package com.riskdetectedan.feature.nova

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.riskdetectedan.core.data.nova.NovaForYouCard
import com.riskdetectedan.core.data.nova.NovaForYouFeed
import com.riskdetectedan.core.designsystem.isg.LocalNovaReduceMotion
import com.riskdetectedan.core.designsystem.isg.NovaTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** "Senin İçin" on screen (iOS `testForYouRotatesSuggestionsAboveAttentionAndProgress`): the screen of 25.09.2026. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class NovaForYouSectionTest {
    @get:Rule val compose = createComposeRule()

    private fun card(id: String, kind: String, tone: String, route: String, dismissible: Boolean = true,
                     params: NovaForYouCard.Params = NovaForYouCard.Params()) =
        NovaForYouCard(id, id.substringBefore(':'), kind, tone, dismissible, params, NovaForYouCard.Target(route))

    private val feed = NovaForYouFeed(1, "personal", "growing",
        cards = listOf(
            card("critical.expired", "critical", "danger", "followup", false, NovaForYouCard.Params(count = 1, companyName = "Deneme Firması")),
            card("continue.company_create:review", "continue", "brand", "company_create"),
            card("continue.checklist_open:review", "continue", "brand", "checklist_run", params = NovaForYouCard.Params(title = "Saha turu")),
        ),
        more = listOf(
            card("performance.analyses_30d", "performance", "success", "analyses", params = NovaForYouCard.Params(count = 12)),
            card("discover.risk_wizard", "discover", "feature", "risk_wizard"),
            card("discover.followup", "discover", "feature", "followup"),
            card("discover.statistics", "discover", "feature", "statistics"),
            card("motivation.today_analysis", "motivation", "brand", "photo_analysis"),
        ))

    private val shown = mutableListOf<String>()

    private fun show(reduceMotion: Boolean = false, continueId: String? = null) {
        compose.mainClock.autoAdvance = false
        compose.setContent {
            NovaTheme(false) {
                CompositionLocalProvider(LocalNovaReduceMotion provides reduceMotion) {
                    NovaForYouSection(NovaForYouPhase.Ready(feed), onOpen = {}, onDismiss = {}, onRetry = {},
                        onShown = { cards -> shown += cards.map { it.id } }, continueId = continueId)
                }
            }
        }
        compose.mainClock.advanceTimeBy(100)
    }

    private fun featured(key: String) = compose.onNodeWithTag("nova.home.foryou.featured.discover.$key")

    @Test fun suggestionsRotateAboveAttentionAndProgress() {
        show()
        featured("risk_wizard").assertIsDisplayed()
        compose.onNodeWithTag("nova.home.foryou.card.critical.expired").assertIsDisplayed()
        compose.onNodeWithTag("nova.home.foryou.card.continue.company_create").assertIsDisplayed()
        compose.onNodeWithTag("nova.home.foryou.strip.performance.analyses_30d").assertIsDisplayed()
        compose.onAllNodes(hasTestTagPrefix("nova.home.foryou.card.")).assertCountEquals(2)
        compose.onNodeWithTag("nova.home.foryou.place", useUnmergedTree = true).assertTextEquals("1/2")
        assertTrue(shown.containsAll(listOf("discover.risk_wizard", "performance.analyses_30d", "critical.expired", "continue.company_create:review")))

        compose.mainClock.advanceTimeBy(6_000)
        featured("followup").assertIsDisplayed()
        featured("risk_wizard").assertDoesNotExist()
        assertTrue("the card that came into view is reported", "discover.followup" in shown)

        featured("followup").performTouchInput { swipeLeft() }
        compose.mainClock.advanceTimeBy(1_000)
        featured("statistics").assertIsDisplayed()

        compose.mainClock.advanceTimeBy(6_000)
        featured("risk_wizard").assertIsDisplayed()
    }

    @Test fun theVisitsUnfinishedItemTakesTheBox() {
        show(continueId = "continue.checklist_open:review")
        compose.onNodeWithTag("nova.home.foryou.card.continue.checklist_open").assertIsDisplayed()
        compose.onNodeWithTag("nova.home.foryou.card.continue.company_create").assertDoesNotExist()
        compose.onNodeWithTag("nova.home.foryou.place", useUnmergedTree = true).assertTextEquals("2/2")
    }

    @Test fun staysPutWithAnimationsRemoved() {
        show(reduceMotion = true)
        compose.mainClock.advanceTimeBy(12_000)
        featured("risk_wizard").assertIsDisplayed()
        featured("risk_wizard").performTouchInput { swipeLeft() }
        compose.mainClock.advanceTimeBy(1_000)
        featured("followup").assertIsDisplayed()
    }

    private fun hasTestTagPrefix(prefix: String) = SemanticsMatcher("testTag starts with $prefix") {
        it.config.getOrElseNullable(androidx.compose.ui.semantics.SemanticsProperties.TestTag) { null }?.startsWith(prefix) == true
    }
}
