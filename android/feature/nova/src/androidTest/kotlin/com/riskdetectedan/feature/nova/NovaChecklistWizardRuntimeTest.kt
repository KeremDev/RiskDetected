package com.riskdetectedan.feature.nova

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.riskdetectedan.core.data.nova.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream

/** Checklist mode of the V6 wizard in a real WebView (iOS `testChecklistModeSuggestsTopicsExportsAndPublishesToListelerim`). */
@RunWith(AndroidJUnit4::class)
class NovaChecklistWizardRuntimeTest {
    /** Records the template actions the saver sends; everything else is out of scope. */
    private class Recorder(private val existingTitle: String) : NovaChecklistClient {
        val drafted = mutableListOf<String>()
        val copied = mutableListOf<NovaChecklistItemSelection>()
        val written = mutableListOf<Triple<String, Int, String>>()
        val revisions = mutableListOf<Long>()
        var published: Pair<Long, String>? = null
        override val companies: suspend () -> List<NovaCompanyOption> = { emptyList() }
        override suspend fun templates(company: String?): List<NovaChecklistTemplate> {
            val existing = NovaChecklistTemplate("c_old", existingTitle, isProduct = false, isArchived = false, versions = emptyList())
            val title = drafted.lastOrNull() ?: return listOf(existing)
            return listOf(existing, NovaChecklistTemplate("c_new", title, isProduct = false, isArchived = false,
                versions = listOf(NovaChecklistTemplateVersion(1, 0, "draft", null, null, emptyList()))))
        }
        override suspend fun draftTemplate(company: String?, title: String) { drafted += title }
        override suspend fun copyItems(company: String?, template: String, version: Int, revision: Long, items: List<NovaChecklistItemSelection>) {
            assertEquals("c_new", template); revisions += revision; copied += items
        }
        override suspend fun setItem(company: String?, template: String, version: Int, revision: Long, itemCode: String, prompt: String,
                                     allowsNotApplicable: Boolean, position: Int) = fail("the section-aware write is used")
        override suspend fun setSectionItem(company: String?, template: String, version: Int, revision: Long, itemCode: String, prompt: String,
                                            allowsNotApplicable: Boolean, position: Int, section: String) {
            assertEquals("w$position", itemCode); revisions += revision; written += Triple(template, position, section)
        }
        override suspend fun publishTemplate(company: String?, template: String, version: Int, revision: Long, note: String) { published = revision to note }
        override suspend fun catalogue(company: String?): NovaChecklistCatalogue = TODO()
        override suspend fun library(search: String, sector: String?, kind: String?, offset: Int): NovaChecklistLibrary = TODO()
        override suspend fun templateDetail(template: String): NovaChecklistTemplateDetail = TODO()
        override suspend fun assignments(company: String): List<NovaChecklistAssignment> = TODO()
        override suspend fun board(query: NovaChecklistQuery): NovaChecklistBoard = TODO()
        override suspend fun detail(run: String): NovaChecklistRun = TODO()
        override suspend fun startRun(company: String?, workplace: String?, template: String, startedOn: String, area: String, equipment: String,
                                      document: String): NovaChecklistRun? = TODO()
        override suspend fun answer(company: String?, draft: NovaChecklistAnswerDraft): NovaChecklistRun? = TODO()
        override suspend fun uploadEvidence(company: String, attachment: NovaChecklistAttachment): String = TODO()
        override suspend fun submit(company: String?, run: String, revision: Long): NovaChecklistRun? = TODO()
        override suspend fun cancel(company: String?, run: String, revision: Long): NovaChecklistRun? = TODO()
        override suspend fun revise(company: String?, run: String, revision: Long, startedOn: String): NovaChecklistRun? = TODO()
        override suspend fun reorderItems(company: String?, template: String, version: Int, revision: Long, itemCodes: List<String>) = TODO()
        override suspend fun removeItem(company: String?, template: String, version: Int, revision: Long, itemCode: String) = TODO()
        override suspend fun copyTemplate(company: String?, template: String, title: String?) = TODO()
        override suspend fun assignTemplate(company: String, workplace: String?, template: String) = TODO()
        override suspend fun deactivateAssignment(company: String, assignment: String) = TODO()
        override fun pendingAnswers() = 0 to 0
        override suspend fun syncPendingAnswers() = 0 to 0
    }

