package com.riskdetectedan.feature.nova

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.NovaModuleEditorOption
import com.riskdetectedan.core.data.nova.NovaModuleEditorRecord
import com.riskdetectedan.core.data.nova.NovaModuleEditorService
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*

/** What a module screen needs to let a recorded entry be edited or removed (iOS `management`). */
class NovaModuleManage(internal val service: NovaModuleEditorService, internal val identity: IsgWorkspaceIdentity,
                       internal val files: NovaFileClient)

/**
 * The record popup's way into the editor (iOS `NovaModuleManageAction`). [onDone] runs once the
 * editor closes, so the list rereads whatever was changed or removed.
 */
@Composable
internal fun NovaModuleManageAction(manage: NovaModuleManage, module: String, company: String, record: String, onDone: () -> Unit) {
    var showing by remember { mutableStateOf(false) }
    NovaButton("Düzenle · Evrak bağla · Sil", { showing = true }, Modifier.testTag("nova.module.manage"),
        variant = NovaButtonVariant.Surface, symbol = "slider.horizontal.3")
    NovaPopup(showing, { showing = false; onDone() }, identifier = "nova.module.editor") {
        if (showing) NovaModuleEditorSheet(manage, module, company, record) { showing = false; onDone() }
    }
}

/** One appointment, emergency plan or drill, reopened for correction (iOS `NovaModuleEditor`). */
@Composable
private fun NovaModuleEditorSheet(manage: NovaModuleManage, module: String, company: String, record: String, onClose: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    var loaded by remember { mutableStateOf<NovaModuleEditorRecord?>(null) }
    val values = remember { mutableStateMapOf<String, JsonElement>() }
    var busy by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        try {
            val result = manage.service.load(manage.identity, module, company, record)
            loaded = result; values.putAll(result.snapshot)
        } catch (cancelled: CancellationException) { throw cancelled } catch (error: Exception) {
            failure = NovaModuleEditorService.message(error)
        }
        busy = false
    }
    fun save(action: String) {
        val data = loaded ?: return
        if (busy) return
        busy = true; failure = null
        coroutines.launch {
            try {
                manage.service.save(manage.identity, module, company, record, data, values.toMap(), action)
                busy = false; onClose()
            } catch (cancelled: CancellationException) { throw cancelled } catch (error: Exception) {
                busy = false; failure = NovaModuleEditorService.message(error)
            }
        }
    }
    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        NovaPageHeading("Kaydı düzenle", onBack = onClose)
        val data = loaded
        if (data != null) {
            NovaText(data.companyName, style = NovaTypeToken.cardTitle)
            NovaCard(Modifier.fillMaxWidth(), padding = 16) {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) { ModuleFields(module, data, values, company, manage.files, !busy) }
            }
            NovaButton("Değişiklikleri kaydet", { save("update") }, Modifier.testTag("nova.module.save"), enabled = !busy,
                loading = busy, symbol = "checkmark")
            if (confirmDelete) {
                NovaText("Kayıt listeden kaldırılacak. İşlem geçmişi korunacak.", style = NovaTypeToken.metaQuiet)
                NovaButton("Kaydı sil", { save("delete") }, Modifier.testTag("nova.module.delete.confirm"), variant = NovaButtonVariant.Danger,
                    enabled = !busy, symbol = "trash")
            } else NovaButton("Kaydı sil", { confirmDelete = true }, Modifier.testTag("nova.module.delete"), variant = NovaButtonVariant.Surface,
                enabled = !busy, symbol = "trash")
        } else if (busy) NovaLoadingView("Kayıt yükleniyor…", Modifier.heightIn(max = 160.dp))
        failure?.let { NovaText(it) }
    }
}

private fun MutableMap<String, JsonElement>.text(key: String): String = when (val value = this[key]) {
    is JsonPrimitive -> if (value.isString) value.content else value.doubleOrNull?.let { if (it % 1.0 == 0.0) it.toLong().toString() else it.toString() }
        ?: value.content
    else -> ""
}

private fun MutableMap<String, JsonElement>.setText(key: String, text: String) { this[key] = if (text.isEmpty()) JsonNull else JsonPrimitive(text) }

