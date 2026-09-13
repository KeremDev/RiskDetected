package com.riskdetectedan.core.designsystem.isg

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class NovaDirectoryDestinationTest {
    @get:Rule val compose = createComposeRule()
    private val scope = NovaPersonnelScope(UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID(), "first")
    private val id = UUID.randomUUID()
    private val intent = NovaDirectoryIntent(scope, NovaDirectoryKind.jobs, UUID.randomUUID(), UUID.randomUUID(), null, 0, mapOf("name" to NovaDirectoryValue.Text("Operatör")))
    @Test fun pendingWriteBlocksNewRecordAndRetryUsesSameIntent() {
        var pending: NovaDirectoryIntent? = intent
        var actual: NovaDirectoryIntent? = null
        val client = NovaDirectoryClient(read = { _, _, _, _, _ -> NovaDirectoryPage(emptyList(), null, null) },
            save = { actual = it; pending = null; NovaDirectoryCommit(it.operationID, id, 0) }, pending = { pending })
        compose.setContent { NovaTheme(false) { NovaDirectoryDestination(scope, NovaDirectoryKind.jobs, client = client, onBack = {}) } }
        compose.onNodeWithText("Yeni kayıt").assertIsNotEnabled()
        compose.onNodeWithText("Bekleyen işlemi tamamla").performScrollTo().performClick()
        compose.waitForIdle()
        compose.runOnIdle { assertEquals(intent, actual) }
        compose.onNodeWithText("Yeni kayıt").assertIsEnabled()
    }
    @Test fun workplaceHistoryOpensAndBackReturnsToSameList() {
        val row = NovaDirectoryRow(id, mapOf("name" to NovaDirectoryValue.Text("Sentetik İşyeri")))
        val client = NovaDirectoryClient(read = { _, kind, parent, _, _ ->
            if (kind == NovaDirectoryKind.contexts) { assertEquals(id, parent); NovaDirectoryPage(emptyList(), null, 0) }
            else NovaDirectoryPage(listOf(row), null, null)
        }, save = { error("No writes expected") }, pending = { null })
        compose.setContent { NovaTheme(false) { NovaDirectoryDestination(scope, NovaDirectoryKind.workplaces, client = client, onBack = {}) } }
        compose.onNodeWithText("Tarihli bağlam").performScrollTo().performClick()
        compose.onNodeWithText("İşyeri Bağlam Geçmişi").assertIsDisplayed()
        compose.onNodeWithContentDescription("Geri").performClick()
        compose.onNodeWithText("Sentetik İşyeri").assertExists()
    }
    @Test fun unavailableJournalNeverEnablesNewWrite() {
        val client = NovaDirectoryClient(read = { _, _, _, _, _ -> error("Must not read after journal failure") },
            save = { error("No writes expected") }, pending = { throw NovaPersonnelFailure(NovaPersonnelFailure.Kind.unavailable) })
        compose.setContent { NovaTheme(false) { NovaDirectoryDestination(scope, NovaDirectoryKind.jobs, client = client, onBack = {}) } }
        compose.onNodeWithText("Yeni kayıt").assertIsNotEnabled()
        compose.onNodeWithText("Tekrar yükle").assertExists()
    }
}
