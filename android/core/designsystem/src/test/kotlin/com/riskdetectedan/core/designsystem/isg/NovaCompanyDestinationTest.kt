package com.riskdetectedan.core.designsystem.isg

import androidx.compose.runtime.*
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class NovaCompanyDestinationTest {
    @get:Rule val compose = createComposeRule()
    private val a = UUID.fromString("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    private val b = UUID.fromString("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
    private val id = UUID.fromString("11111111-1111-4111-8111-111111111111")
    private fun ready(owner: UUID): NovaSessionHost {
        val host = NovaSessionHost(setOf(NovaDestination.companies)).adopt(NovaSessionIdentity(owner, UUID.randomUUID())).beginAvailabilityRefresh()
        return host.resolve(requireNotNull(host.pending), owner, setOf(NovaDestination.companies))
    }
    private fun row(owner: UUID) = NovaOwnedCompany(id, owner, if (owner == a) "Firma A" else "Firma B", "Sentetik adres", false)

    @Test fun loadsOwnedRowsAndSelectsCurrentId() {
        val host = ready(a)
        var selected: UUID? = null
        compose.setContent { NovaTheme(false) { NovaCompanyDestination(host, { listOf(row(a)) }, onSelect = { selected = it }, onBack = {}) } }
        compose.onNodeWithText("Firma A").assertIsDisplayed()
        compose.onNodeWithText("1 firma").assertIsDisplayed()
        compose.onNodeWithTag("nova.company.$id").performClick()
        compose.runOnIdle { assertEquals(id, selected) }
    }
    @Test fun retryUsesGenericErrorAndNewRequest() {
        val host = ready(a)
        var calls = 0
        compose.setContent { NovaTheme(false) { NovaCompanyDestination(host, {
            calls++
            if (calls == 1) error("synthetic-private-body")
            listOf(row(a))
        }, onSelect = {}, onBack = {}) } }
        compose.onNodeWithText("synthetic-private-body").assertDoesNotExist()
        compose.onNodeWithText("Tekrar dene").performClick()
        compose.onNodeWithText("Firma A").assertIsDisplayed()
        compose.runOnIdle { assertEquals(2, calls) }
    }
    @Test fun previousAccountResponseCannotReplaceNewAccountEvenIfProviderIgnoresCancellation() {
        var host by mutableStateOf(ready(a))
        val delayed = CompletableDeferred<List<NovaOwnedCompany>>()
        var firstStarted = false
        compose.setContent {
            val owner = requireNotNull(host.identity).userID
            NovaTheme(false) { NovaCompanyDestination(host, {
                if (owner == a) { firstStarted = true; withContext(NonCancellable) { delayed.await() } }
                else listOf(row(b))
            }, onSelect = {}, onBack = {}) }
        }
        compose.runOnIdle { assertTrue(firstStarted); host = ready(b) }
        compose.onNodeWithText("Firma B").assertIsDisplayed()
        compose.runOnIdle { delayed.complete(listOf(row(a))) }
        compose.waitForIdle()
        compose.onNodeWithText("Firma B").assertIsDisplayed()
        compose.onNodeWithText("Firma A").assertDoesNotExist()
    }

    @Test fun archiveScopeChangeHidesOldRowsWhileReplacementLoads() {
        val host = ready(a)
        var includeArchived by mutableStateOf(true)
        val replacement = CompletableDeferred<List<NovaOwnedCompany>>()
        val archived = row(a).copy(id = UUID.fromString("22222222-2222-4222-8222-222222222222"), name = "Arşiv Firma", isArchived = true)
        compose.setContent { NovaTheme(false) { NovaCompanyDestination(host, { scope ->
            if (scope) listOf(row(a), archived) else replacement.await()
        }, includeArchived = includeArchived, onSelect = {}, onBack = {}) } }
        compose.onNodeWithText("Arşiv Firma").assertIsDisplayed()
        compose.runOnIdle { includeArchived = false }
        compose.onNodeWithText("Arşiv Firma").assertDoesNotExist()
        compose.onNodeWithText("Firma A").assertDoesNotExist()
        compose.runOnIdle { replacement.complete(listOf(row(a), archived)) }
        compose.onNodeWithText("Firma A").assertIsDisplayed()
        compose.onNodeWithText("Arşiv Firma").assertDoesNotExist()
    }

    @Test fun searchTextDoesNotSurviveAccountChange() {
        var host by mutableStateOf(ready(a))
        compose.setContent {
            val owner = requireNotNull(host.identity).userID
            NovaTheme(false) { NovaCompanyDestination(host, { listOf(row(owner)) }, onSelect = {}, onBack = {}) }
        }
        compose.onNodeWithTag("nova.companies.search").performTextInput("Firma A")
        compose.onNodeWithTag("nova.company.$id").assertIsDisplayed()
        compose.runOnIdle { host = ready(b) }
        compose.onNodeWithText("Firma B").assertIsDisplayed()
        assertEquals("", compose.onNodeWithTag("nova.companies.search").fetchSemanticsNode().config[SemanticsProperties.EditableText].text)
    }
}
