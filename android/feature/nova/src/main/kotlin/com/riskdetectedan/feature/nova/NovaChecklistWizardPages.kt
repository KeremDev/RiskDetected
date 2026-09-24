package com.riskdetectedan.feature.nova

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.rememberScrollState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import java.text.Normalizer
import java.util.Locale

/* Kontrol listesi sayfaları (iOS NovaChecklistWizardViews.swift). Bütün metinler köprüden (`checklist.texts`) gelir. */

/** The checklist wizard as the Kontroller and Kontrol Listeleri screens open it (iOS `NovaRiskWizardScreen.checklist`). */
@Composable
internal fun ChecklistWizard(client: NovaChecklistClient, initialCompany: String?, onStart: (String) -> Unit, onBack: () -> Unit) {
    NovaRiskWizardScreen(client.companies, { company -> client.catalogue(company).workplaces.map { NovaWizardWorkplace(it.id, it.name) } },
        null, initialCompany, mode = "checklist", checklistClient = client, onChecklistStart = onStart, onBack = onBack)
}

internal fun LazyListScope.checklistPurposePage(c: ChecklistWizardView, act: (Map<String, Any?>) -> Unit) {
    item { PageTitle(c.text("purpose.title"), c.text("purpose.help")) }
    c.purposes.forEach { p ->
        item(key = "purpose" + p.id) {
            Box(Modifier.testTag("checklistWizard.purpose.${p.id}")) {
                OptionRow(p.title, p.help, emptyList(), emptyList(), p.selected, single = true) { act(mapOf("type" to "ckPurpose", "id" to p.id)) }
            }
        }
    }
    if (c.purpose == "site") {
        item { NovaText(c.text("freq.title"), Modifier.padding(top = 8.dp), style = NovaTypeToken.overline) }
        item { Chips(c.freqs) { act(mapOf("type" to "ckFreq", "id" to it)) } }
        item { NovaText(c.text("freq.help"), style = NovaTypeToken.metaQuiet) }
    }
    item { NovaText(c.text("layout.title"), Modifier.padding(top = 8.dp), style = NovaTypeToken.overline) }
    item { Chips(c.layouts) { act(mapOf("type" to "ckLayout", "id" to it)) } }
    item { NovaText(c.text("layout.help"), style = NovaTypeToken.metaQuiet) }
}

@Composable
private fun Chips(items: List<ChecklistChoice>, pick: (String) -> Unit) {
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items.forEach { NovaChoiceChip(it.title, it.selected) { pick(it.id) } }
    }
}

internal fun LazyListScope.checklistTopicsPage(c: ChecklistWizardView, query: String, hits: List<ChecklistTopic>, onQuery: (String) -> Unit,
                                               act: (Map<String, Any?>) -> Unit) {
    item { PageTitle(c.text("topics.title"), c.text("topics.help")) }
    item { NovaText(c.text("topics.suggested") + " · ${c.topics.count { it.suggested }}", style = NovaTypeToken.overline) }
    if (c.topics.isEmpty()) item { NovaText(c.text("topics.empty"), style = NovaTypeToken.metaQuiet) }
    c.topics.forEach { t -> item(key = "topic" + t.id) { TopicRow(c, t, act) } }
    item { NovaText(c.text("topics.add"), Modifier.padding(top = 8.dp), style = NovaTypeToken.overline) }
    item { NovaSearchCapsule(query, c.text("topics.search"), "checklistWizard.topicSearch") { onQuery(it) } }
    hits.forEach { t -> item(key = "hit" + t.id) { TopicRow(c, t, act) } }
    if (query.length >= 2 && hits.isEmpty()) item { NovaText(c.text("topics.noHits"), style = NovaTypeToken.metaQuiet) }
}

@Composable
private fun TopicRow(c: ChecklistWizardView, t: ChecklistTopic, act: (Map<String, Any?>) -> Unit) {
    val badges = listOf(t.kindLabel, "${t.questions} " + c.text("topics.questions")) + if (t.isNew) listOf(c.text("topics.new")) else emptyList()
    val reasons = if (t.suggested) t.reasons.take(3) else if (t.selected) listOf(c.text("topics.manual")) else emptyList()
    Box(Modifier.testTag("checklistWizard.topic.${t.id}")) {
        OptionRow(t.title, "", reasons, badges, t.selected) { act(mapOf("type" to "ckTopic", "id" to t.id)) }
    }
}

