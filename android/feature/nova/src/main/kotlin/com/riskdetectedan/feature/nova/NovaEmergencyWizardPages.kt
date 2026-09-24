package com.riskdetectedan.feature.nova

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*

/** A person the company already has on file, offered for the plan team (iOS `NovaEmergencyWizardStaff`). */
internal data class EmergencyWizardStaff(val id: String, val name: String, val detail: String, val isSupportStaff: Boolean)

/* Acil durum sayfaları (iOS NovaEmergencyWizardViews.swift). Bütün metinler köprüden (`emergency.texts`) gelir. */

internal fun LazyListScope.emergencySitePage(e: EmergencyWizardView, act: (Map<String, Any?>) -> Unit) {
    item { PageTitle(e.text("site.title"), e.text("site.help")) }
    e.site.forEach { s ->
        item(key = "site" + s.id) {
            Box(Modifier.testTag("emergencyWizard.site.${s.id}")) { OptionRow(s.title, s.help, emptyList(), emptyList(), s.selected) { act(mapOf("type" to "site", "id" to s.id)) } }
        }
    }
}

internal fun LazyListScope.emergencyCardsPage(e: EmergencyWizardView, query: String, hits: List<EmergencyCard>, onQuery: (String) -> Unit,
                                              act: (Map<String, Any?>) -> Unit) {
    item { PageTitle(e.text("cards.title"), e.text("cards.help")) }
    e.cards.forEach { c ->
        item(key = "card" + c.id) {
            Box(Modifier.testTag("emergencyWizard.card.${c.id}")) {
                OptionRow(c.title, c.trigger + " · " + c.mode, if (c.core) emptyList() else if (c.suggested) c.reasons.take(2) else listOf(e.text("cards.manual")),
                    if (c.core) listOf(e.text("cards.core")) else emptyList(), c.selected) { if (!c.core) act(mapOf("type" to "card", "id" to c.id)) }
            }
        }
    }
    item { NovaText(e.text("cards.add"), Modifier.padding(top = 8.dp), style = NovaTypeToken.overline) }
    item { NovaSearchCapsule(query, e.text("cards.search"), "emergencyWizard.cardSearch") { onQuery(it) } }
    hits.forEach { c -> item(key = "hit" + c.id) { OptionRow(c.title, c.trigger, emptyList(), emptyList(), false) { act(mapOf("type" to "card", "id" to c.id)) } } }
}