    @Test fun checklistModeSuggestsTopicsExportsAndPublishes() = runBlocking {
        withContext(Dispatchers.Main) {
            val context = InstrumentationRegistry.getInstrumentation().context
            val runtime = NovaRiskWizardRuntime(context)
            try {
                runtime.ready()
                var view = runtime.start("Deniz Lojistik", "24.09.2026", "checklist")
                assertEquals("checklist", view.mode)
                assertEquals(listOf("purpose", "topics", "items", "summary"), view.steps.takeLast(4))
                view = runtime.act(mapOf("type" to "sector", "id" to "S127"))
                view = runtime.act(mapOf("type" to "pick", "kind" to "equipment", "id" to "E041"))
                view = runtime.act(mapOf("type" to "pick", "kind" to "equipment", "id" to "E051"))
                val checklist = requireNotNull(view.checklist)
                val ids = checklist.topics.map { it.id }.toSet()
                assertTrue(ids.containsAll(listOf("WAREHOUSE", "FORK", "RACK", "FIRE")))
                assertFalse("a forklift does not bring machine lockout checks", "LOTO" in ids)
                assertTrue(checklist.topics.first { it.id == "FORK" }.reasons.contains("Denge ağırlıklı forklift"))
                assertTrue(runtime.checklistTopics("iskele").any { it.id == "SCAFFOLD" })
                runtime.act(mapOf("type" to "ckTopic", "id" to "BATTERY"))
                runtime.act(mapOf("type" to "ckCustom", "op" to "add", "pack" to "FORK", "text" to "Forklift anahtarları vardiya sonunda teslim ediliyor mu?"))

                val list = runtime.checklistList()
                assertEquals(1, list.lists.size)
                assertEquals(list.total, list.lists.single().items.size)
                assertEquals(list.total, list.fromCatalog + list.newCatalog + list.own)
                for (format in listOf("docx", "xlsx")) {
                    val file = runtime.download(format)
                    assertEquals("Deniz_Lojistik_Kontrol_Listesi_24-09-2026.$format", file.name)
                    val parts = mutableSetOf<String>()
                    ZipInputStream(ByteArrayInputStream(file.bytes)).use { zip -> var entry = zip.nextEntry; while (entry != null) { parts += entry.name; entry = zip.nextEntry } }
                    assertTrue(parts.contains(if (format == "docx") "word/document.xml" else "xl/worksheets/sheet1.xml"))
                }
                val pdf = runtime.download("pdf")
                assertEquals("%PDF", pdf.bytes.take(4).toByteArray().toString(Charsets.US_ASCII))

                val client = Recorder(list.title)
                assertEquals(listOf("c_new"), ChecklistWizardSaver.save(runtime, client, null))
                assertEquals(listOf(list.title + " (2)"), client.drafted)
                assertEquals(list.fromCatalog, client.copied.size)
                assertEquals("catalog_dpo_01", client.copied.first().sourceTemplateCode)
                assertEquals(list.newCatalog + list.own, client.written.size)
                assertTrue(client.written.any { it.third == "Forklift kullanım öncesi kontrolü" })
                assertEquals((0 until client.revisions.size).map { it.toLong() }, client.revisions)
                assertEquals(client.revisions.size.toLong() to list.approvalNote, client.published)
                assertEquals("Liste (3)", ChecklistWizardSaver.unique("Liste", setOf("liste", "liste (2)")))
            } finally { runtime.close() }
        }
    }
}