internal fun LazyListScope.checklistItemsPage(c: ChecklistWizardView, open: Set<String>, drafts: Map<String, String>, onToggle: (String) -> Unit,
                                              onDraft: (String, String) -> Unit, act: (Map<String, Any?>) -> Unit) {
    item { PageTitle(c.text("items.title"), c.text("items.help")) }
    item { NovaText(c.text("summary.items") + " · ${c.itemCount}", style = NovaTypeToken.overline) }
    if (c.groups.isEmpty()) item { NovaText(c.text("items.empty"), style = NovaTypeToken.metaQuiet) }
    c.groups.forEach { g ->
        item(key = "group" + g.id) {
            val isOpen = g.id in open
            NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                Row(Modifier.fillMaxWidth().clickable { onToggle(g.id) }.testTag("checklistWizard.group.${g.id}"), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        NovaText(g.title, style = NovaTypeToken.bodyStrong)
                        NovaText(g.kindLabel + " · ${g.on} / ${g.total} " + c.text("topics.questions") + if (g.custom.isEmpty()) "" else " + ${g.custom.size}",
                            style = NovaTypeToken.metaQuiet)
                    }
                    NovaIcon(if (isOpen) "chevron.up" else "chevron.down", 16.dp, tint = NovaColorToken.textSecondary.color())
                }
                if (isOpen) Column(Modifier.padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    NovaText(if (g.on == g.total) c.text("items.none") else c.text("items.all"), Modifier.clickable { act(mapOf("type" to "ckItems", "id" to g.id)) },
                        style = NovaTypeToken.label, color = NovaColorToken.accentInk.color())
                    g.items.forEach { q -> QuestionRow(c, q) { act(mapOf("type" to "ckItem", "id" to q.key)) } }
                    g.custom.forEach { OwnRow(c, it, act) }
                    AddQuestion(c, g.id, drafts[g.id].orEmpty(), onDraft, act)
                }
            }
        }
    }
    item {
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            NovaText(c.text("items.own"), style = NovaTypeToken.cardTitle)
            NovaText(c.text("items.ownHelp"), style = NovaTypeToken.metaQuiet)
            Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                c.loose.forEach { OwnRow(c, it, act) }
                AddQuestion(c, "", drafts[""].orEmpty(), onDraft, act)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun QuestionRow(c: ChecklistWizardView, q: ChecklistQuestion, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).semantics { selected = q.selected }, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        NovaIcon(if (q.selected) "checkmark.square.fill" else "square", 18.dp,
            tint = if (q.selected) NovaColorToken.accentInk.color() else NovaColorToken.textTertiary.color())
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            NovaText(q.text, style = NovaTypeToken.body, color = if (q.selected) NovaColorToken.text.color() else NovaColorToken.textSecondary.color())
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Tag(q.vmLabel, NovaColorToken.statusNeutralBg.color(), NovaColorToken.statusNeutralInk.color())
                if (q.isNew) Tag(c.text("topics.new"), NovaColorToken.statusSuccessBg.color(), NovaColorToken.statusSuccessInk.color())
            }
        }
    }
}

@Composable
private fun OwnRow(c: ChecklistWizardView, own: ChecklistOwn, act: (Map<String, Any?>) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
        NovaIcon("person.fill.questionmark", 15.dp, tint = NovaColorToken.accentInk.color())
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            NovaText(own.text, style = NovaTypeToken.body)
            Tag(c.text("items.mine"), NovaColorToken.statusInfoBg.color(), NovaColorToken.statusInfoInk.color())
        }
        NovaText(c.text("items.remove"), Modifier.clickable { act(mapOf("type" to "ckCustom", "op" to "remove", "index" to own.index)) }.padding(4.dp),
            style = NovaTypeToken.label, color = NovaColorToken.accentInk.color())
    }
}

@Composable
private fun AddQuestion(c: ChecklistWizardView, pack: String, draft: String, onDraft: (String, String) -> Unit, act: (Map<String, Any?>) -> Unit) {
    Column(Modifier.testTag("checklistWizard.custom." + pack.ifEmpty { "own" }), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        InputField(c.text("items.custom"), draft, c.text("items.placeholder")) { onDraft(pack, it) }
        NovaButton(c.text("items.add"), {
            act(mapOf("type" to "ckCustom", "op" to "add", "pack" to pack, "text" to draft)); onDraft(pack, "")
        }, symbol = "plus", variant = NovaButtonVariant.Surface, enabled = draft.isNotBlank(), compact = true)
    }
}