internal fun LazyListScope.emergencyTeamPage(e: EmergencyWizardView, staff: List<EmergencyWizardStaff>?, staffQuery: String, openPerson: String?,
                                             onStaffQuery: (String) -> Unit, onOpenPerson: (String?) -> Unit, act: (Map<String, Any?>) -> Unit) {
    val teams = e.teams
    item { PageTitle(e.text("team.title"), e.text("team.help")) }
    item {
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            NovaText(e.text("team.reference"), style = NovaTypeToken.overline)
            NovaText(listOf(teams.hazardClassLabel, teams.employees?.toString() ?: e.text("team.noEmployees")).filter { it.isNotEmpty() }.joinToString(" · "),
                style = NovaTypeToken.metaQuiet)
            teams.roles.forEach { role ->
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Column(Modifier.weight(1f)) {
                        NovaText(role.label, style = NovaTypeToken.bodyStrong)
                        NovaText(role.basis, style = NovaTypeToken.metaQuiet)
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        NovaText(role.required?.toString() ?: (if (teams.combinedRequired != null && role.id != "ilkyardim") e.text("team.shared") else "—"),
                            style = NovaTypeToken.sectionTitle)
                        NovaText(e.text("team.assigned") + " ${role.assigned}", style = NovaTypeToken.metaQuiet)
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            NovaText(teams.note, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color())
        }
    }
    item { NovaText(e.text("team.members") + " · ${e.members.size}", Modifier.padding(top = 4.dp), style = NovaTypeToken.overline) }
    if (e.members.isEmpty()) item { NovaText(e.text("team.empty"), style = NovaTypeToken.metaQuiet) }
    e.members.forEach { m -> item(key = "member${m.index}") { MemberCard(e, m, act) } }
    item {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            NovaText(e.text("team.manual"), style = NovaTypeToken.label)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                teams.roles.forEach { role -> NovaChoiceChip("+ " + role.label, false) { act(mapOf("type" to "member", "op" to "add", "role" to role.id)) } }
            }
        }
    }
    if (staff != null) {
        item { NovaText(e.text("team.fromCompany"), Modifier.padding(top = 8.dp), style = NovaTypeToken.overline) }
        item { NovaSearchCapsule(staffQuery, e.text("team.name"), "emergencyWizard.staffSearch") { onStaffQuery(it) } }
        val taken = e.members.mapNotNull { it.ref }.toSet()
        staff.filter { it.id.lowercase() !in taken && (staffQuery.length < 2 || it.name.contains(staffQuery, ignoreCase = true)) }.take(40).forEach { person ->
            item(key = "staff" + person.id) {
                Column(Modifier.fillMaxWidth().background(NovaColorToken.surface.color(), RoundedCornerShape(12.dp)).clickable { onOpenPerson(if (openPerson == person.id) null else person.id) }
                    .padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        NovaIcon(if (person.isSupportStaff) "person.badge.shield.checkmark" else "person", 18.dp)
                        Column(Modifier.weight(1f)) {
                            NovaText(person.name, style = NovaTypeToken.bodyStrong)
                            if (person.detail.isNotEmpty()) NovaText(person.detail, style = NovaTypeToken.metaQuiet)
                        }
                        NovaIcon("plus.circle", 18.dp, tint = NovaColorToken.accentInk.color())
                    }
                    if (openPerson == person.id) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        teams.roles.forEach { role ->
                            NovaChoiceChip(role.label, false) {
                                onOpenPerson(null)
                                act(mapOf("type" to "member", "op" to "add", "role" to role.id, "name" to person.name, "title" to person.detail, "ref" to person.id.lowercase()))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MemberCard(e: EmergencyWizardView, m: EmergencyMember, act: (Map<String, Any?>) -> Unit) {
    fun set(field: String, value: Any?) = act(mapOf("type" to "member", "op" to "set", "index" to m.index, "field" to field, "value" to value))
    NovaCard(Modifier.fillMaxWidth(), padding = 12) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                e.teams.roles.forEach { role -> NovaChoiceChip(role.label, m.role == role.id) { set("role", role.id) } }
            }
            NovaIcon("trash", 18.dp, Modifier.clickable { act(mapOf("type" to "member", "op" to "remove", "index" to m.index)) }.padding(8.dp))
        }
        Spacer(Modifier.height(8.dp))
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            InputField(e.text("team.name"), m.name, e.text("team.name")) { set("name", it) }
            InputField(e.text("team.personTitle"), m.title, e.text("team.personTitle")) { set("title", it) }
            InputField(e.text("team.area"), m.area, e.text("team.area")) { set("area", it) }
            InputField(e.text("team.contact"), m.contact, e.text("team.contact")) { set("contact", it) }
            NovaChoiceChip(e.text("team.backup"), m.backup) { set("backup", !m.backup) }
        }
    }
}

internal fun LazyListScope.emergencyFieldsPage(e: EmergencyWizardView, act: (Map<String, Any?>) -> Unit) {
    item { PageTitle(e.text("fields.title"), e.text("fields.help")) }
    item { NovaText(e.text("fields.general"), style = NovaTypeToken.overline) }
    e.fields.filter { it.general }.forEach { f -> item(key = "f" + f.key) { InputField(f.label, f.value, e.text("fields.placeholder")) { act(mapOf("type" to "field", "key" to f.key, "value" to it)) } } }
    val specific = e.fields.filter { !it.general }
    if (specific.isNotEmpty()) {
        item { NovaText(e.text("fields.specific") + " · ${specific.size}", Modifier.padding(top = 6.dp), style = NovaTypeToken.overline) }
        specific.forEach { f -> item(key = "f" + f.key) { InputField(f.label + " · " + f.card, f.value, e.text("fields.placeholder")) { act(mapOf("type" to "field", "key" to f.key, "value" to it)) } } }
    }
    item { NovaText(e.text("fields.contacts"), Modifier.padding(top = 6.dp), style = NovaTypeToken.overline) }
    e.contacts.forEach { c ->
        item(key = "contact${c.index}") {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Bottom) {
                Box(Modifier.weight(2f)) { InputField(e.text("fields.contactLabel"), c.label, e.text("fields.contactLabel")) { act(mapOf("type" to "contact", "op" to "set", "index" to c.index, "field" to "label", "value" to it)) } }
                Box(Modifier.weight(1f)) { InputField(e.text("fields.contactNumber"), c.number, e.text("fields.contactNumber")) { act(mapOf("type" to "contact", "op" to "set", "index" to c.index, "field" to "number", "value" to it)) } }
                NovaIcon("trash", 18.dp, Modifier.clickable { act(mapOf("type" to "contact", "op" to "remove", "index" to c.index)) }.padding(10.dp))
            }
        }
    }
    item { NovaButton(e.text("fields.addContact"), { act(mapOf("type" to "contact", "op" to "add")) }, symbol = "plus", variant = NovaButtonVariant.Surface, compact = true) }
}