@Composable
private fun ModuleFields(module: String, data: NovaModuleEditorRecord, values: MutableMap<String, JsonElement>, company: String,
                         files: NovaFileClient, enabled: Boolean) {
    var chooser by remember { mutableStateOf<String?>(null) }
    @Composable fun field(title: String, key: String, multiline: Boolean = false) =
        NovaTextField(title, values.text(key), { values.setText(key, it) }, identifier = "nova.module.$key", multiline = multiline, enabled = enabled)
    @Composable fun choose(title: String, key: String, items: List<Pair<String, String>>, allowsNone: Boolean) {
        val current = values.text(key)
        NovaChooserButton(title, items.firstOrNull { it.first == current }?.second ?: "Seçin", "nova.module.$key", open = chooser == key) {
            if (enabled) chooser = if (chooser == key) null else key
        }
        if (chooser == key) NovaChooserPanel((if (allowsNone) listOf(NovaChooserOption(null, "Seçin")) else emptyList()) +
            items.map { NovaChooserOption(it.first, it.second) }, current.ifEmpty { null }, "nova.module.$key.options") {
            values.setText(key, it.orEmpty()); chooser = null
        }
    }
    fun options(items: List<NovaModuleEditorOption>) = items.map { it.id to it.name }
    when (module) {
        "emergency_plan" -> {
            choose("İşyeri", "workplace_id", options(data.workplaces), allowsNone = true)
            field("Kapsam", "scope")
            field("Hazırlık tarihi (YYYY-AA-GG)", "prepared_on")
            field("Geçerlilik tarihi (isteğe bağlı)", "valid_until")
            field("Dayanak / açıklama", "review_note", multiline = true)
            TeamFields(values, enabled)
        }
        "drill" -> {
            choose("Acil durum planı", "plan_id", options(data.plans), allowsNone = true)
            field("Planlanan tarih (YYYY-AA-GG)", "planned_on")
            if (values.text("state") == "performed") {
                field("Gerçekleşme tarihi (YYYY-AA-GG)", "performed_on")
                NovaText("Katılımcılar", style = NovaTypeToken.label)
                val selected = (values["participants"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
                data.employees.forEach { employee ->
                    NovaCompanyToggleRow(employee.name, employee.id in selected, enabled) { on ->
                        val list = selected.filter { it != employee.id } + if (on) listOf(employee.id) else emptyList()
                        values["participants"] = JsonArray(list.map(::JsonPrimitive))
                    }
                }
            }
            field("Gözlemler", "observation", multiline = true)
            field("İyileştirmeler", "improvement", multiline = true)
        }
        else -> {
            choose("Personel", "employee_id", options(data.employees), allowsNone = true)
            choose("İşyeri", "scope_workplace_id", options(data.workplaces), allowsNone = true)
            choose("Görev", "kind", listOf("representative" to "Çalışan temsilcisi", "support_staff" to "Destek elemanı",
                "team_member" to "Ekip üyesi", "first_aid" to "İlk yardımcı", "fire_team" to "Yangın ekibi"), allowsNone = false)
            field("Başlangıç tarihi (YYYY-AA-GG)", "starts_on")
            field("Bitiş tarihi (isteğe bağlı)", "ends_before")
            choose("Dayanak", "basis", listOf("elected" to "Seçim", "appointed" to "Atama"), allowsNone = false)
            field("Dayanak açıklaması", "basis_note", multiline = true)
            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                NovaText("Atama yazısı", style = NovaTypeToken.label)
                NovaInlineFileField("personnel_document", company, files, values.text("asset_id"), { values.setText("asset_id", it) })
            }
        }
    }
}

private val teamRoles = listOf("coordinator" to "Koordinatör", "fire" to "Yangın", "first_aid" to "İlk yardım", "evacuation" to "Tahliye", "other" to "Diğer")

/** The plan's team snapshot, edited in place like iOS: name, role and contact per member. */
@Composable
private fun TeamFields(values: MutableMap<String, JsonElement>, enabled: Boolean) {
    val members = (values["team_snapshot"] as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }
    fun store(list: List<JsonObject>) { values["team_snapshot"] = JsonArray(list) }
    fun edit(index: Int, key: String, value: String) = store(members.mapIndexed { i, member ->
        if (i == index) JsonObject(member + (key to JsonPrimitive(value))) else member
    })
    var chooser by remember { mutableStateOf<Int?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        NovaText("Ekip", style = NovaTypeToken.cardTitle)
        members.forEachIndexed { index, member ->
            fun text(key: String) = (member[key] as? JsonPrimitive)?.contentOrNull.orEmpty()
            NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    NovaTextField("Ad soyad", text("full_name"), { edit(index, "full_name", it) }, identifier = "nova.module.team.$index.name", enabled = enabled)
                    NovaChooserButton("Görev", teamRoles.firstOrNull { it.first == text("role") }?.second ?: "Diğer", "nova.module.team.$index.role",
                        open = chooser == index) { if (enabled) chooser = if (chooser == index) null else index }
                    if (chooser == index) NovaChooserPanel(teamRoles.map { NovaChooserOption(it.first, it.second) }, text("role"),
                        "nova.module.team.$index.role.options") { role -> edit(index, "role", role ?: "other"); chooser = null }
                    NovaTextField("İletişim", text("contact"), { edit(index, "contact", it) }, identifier = "nova.module.team.$index.contact", enabled = enabled)
                    NovaButton("Ekipten kaldır", { store(members.filterIndexed { i, _ -> i != index }) }, variant = NovaButtonVariant.Danger,
                        enabled = enabled, symbol = "trash", compact = true)
                }
            }
        }
        NovaButton("Ekip üyesi ekle", { store(members + buildJsonObject { put("full_name", ""); put("role", "other") }) },
            Modifier.testTag("nova.module.team.add"), variant = NovaButtonVariant.Surface, enabled = enabled, symbol = "person.badge.plus")
    }
}