internal fun LazyListScope.checklistSummaryPage(v: RiskWizardView, c: ChecklistWizardView, act: (Map<String, Any?>) -> Unit, edit: (String) -> Unit) {
    item { PageTitle(c.text("summary.title"), c.text("summary.help")) }
    item {
        Box(Modifier.testTag("checklistWizard.title")) {
            InputField(c.text("summary.name"), if (c.titleManual) c.title else "", c.title) { act(mapOf("type" to "ckTitle", "value" to it)) }
        }
    }
    item {
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            val purpose = listOfNotNull(c.purposes.firstOrNull { it.selected }?.title,
                if (c.purpose == "site") c.freqs.firstOrNull { it.selected && it.id.isNotEmpty() }?.title else null).joinToString(" · ")
            listOf(Triple(c.text("summary.firm"), v.firm.name, "firm"),
                Triple(c.text("summary.sector"), v.sectors.joinToString(", ") { it.title } + if (v.hazardClassLabel.isNotEmpty()) " · " + v.hazardClassLabel else "", "sector"),
                Triple(c.text("summary.purpose"), purpose, "purpose"),
                Triple(c.text("summary.layout"), (c.layouts.firstOrNull { it.selected }?.title ?: "") + " · ${c.listCount}", "purpose"),
                Triple(c.text("summary.topics"), "${c.topicCount} · " + c.topics.filter { it.selected }.joinToString(", ") { it.title }, "topics"),
                Triple(c.text("summary.items"), "${c.itemCount}", "items")).forEach { (label, value, target) ->
                Row(Modifier.fillMaxWidth().padding(vertical = 5.dp), verticalAlignment = Alignment.Top) {
                    Column(Modifier.weight(1f)) {
                        NovaText(label, style = NovaTypeToken.metaQuiet)
                        NovaText(value.ifEmpty { "—" }, style = NovaTypeToken.body)
                    }
                    NovaText(c.text("summary.edit"), Modifier.clickable { edit(target) }.padding(4.dp), style = NovaTypeToken.label, color = NovaColorToken.accentInk.color())
                }
            }
        }
    }
    if (c.gaps.isNotEmpty()) item {
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            NovaText(c.text("summary.gaps"), style = NovaTypeToken.overline)
            c.gaps.forEach { NovaText("• $it", style = NovaTypeToken.meta) }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
internal fun LazyListScope.checklistResultPage(list: ChecklistWizardList, c: ChecklistWizardView, busy: Boolean, canSave: Boolean, saved: List<String>,
                                               open: Set<String>, onToggle: (String) -> Unit, onExport: (String) -> Unit, onSave: () -> Unit,
                                               onStart: ((String) -> Unit)?) {
    item {
        PageTitle(list.title, listOf(list.purposeLabel, list.freqLabel, "${list.sections.size} " + c.text("topics.unit"),
            "${list.total} " + c.text("topics.questions")).filter { it.isNotEmpty() }.joinToString(" · "))
    }
    if (list.total == 0) {
        item { NovaHelpHint(c.text("result.nothing")) }
        return
    }
    item {
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            NovaText(c.text("result.download"), style = NovaTypeToken.cardTitle)
            Spacer(Modifier.height(8.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaButton(c.text("result.word"), { onExport("docx") }, Modifier.testTag("checklistWizard.docx"), symbol = "doc.text", enabled = !busy, compact = true)
                NovaButton(c.text("result.excel"), { onExport("xlsx") }, Modifier.testTag("checklistWizard.xlsx"), symbol = "tablecells",
                    variant = NovaButtonVariant.Surface, enabled = !busy, compact = true)
                NovaButton(c.text("result.pdf"), { onExport("pdf") }, symbol = "doc.richtext", variant = NovaButtonVariant.Surface, enabled = !busy, compact = true)
            }
        }
    }
    if (canSave) item {
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            NovaText(c.text("result.save"), style = NovaTypeToken.cardTitle)
            NovaText(c.text("result.saveHelp"), style = NovaTypeToken.metaQuiet)
            NovaText(c.text("result.lists") + " · ${list.lists.size}", Modifier.padding(top = 6.dp), style = NovaTypeToken.overline)
            list.lists.forEach { NovaText("• " + it.title + " · ${it.items.size} " + c.text("topics.questions"), style = NovaTypeToken.meta) }
            Spacer(Modifier.height(8.dp))
            NovaButton(if (saved.isNotEmpty()) c.text("result.saved") else if (busy) c.text("result.saving") else c.text("result.save"), onSave,
                Modifier.testTag("checklistWizard.save"), symbol = if (saved.isNotEmpty()) "checkmark.circle" else "tray.and.arrow.down",
                variant = if (saved.isNotEmpty()) NovaButtonVariant.Surface else NovaButtonVariant.Primary, enabled = !busy && saved.isEmpty(), compact = true)
            val code = saved.singleOrNull()
            if (onStart != null && code != null) {
                Spacer(Modifier.height(8.dp))
                NovaText(c.text("result.startHelp"), style = NovaTypeToken.metaQuiet)
                NovaButton(c.text("result.start"), { onStart(code) }, Modifier.testTag("checklistWizard.start"), symbol = "play",
                    variant = NovaButtonVariant.Surface, enabled = !busy, compact = true)
            }
        }
    }
    list.sections.forEach { s ->
        item(key = "section" + s.id) {
            val isOpen = s.id in open
            NovaCard(Modifier.fillMaxWidth().testTag("checklistWizard.section.${s.id}"), padding = 14) {
                Row(Modifier.fillMaxWidth().clickable { onToggle(s.id) }, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        NovaText(s.title, style = NovaTypeToken.bodyStrong)
                        NovaText(s.kindLabel + " · ${s.items.size} " + c.text("topics.questions"), style = NovaTypeToken.metaQuiet)
                        if (s.why.isNotEmpty()) Tag(s.why.joinToString(", "), NovaColorToken.statusSuccessBg.color(), NovaColorToken.statusSuccessInk.color())
                    }
                    NovaIcon(if (isOpen) "chevron.up" else "chevron.down", 16.dp, tint = NovaColorToken.textSecondary.color())
                }
                if (isOpen) Column(Modifier.padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    s.items.forEach { e ->
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            NovaText("${e.no}.", Modifier.width(30.dp), style = NovaTypeToken.metaQuiet)
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                NovaText(e.text, style = NovaTypeToken.body)
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    if (e.vmLabel.isNotEmpty()) Tag(e.vmLabel, NovaColorToken.statusNeutralBg.color(), NovaColorToken.statusNeutralInk.color())
                                    if (e.own) Tag(c.text("result.own"), NovaColorToken.statusInfoBg.color(), NovaColorToken.statusInfoInk.color())
                                    if (e.isNew) Tag(c.text("result.newItem"), NovaColorToken.statusSuccessBg.color(), NovaColorToken.statusSuccessInk.color())
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    item { NovaHelpHint(list.note) }
}

/** Publishes the finished list to Listelerim with the module's own template actions: catalogue questions are copied with their method and
 *  help text, the expert's own questions are written, then the version is published. A server without the extension catalogue refuses those
 *  templates; their questions are then written as the expert's own (iOS `NovaChecklistWizardSaver`). */
internal object ChecklistWizardSaver {
    fun fold(value: String): String = Normalizer.normalize(value.lowercase(Locale.forLanguageTag("tr-TR")), Normalizer.Form.NFD)
        .replace(Regex("\\p{Mn}+"), "").replace('ı', 'i').trim()
    /** A new title opens a new list; the same title would open a new version of an existing one instead. */
    fun unique(title: String, taken: Set<String>): String {
        if (fold(title) !in taken) return title
        var number = 2
        while (fold("$title ($number)") in taken) number++
        return "$title ($number)"
    }
    suspend fun save(runtime: NovaRiskWizardRuntime, client: NovaChecklistClient, company: String?): List<String> {
        val result = runtime.checklistList()
        val taken = client.templates(company).map { fold(it.title) }.toMutableSet()
        val codes = mutableListOf<String>()
        var extensionOnServer = true
        for (entry in result.lists.filter { it.items.isNotEmpty() }) {
            val title = unique(entry.title, taken)
            taken += fold(title)
            client.draftTemplate(company, title)
            val template = client.templates(company).firstOrNull { fold(it.title) == fold(title) } ?: throw NovaChecklistException(NovaChecklistFailure.unavailable)
            val draft = template.draft ?: throw NovaChecklistException(NovaChecklistFailure.unavailable)
            val code = template.templateCode
            var revision = draft.revision
            var position = draft.items.size
            // One copy batch at a time: catalogue questions, or one extension template's questions.
            val pending = mutableListOf<Triple<NovaChecklistItemSelection, ChecklistSaveItem, Int>>()
            var pendingFallback = false
            // Every successful template action bumps the draft's edit revision by one; a refused one changes nothing.
            suspend fun write(item: ChecklistSaveItem, at: Int) {
                client.setSectionItem(company, code, draft.version, revision, "w$at", item.text, item.allowsNotApplicable, at, item.section)
                revision++
            }
            suspend fun flush() {
                val batch = pending.toList()
                pending.clear()
                if (batch.isEmpty()) return
                if (pendingFallback && !extensionOnServer) { batch.forEach { write(it.second, it.third) }; return }
                try {
                    batch.chunked(100).forEach { chunk -> client.copyItems(company, code, draft.version, revision, chunk.map { it.first }); revision++ }
                } catch (error: NovaChecklistException) {
                    if (error.failure != NovaChecklistFailure.denied || !pendingFallback) throw error
                    extensionOnServer = false
                    batch.forEach { write(it.second, it.third) }
                }
            }
            for (item in entry.items) {
                position++
                val ref = item.ref
                if (ref == null) { flush(); write(item, position); continue }
                val last = pending.lastOrNull()
                if (last != null && (pendingFallback != item.fallback || (item.fallback && last.first.sourceTemplateCode != ref.template))) flush()
                pendingFallback = item.fallback
                pending += Triple(NovaChecklistItemSelection(ref.template, ref.item, sectionTitle = item.section), item, position)
            }
            flush()
            client.publishTemplate(company, code, draft.version, revision, result.approvalNote)
            codes += code
        }
        return codes
    }
}