internal fun LazyListScope.emergencySummaryPage(v: RiskWizardView, e: EmergencyWizardView, edit: (String) -> Unit) {
    val selected = e.cards.filter { it.selected }
    item { PageTitle(e.text("summary.title"), e.text("summary.help")) }
    item {
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            listOf(
                Triple(e.text("summary.firm"), listOf(v.firm.name, e.employees?.toString().orEmpty()).filter { it.isNotEmpty() }.joinToString(" · "), "firm"),
                Triple(e.text("summary.sector"), v.sectors.joinToString(", ") { it.title } + if (v.hazardClassLabel.isNotEmpty()) " · " + v.hazardClassLabel else "", "sector"),
                Triple(e.text("summary.valid"), e.validUntil, "sector"),
                Triple(e.text("summary.cards"), "${selected.size} · " + selected.joinToString(", ") { it.title }, "cards"),
                Triple(e.text("summary.team"), "${e.members.size} · " + e.teams.roles.joinToString(", ") { it.label + " " + (it.required?.toString() ?: "—") }, "team"),
                Triple(e.text("summary.fields"), "${e.fields.count { it.value.isNotEmpty() }} / ${e.fields.size}", "fields"),
            ).forEach { (label, value, target) ->
                Row(Modifier.fillMaxWidth().padding(vertical = 5.dp), verticalAlignment = Alignment.Top) {
                    Column(Modifier.weight(1f)) {
                        NovaText(label, style = NovaTypeToken.metaQuiet)
                        NovaText(value.ifEmpty { "—" }, style = NovaTypeToken.body)
                    }
                    NovaText(e.text("summary.edit"), Modifier.clickable { edit(target) }.padding(4.dp), style = NovaTypeToken.label, color = NovaColorToken.accentInk.color())
                }
            }
        }
    }
    item { GapsCard(e.text("summary.gaps"), e.gaps) }
}

@Composable
private fun GapsCard(title: String, gaps: List<String>) {
    NovaCard(Modifier.fillMaxWidth(), padding = 14) {
        NovaText("$title · ${gaps.size}", style = NovaTypeToken.overline)
        gaps.forEach { NovaText("• $it", style = NovaTypeToken.meta) }
    }
}

