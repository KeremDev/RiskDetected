package com.riskdetectedan.isg.designpreview

import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.feature.nova.NovaChecklistClient

/** Synthetic checklist runs; nothing leaves the process. */
internal object PreviewChecklistClient : NovaChecklistClient {
    private fun answer(position: Int, prompt: String, result: NovaChecklistResult?) = NovaChecklistAnswer("q$position", prompt, position, null, null, null, true,
        null, if (position == 2) "Korkuluk yüksekliği ve ara çubuk sürekliliğine bakın." else null, emptyList(), null, false, false, false, result, null, null, null)
    private val run = NovaChecklistRun("r1", "c1", "Koza Altın A.Ş", "w1", "Kırma Eleme", "scaffold", "İskele Kontrolü", 3, NovaChecklistRunState.`open`,
        "2026-09-22", null, 4, null, null, null, null, 4, 1, 3, 1, 0, 0, 25.0, null, null, null, emptyList(), 0,
        listOf(answer(1, "İskele zemini düz ve sağlam mı?", NovaChecklistResult.conform), answer(2, "Korkuluklar eksiksiz mi?", null),
            answer(3, "Giriş merdiveni sabitlenmiş mi?", null), answer(4, "İskele etiketi güncel mi?", null)))
    private val done = run.copy(id = "r2", templateTitle = "Forklift Günlük Kontrol", state = NovaChecklistRunState.submitted, answered = 4, remaining = 0, conform = 3,
        nonconform = 1, nonconformitiesOpened = 1)
    override val companies: suspend () -> List<NovaCompanyOption> = { listOf(NovaCompanyOption("c1", "Koza Altın A.Ş", "Maden · Çok tehlikeli", null)) }
    override suspend fun catalogue(company: String?) = NovaChecklistCatalogue(listOf(NovaChecklistCatalogue.Workplace("w1", "Kırma Eleme", false)),
        listOf(NovaChecklistStarter("scaffold", "İskele Kontrolü", 3, 4, true, null, "insaat", "equipment", null, null)), true, null, null, null)
    override suspend fun library(search: String, sector: String?, kind: String?, offset: Int) =
        NovaChecklistLibrary("2026.3", "published", "approved", emptyList(), emptyList(), emptyList(), 0, 30, 0)
    override suspend fun templateDetail(template: String) = NovaChecklistTemplateDetail(template, null, null, "İskele Kontrolü", null, "equipment", emptyList(),
        null, emptyList(), true, null, 3, emptyList())
    override suspend fun templates(company: String?) = emptyList<NovaChecklistTemplate>()
    override suspend fun assignments(company: String) = emptyList<NovaChecklistAssignment>()
    override suspend fun board(query: NovaChecklistQuery): NovaChecklistBoard {
        val rows = listOf(run, done).filter { it.state.wire == query.state }
        return NovaChecklistBoard(rows, mapOf("open" to 1, "submitted" to 1), rows.size, false, 0)
    }
    override suspend fun detail(run: String) = if (run == done.id) done else this.run
    private fun refuse(): Nothing = throw NovaChecklistException(NovaChecklistFailure.moduleUnavailable)
    override suspend fun startRun(company: String?, workplace: String?, template: String, startedOn: String, area: String, equipment: String, document: String) = refuse()
    override suspend fun answer(company: String?, draft: NovaChecklistAnswerDraft) = refuse()
    override suspend fun uploadEvidence(company: String, attachment: NovaChecklistAttachment) = refuse()
    override suspend fun submit(company: String?, run: String, revision: Long) = refuse()
    override suspend fun cancel(company: String?, run: String, revision: Long) = refuse()
    override suspend fun revise(company: String?, run: String, revision: Long, startedOn: String) = refuse()
    override suspend fun draftTemplate(company: String?, title: String) = refuse()
    override suspend fun setItem(company: String?, template: String, version: Int, revision: Long, itemCode: String, prompt: String, allowsNotApplicable: Boolean, position: Int) = refuse()
    override suspend fun copyItems(company: String?, template: String, version: Int, revision: Long, items: List<NovaChecklistItemSelection>) = refuse()
    override suspend fun reorderItems(company: String?, template: String, version: Int, revision: Long, itemCodes: List<String>) = refuse()
    override suspend fun removeItem(company: String?, template: String, version: Int, revision: Long, itemCode: String) = refuse()
    override suspend fun publishTemplate(company: String?, template: String, version: Int, revision: Long, note: String) = refuse()
    override suspend fun copyTemplate(company: String?, template: String, title: String?) = refuse()
    override suspend fun assignTemplate(company: String, workplace: String?, template: String) = refuse()
    override suspend fun deactivateAssignment(company: String, assignment: String) = refuse()
    override fun pendingAnswers() = 0 to 0
    override suspend fun syncPendingAnswers() = 0 to 0
}
