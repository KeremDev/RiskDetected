package com.riskdetectedan.core.designsystem.isg

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], qualifiers = "w440dp-h956dp-mdpi")
class NovaScreensTest {
    @get:Rule val compose = createComposeRule()
    private val companies = listOf(NovaCompanyItem("one", "İstanbul İş Güvenliği", "Kaymaz · Çok tehlikeli"), NovaCompanyItem("two", "Işık Maden", "Ankara"))

    @Test fun photoAndCreateFindingHaveIndependentActions() {
        var photos = 0
        var route: NovaDestination? = null
        compose.setContent { NovaTheme(false) {
            NovaDashboardScreen(NovaDashboardData("Kerem", 0, emptyList(), null, "Uyarı yok"),
                onNavigate = { route = it }, onPhoto = { photos++ })
        } }
        compose.onNodeWithTag("nova.home.photo").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(1, photos); assertNull(route) }
        compose.onNodeWithTag("nova.home.addFinding").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(1, photos); assertEquals(NovaDestination.newFinding, route) }
    }

    @Test fun turkishSearchCoversDottedAndDotlessIAndMetadata() {
        assertEquals(listOf(companies[0]), filterNovaCompanies(companies, "İSTANBUL"))
        assertEquals(listOf(companies[1]), filterNovaCompanies(companies, "ışık"))
        assertEquals(listOf(companies[0]), filterNovaCompanies(companies, "tehlikeli"))
        assertEquals(companies, filterNovaCompanies(companies, "  "))
        assertTrue(filterNovaCompanies(companies, "bulunmayan").isEmpty())
        assertEquals("KK", novaInitials(" Kerem  Kaya "))
    }

    @Test fun companySearchClearSelectAndBack() {
        var selected: String? = null
        var backs = 0
        compose.setContent { NovaTheme(false) { NovaCompaniesScreen(companies, onSelect = { selected = it }, onBack = { backs++ }, onRetry = {}) } }
        compose.onNodeWithTag("nova.companies.search").performTextInput("bulunmayan")
        compose.onNodeWithText("Firma bulunamadı").assertIsDisplayed()
        compose.onNodeWithTag("nova.company.one").assertDoesNotExist()
        compose.onNodeWithTag("nova.companies.clear").performClick()
        compose.onNodeWithTag("nova.company.two").performClick()
        compose.runOnIdle { assertEquals("two", selected) }
        compose.onNodeWithTag("nova.back").performClick()
        compose.runOnIdle { assertEquals(1, backs) }
    }

    @Test fun notificationPopupActionsPreserveRouteUntilCenterChosen() {
        var state by mutableStateOf(NovaNavigationState("a", NovaDestination.entries.toSet()))
        var notices by mutableStateOf(listOf(NovaNotice("overdue", "Termini geçen aksiyonlar", "Geciken düzeltmeleri inceleyin.", "1 gün gecikti", "exclamationmark.triangle", NovaColorToken.statusDangerInk)))
        compose.setContent { NovaTheme(false) {
            NovaExpertShell(state, "Kerem Kaya", onEvent = { event, epoch -> state = state.apply(event, epoch) }, notices = notices,
                actions = NovaShellActions(onReadAll = { notices = notices.map { it.copy(unread = false) } },
                    onClearNotifications = { notices = emptyList() })) { NovaText("content:${it.name}") }
        } }
        compose.onNodeWithTag("nova.notifications").performClick()
        compose.runOnIdle { assertEquals(NovaDestination.home, state.current); assertEquals(NovaOverlay.notifications, state.overlay) }
        compose.onNodeWithTag("nova.notices.read").performClick()
        compose.runOnIdle { assertFalse(notices.single().unread) }
        compose.onNodeWithTag("nova.notices.clear").performClick()
        compose.onNodeWithText("Yeni bildirim yok").assertIsDisplayed()
        compose.onNodeWithTag("nova.notices.center").performClick()
        compose.onNodeWithText("content:notifications").assertIsDisplayed()
    }

    @Test fun companyErrorRetriesAndDoesNotDisplayStaleRows() {
        var retries = 0
        compose.setContent { NovaTheme(false) { NovaCompaniesScreen(companies, error = "Bağlantı kesildi", onSelect = {}, onBack = {}, onRetry = { retries++ }) } }
        compose.onNodeWithTag("nova.company.one").assertDoesNotExist()
        compose.onNodeWithText("Tekrar dene").performClick()
        compose.runOnIdle { assertEquals(1, retries) }
    }
}