internal fun LazyListScope.emergencyResultPage(plan: EmergencyPlan, e: EmergencyWizardView, busy: Boolean, canSave: Boolean, saved: Boolean, open: Set<String>,
                                               onToggle: (String) -> Unit, onExport: (String) -> Unit, onSave: () -> Unit) {
    item { PageTitle(plan.name.ifEmpty { e.text("file.title") }, listOf(plan.sector, plan.hazardClass, plan.validUntil).filter { it.isNotEmpty() }.joinToString(" · ")) }
    item {
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            NovaText(e.text("result.plan"), style = NovaTypeToken.cardTitle)
            NovaText(e.text("result.planHelp"), style = NovaTypeToken.metaQuiet)
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaButton(e.text("result.download"), { onExport("docx") }, Modifier.testTag("emergencyWizard.docx"), symbol = "arrow.down.doc", enabled = !busy, compact = true)
                NovaButton(e.text("result.pdf"), { onExport("pdf") }, symbol = "doc.richtext", variant = NovaButtonVariant.Surface, enabled = !busy, compact = true)
            }
            Spacer(Modifier.height(8.dp))
            NovaText(e.text("result.cards") + " · " + e.text("result.cardsHelp"), style = NovaTypeToken.metaQuiet)
            NovaButton(e.text("result.downloadCards"), { onExport("cards") }, Modifier.testTag("emergencyWizard.cards"), symbol = "printer",
                variant = NovaButtonVariant.Surface, enabled = !busy, compact = true)
        }
    }
    item {
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            NovaText(e.text("result.save"), style = NovaTypeToken.cardTitle)
            NovaText(if (canSave) e.text("result.saveHelp") else e.text("result.needsCompany"), style = NovaTypeToken.metaQuiet)
            Spacer(Modifier.height(8.dp))
            NovaButton(if (saved) e.text("result.saved") else e.text("result.save"), onSave, Modifier.testTag("emergencyWizard.save"),
                symbol = if (saved) "checkmark.circle" else "tray.and.arrow.down", variant = if (saved) NovaButtonVariant.Surface else NovaButtonVariant.Primary,
                enabled = canSave && !busy && !saved, compact = true)
        }
    }
    item {
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            NovaText(e.text("step.team"), style = NovaTypeToken.cardTitle)
            plan.teams.roles.forEach { role ->
                Row(Modifier.fillMaxWidth().padding(top = 6.dp)) {
                    NovaText(role.label, Modifier.weight(1f), style = NovaTypeToken.body)
                    NovaText((role.required?.toString() ?: if (plan.teams.combinedRequired != null && role.id != "ilkyardim") e.text("team.shared") else "—") +
                        " · " + e.text("team.assigned") + " ${role.assigned}", style = NovaTypeToken.meta)
                }
            }
        }
    }
    item { NovaText(e.text("result.scenarios"), Modifier.padding(top = 6.dp), style = NovaTypeToken.cardTitle) }
    plan.cards.forEachIndexed { i, card ->
        item(key = "plan" + card.id) {
            val isOpen = card.id in open
            NovaCard(Modifier.fillMaxWidth().testTag("emergencyWizard.row.${card.id}"), padding = 14) {
                Row(Modifier.fillMaxWidth().clickable { onToggle(card.id) }, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    NovaText("${i + 1}", Modifier.width(24.dp), style = NovaTypeToken.metaQuiet)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        NovaText(card.title, style = NovaTypeToken.bodyStrong)
                        NovaText(card.trigger, style = NovaTypeToken.meta)
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            if (card.core) Tag(e.text("cards.core"), NovaColorToken.statusInfoBg.color(), NovaColorToken.statusInfoInk.color())
                            else Tag(card.why.joinToString(", "), NovaColorToken.statusSuccessBg.color(), NovaColorToken.statusSuccessInk.color())
                            Tag(card.mode, NovaColorToken.statusNeutralBg.color(), NovaColorToken.statusNeutralInk.color())
                        }
                    }
                    NovaIcon(if (isOpen) "chevron.up" else "chevron.down", 16.dp, tint = NovaColorToken.textSecondary.color())
                }
                if (isOpen) Column(Modifier.padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("result.before" to card.before, "result.worker" to card.worker, "result.team" to card.team,
                        "result.prohibited" to card.prohibited, "result.after" to card.after).forEach { (key, items) ->
                        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            NovaText(e.text(key), style = NovaTypeToken.label)
                            items.forEach { NovaText("• $it", style = NovaTypeToken.body) }
                        }
                    }
                    NovaText(e.text("result.reentry") + ": " + card.reentry, style = NovaTypeToken.meta)
                    card.siteFields.forEach { (label, value) -> NovaText("$label: " + value.ifEmpty { e.text("result.siteLater") }, style = NovaTypeToken.metaQuiet) }
                }
            }
        }
    }
    item { GapsCard(e.text("summary.gaps"), plan.gaps) }
    item { NovaHelpHint(e.text("result.note")) }
}

/** Saves the plan as a module record: the Word plan goes to the file archive, then a plan version is published (iOS `NovaEmergencyWizardSaver`). */
internal object EmergencyWizardSaver {
    /** The module stores fire / first aid / evacuation / other; the Word plan keeps the exact team names. */
    fun role(id: String) = when (id) {
        "sondurme" -> NovaEmergencyRole.fire
        "ilkyardim" -> NovaEmergencyRole.firstAid
        "koruma" -> NovaEmergencyRole.evacuation
        else -> NovaEmergencyRole.other
    }
    fun isoDay(turkish: String): String {
        val parts = turkish.split(".").mapNotNull { it.trim().toIntOrNull() }
        return if (parts.size == 3) "%04d-%02d-%02d".format(parts[2], parts[1], parts[0]) else ""
    }
    suspend fun save(runtime: NovaRiskWizardRuntime, client: NovaEmergencyClient, company: String, workplace: String?, e: EmergencyWizardView) {
        val plan = runtime.plan()
        val file = runtime.download("docx")
        val draft = NovaFileDraft(title = e.text("file.title"), category = "emergency_plan", note = e.text("file.note"), fileName = file.name,
            fileExtension = "docx", bytes = file.bytes.size, sha256 = NovaFileDraft.sha256(file.bytes))
        val entry = client.files.file(company, draft, file.bytes)
        // Only a filed (scanned and promoted) file may be attached; otherwise the plan is saved and the file stays in Dosyalarım.
        client.publish(company, NovaEmergencyPlanDraft(workplaceId = workplace, preparedOn = isoDay(plan.date), validUntil = isoDay(plan.validUntil),
            team = plan.members.filter { !it.backup }.take(200).map { NovaEmergencyMember(it.name, role(it.roleId), it.contact.ifEmpty { null }) },
            assetId = entry.assetId.takeIf { entry.state.isFiled }))
    }
}
