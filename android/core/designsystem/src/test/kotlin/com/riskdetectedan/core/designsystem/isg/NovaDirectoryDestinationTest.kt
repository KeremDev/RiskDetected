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
    @Test fun readOnlyPreservesPendingWithoutSendingIt() {
        val client = NovaDirectoryClient(read = { _, _, _, _, _ -> NovaDirectoryPage(emptyList(), null, null) },
            save = { error("Read-only must never send") }, pending = { intent })
        compose.setContent { NovaTheme(false) { NovaDirectoryDestination(scope, NovaDirectoryKind.jobs, client = client, canWrite = false, onBack = {}) } }
        compose.onNodeWithText("Yeni kayıt").assertIsNotEnabled()
        compose.onNodeWithText("Bekleyen işlemi tamamla").assertIsNotEnabled()
    }
    @Test fun readOnlyIsPropagatedIntoWorkplaceHistory() {
        val row = NovaDirectoryRow(id, mapOf("name" to NovaDirectoryValue.Text("Sentetik İşyeri")))
        val client = NovaDirectoryClient(read = { _, kind, _, _, _ -> NovaDirectoryPage(if (kind == NovaDirectoryKind.workplaces) listOf(row) else emptyList(), null, 0) },
            save = { error("No writes expected") }, pending = { null })
        compose.setContent { NovaTheme(false) { NovaDirectoryDestination(scope, NovaDirectoryKind.workplaces, client = client, canWrite = false, onBack = {}) } }
        compose.onNodeWithText("Düzenle").assertDoesNotExist()
        compose.onNodeWithText("Bilgi geçmişi").performScrollTo().performClick()
        compose.onNodeWithText("Yeni kayıt").assertIsNotEnabled()
    }
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
        compose.onNodeWithText("Bilgi geçmişi").performScrollTo().performClick()
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
    private fun engagement() = NovaDirectoryRow(id, mapOf(
        "organization_id" to NovaDirectoryValue.Text(id.toString()), "workplace_id" to NovaDirectoryValue.Text(id.toString()),
        "starts_on" to NovaDirectoryValue.Text("2026-01-01"), "ends_before" to NovaDirectoryValue.Text("2027-01-01"), "description" to NovaDirectoryValue.Text("Sentetik iş")))
    @Test fun engagementValidatesDatesBeforeSaveAndLocksImmutableKeys() {
        var saved: NovaDirectoryIntent? = null
        val client = NovaDirectoryClient(read = { _, kind, _, _, _ -> NovaDirectoryPage(if (kind == NovaDirectoryKind.engagements) listOf(engagement()) else listOf(NovaDirectoryRow(id, mapOf("name" to NovaDirectoryValue.Text("Sentetik seçim")))), null, 0) },
            save = { saved = it; NovaDirectoryCommit(it.operationID, id, 1) }, pending = { null })
        compose.setContent { NovaTheme(false) { NovaDirectoryDestination(scope, NovaDirectoryKind.engagements, client = client, onBack = {}) } }
        compose.onNodeWithTag("directory.edit.$id").performScrollTo().performClick()
        compose.onNodeWithTag("directory.field.organization_id").assertIsNotEnabled()
        compose.onNodeWithTag("directory.field.workplace_id").assertIsNotEnabled()
        compose.onNodeWithTag("directory.field.starts_on").assertIsNotEnabled()
        compose.onNodeWithTag("directory.field.ends_before").performScrollTo().performTextReplacement("2025-12-31")
        compose.onNodeWithTag("directory.save").performScrollTo().performClick()
        compose.runOnIdle { assertNull(saved) }
        compose.onNodeWithTag("directory.error").assertTextContains("Bitiş (hariç), başlangıç tarihinden sonra olmalı.")
        compose.onNodeWithTag("directory.field.ends_before").performScrollTo().performTextReplacement("2026-12-31")
        compose.onNodeWithTag("directory.save").performScrollTo().performClick()
        compose.runOnIdle { assertEquals("2026-12-31", (saved!!.body["ends_before"] as NovaDirectoryValue.Text).value); assertEquals(id, saved!!.entityID) }
    }
    @Test fun optionFailureBlocksSaveAndRetryKeepsUserEdits() {
        var failed = false; var saved: NovaDirectoryIntent? = null
        val client = NovaDirectoryClient(read = { _, kind, _, _, _ ->
            if (kind == NovaDirectoryKind.workplaces && !failed) { failed = true; throw NovaPersonnelFailure(NovaPersonnelFailure.Kind.unavailable) }
            NovaDirectoryPage(if (kind == NovaDirectoryKind.engagements) listOf(engagement()) else listOf(NovaDirectoryRow(id, mapOf("name" to NovaDirectoryValue.Text("Sentetik seçim")))), null, 0)
        }, save = { saved = it; NovaDirectoryCommit(it.operationID, id, 1) }, pending = { null })
        compose.setContent { NovaTheme(false) { NovaDirectoryDestination(scope, NovaDirectoryKind.engagements, client = client, onBack = {}) } }
        compose.onNodeWithTag("directory.edit.$id").performScrollTo().performClick()
        compose.onNodeWithTag("directory.field.description").performScrollTo().performTextReplacement("Korunan taslak")
        compose.onNodeWithTag("directory.save").assertIsNotEnabled()
        compose.onNodeWithTag("directory.options.retry").performScrollTo().performClick()
        compose.onNodeWithTag("directory.save").performScrollTo().assertIsEnabled().performClick()
        compose.runOnIdle { assertEquals("Korunan taslak", (saved!!.body["description"] as NovaDirectoryValue.Text).value) }
    }
    @Test fun hierarchyPickerHidesSelfAndDescendants() {
        val child = UUID.randomUUID()
        val rows = listOf(NovaDirectoryRow(id, mapOf("name" to NovaDirectoryValue.Text("Ana"), "code" to NovaDirectoryValue.Text("ANA"), "workplace_id" to NovaDirectoryValue.Text(id.toString()))),
            NovaDirectoryRow(child, mapOf("name" to NovaDirectoryValue.Text("Alt"), "workplace_id" to NovaDirectoryValue.Text(id.toString()), "parent_id" to NovaDirectoryValue.Text(id.toString()))))
        val client = NovaDirectoryClient(read = { _, kind, _, _, _ -> NovaDirectoryPage(if (kind == NovaDirectoryKind.departments) rows else listOf(NovaDirectoryRow(id, mapOf("name" to NovaDirectoryValue.Text("İşyeri")))), null, 0) },
            save = { NovaDirectoryCommit(it.operationID, id, 1) }, pending = { null })
        compose.setContent { NovaTheme(false) { NovaDirectoryDestination(scope, NovaDirectoryKind.departments, client = client, onBack = {}) } }
        compose.onNodeWithTag("directory.edit.$id").performScrollTo().performClick()
        compose.onNodeWithTag("directory.field.parent_id").performScrollTo().performClick()
        compose.onNodeWithTag("directory.option.parent_id.$id").assertDoesNotExist()
        compose.onNodeWithTag("directory.option.parent_id.$child").assertDoesNotExist()
        compose.onNodeWithTag("directory.save").performScrollTo().assertIsEnabled().performClick()
        compose.onNodeWithTag("directory.add").assertExists()
    }
    @Test fun hierarchyReparentLoadsSecondPageAndPreservesTheRecord() {
        val child=UUID.randomUUID();val parent=UUID.randomUUID();var saved:NovaDirectoryIntent?=null;var secondPage=false
        fun row(key:UUID,name:String,ancestor:UUID?=null)=NovaDirectoryRow(key,mapOf("name" to NovaDirectoryValue.Text(name),"code" to NovaDirectoryValue.Text("CODE"),"workplace_id" to NovaDirectoryValue.Text(id.toString())) + (ancestor?.let{mapOf("parent_id" to NovaDirectoryValue.Text(it.toString()))}?:emptyMap()))
        val client=NovaDirectoryClient(read={_,kind,_,after,_->
            if(kind==NovaDirectoryKind.workplaces)NovaDirectoryPage(listOf(row(id,"İşyeri")),null,0)
            else if(after==null)NovaDirectoryPage(listOf(row(id,"Ana"),row(child,"Alt",id)),child,0)
            else {assertEquals(child,after);secondPage=true;NovaDirectoryPage(listOf(row(parent,"İkinci sayfa üst departman")),null,0)}
        },save={saved=it;NovaDirectoryCommit(it.operationID,id,1)},pending={null})
        compose.setContent{NovaTheme(false){NovaDirectoryDestination(scope,NovaDirectoryKind.departments,client=client,onBack={})}}
        compose.onNodeWithTag("directory.edit.$id").performScrollTo().performClick()
        compose.onNodeWithTag("directory.field.parent_id").performScrollTo().performClick()
        compose.onNodeWithTag("directory.option.parent_id.$id").assertDoesNotExist()
        compose.onNodeWithTag("directory.option.parent_id.$child").assertDoesNotExist()
        compose.onNodeWithText("Diğer kayıtlar").performScrollTo().performClick()
        compose.onNodeWithTag("directory.option.parent_id.$parent").performScrollTo().performClick()
        compose.onNodeWithTag("directory.save").performScrollTo().performClick()
        compose.runOnIdle{assertTrue(secondPage);assertEquals(id,saved!!.entityID);assertEquals("Ana",(saved!!.body["name"] as NovaDirectoryValue.Text).value);assertEquals(parent.toString(),(saved!!.body["parent_id"] as NovaDirectoryValue.Text).value)}
    }
}
