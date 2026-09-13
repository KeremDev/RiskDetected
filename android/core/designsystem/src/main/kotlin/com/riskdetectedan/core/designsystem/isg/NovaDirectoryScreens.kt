package com.riskdetectedan.core.designsystem.isg

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.util.UUID

private val NovaDirectoryKind.icon: ImageVector get() = when(this) {
    NovaDirectoryKind.workplaces, NovaDirectoryKind.contractors, NovaDirectoryKind.engagements -> Icons.Outlined.Business
    NovaDirectoryKind.departments -> Icons.Outlined.AccountTree
    NovaDirectoryKind.jobs -> Icons.Outlined.WorkOutline
    NovaDirectoryKind.contexts -> Icons.Outlined.History
    else -> Icons.Outlined.PersonOutline
}
@Composable
fun NovaDirectoryDestination(scope: NovaPersonnelScope, kind: NovaDirectoryKind, parent: UUID? = null, client: NovaDirectoryClient, canWrite: Boolean = true, onBack: () -> Unit) {
    key(scope, kind, parent, canWrite) { DirectoryContent(scope, kind, parent, client, canWrite, onBack) }
}
@Composable
private fun DirectoryContent(scope: NovaPersonnelScope, kind: NovaDirectoryKind, parent: UUID?, client: NovaDirectoryClient, canWrite: Boolean, onBack: () -> Unit) {
    var rows by remember { mutableStateOf(emptyList<NovaDirectoryRow>()) }
    var next by remember { mutableStateOf<UUID?>(null) }
    var page by remember { mutableStateOf<UUID?>(null) }
    var parentVersion by remember { mutableLongStateOf(0) }
    var archived by remember { mutableStateOf(false) }
    var refresh by remember { mutableStateOf(UUID.randomUUID()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var editing by remember { mutableStateOf(false) }
    var original by remember { mutableStateOf<NovaDirectoryRow?>(null) }
    var pending by remember { mutableStateOf<NovaDirectoryIntent?>(null) }
    var recovering by remember { mutableStateOf(false) }
    var child by remember { mutableStateOf<Pair<NovaDirectoryKind, UUID>?>(null) }
    if (child != null) {
        val route = child!!
        NovaDirectoryDestination(scope, route.first, route.second, client, canWrite) { child = null }
        return
    }
    if (editing && canWrite) {
        key(original?.id) { DirectoryEditor(scope, kind, parent, parentVersion, original, rows, client, { editing = false; refresh = UUID.randomUUID() }) {
            editing = false; page = null; refresh = UUID.randomUUID()
        } }
        return
    }
    BackHandler(onBack = onBack)
    LaunchedEffect(page, archived, refresh) {
        loading = true; error = null
        try {
            pending = client.pending(scope); currentCoroutineContext().ensureActive()
            val result = client.read(scope, kind, parent, page, archived); currentCoroutineContext().ensureActive()
            rows = if (page == null) result.rows else rows + result.rows.filter { r -> rows.none { it.id == r.id } }
            next = result.next; parentVersion = result.parentVersion ?: 0
        } catch (_: Exception) { currentCoroutineContext().ensureActive(); error = "Kayıtlar yüklenemedi. Erişiminizi ve bağlantınızı kontrol edin." }
        loading = false
    }
    LaunchedEffect(recovering) {
        val intent = pending
        if (canWrite && recovering && intent != null) {
            try { client.save(intent); currentCoroutineContext().ensureActive(); pending = null }
            catch (_: Exception) { currentCoroutineContext().ensureActive(); error = "İşlem henüz doğrulanamadı." }
            recovering = false; refresh = UUID.randomUUID()
        }
    }
    NovaPageSurface {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            DirectoryHeading(kind.title, onBack)
            if (kind.isCatalog) Row(verticalAlignment = Alignment.CenterVertically) {
                NovaText("Arşivdekileri göster", Modifier.weight(1f)); Switch(archived, { archived = it; page = null })
            }
            pending?.let { p -> NovaCard { Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                DirectoryLabel("Bekleyen işlem · ${p.kind.title}", Icons.Outlined.Refresh)
                NovaText("Önceki işlemi doğrulamadan yeni kayıt göndermeyin.")
                NovaButton("Bekleyen işlemi tamamla", { recovering = true }, enabled = canWrite, loading = recovering)
            } } }
            if (!canWrite) NovaText("Salt okunur · kayıt geçmişiniz korunuyor.", style = NovaTypeToken.metaQuiet)
            DirectoryAction(if (kind == NovaDirectoryKind.employers) "İşveren ilişkisini düzenle" else "Yeni kayıt", Icons.Outlined.Add, canWrite && !loading && error == null && pending == null) {
                original = if (kind == NovaDirectoryKind.employers) rows.firstOrNull() else null; editing = true
            }
            error?.let { NovaCard { Column { NovaText(it); DirectoryAction("Tekrar yükle", Icons.Outlined.Refresh) { refresh = UUID.randomUUID() } } } }
            rows.forEach { row -> NovaCard { Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                DirectoryLabel(row.title, kind.icon)
                row.text("code")?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
                row.text("starts_on")?.let { NovaText("$it → ${row.text("ends_before") ?: "Devam ediyor"}", style = NovaTypeToken.metaQuiet) }
                row.text("department_name_snapshot")?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
                if (row.archived) NovaText("Arşivde", style = NovaTypeToken.metaQuiet)
                if (canWrite && (kind.isCatalog || kind == NovaDirectoryKind.engagements)) DirectoryAction("Düzenle", Icons.Outlined.Edit, pending == null) { original = row; editing = true }
                if (kind == NovaDirectoryKind.workplaces) DirectoryAction("Tarihli bağlam", Icons.Outlined.History) { child = NovaDirectoryKind.contexts to row.id }
                if (kind == NovaDirectoryKind.contractors) DirectoryAction("Çalışılan işyerleri", Icons.Outlined.Business) { child = NovaDirectoryKind.engagements to row.id }
            } } }
            if (loading) CircularProgressIndicator()
            if (!loading && error == null && rows.isEmpty()) NovaCard { NovaText("Henüz kayıt yok.") }
            next?.let { cursor -> DirectoryAction("Daha fazla", Icons.Outlined.ExpandMore, !loading) { page = cursor } }
        }
    }
}
private data class DirectoryField(val id: String, val label: String, val choices: NovaDirectoryKind? = null, val nullable: Boolean = false)
private fun directoryFields(kind: NovaDirectoryKind): List<DirectoryField> {
    val name = DirectoryField("name", "Ad / unvan"); val code = DirectoryField("code", "Kod")
    val workplace = DirectoryField("workplace_id", "İşyeri", NovaDirectoryKind.workplaces)
    val org = DirectoryField("organization_id", "Dış firma", NovaDirectoryKind.contractors)
    val start = DirectoryField("starts_on", "Geçerlilik başlangıcı · YYYY-AA-GG")
    return when(kind) {
        NovaDirectoryKind.workplaces -> listOf(name, code, DirectoryField("address", "Adres", nullable = true))
        NovaDirectoryKind.departments -> listOf(name, code, workplace, DirectoryField("parent_id", "Üst departman", NovaDirectoryKind.departments, true))
        NovaDirectoryKind.jobs -> listOf(name, code, DirectoryField("description", "Görev açıklaması", nullable = true))
        NovaDirectoryKind.contractors -> listOf(name, code, DirectoryField("relationship", "İlişki türü"))
        NovaDirectoryKind.engagements -> listOf(org, workplace, start, DirectoryField("ends_before", "Bitiş (hariç) · YYYY-AA-GG", nullable = true), DirectoryField("description", "Yapılan iş", nullable = true))
        NovaDirectoryKind.contexts -> listOf(start, DirectoryField("previous_id", "Önceki dönem", nullable = true), DirectoryField("timezone", "Saat dilimi · ör. Europe/Istanbul"), DirectoryField("jurisdiction", "Mevzuat bölgesi"), DirectoryField("hazard_class", "Tehlike sınıfı"), DirectoryField("industry_code", "Faaliyet kodu", nullable = true), DirectoryField("evidence_note", "Bağlam değişikliğinin dayanağı"))
        NovaDirectoryKind.assignments -> listOf(workplace, DirectoryField("department_id", "Departman", NovaDirectoryKind.departments), DirectoryField("job_role_id", "Görev / unvan", NovaDirectoryKind.jobs), start, DirectoryField("previous_id", "Önceki görevlendirme", nullable = true), DirectoryField("reason", "Değişiklik nedeni · sağlık bilgisi yazmayın", nullable = true))
        NovaDirectoryKind.employers -> listOf(org.copy(label = "İşveren · boş ise ana firma", nullable = true))
    }
}
@Composable
private fun DirectoryEditor(scope: NovaPersonnelScope, kind: NovaDirectoryKind, parent: UUID?, parentVersion: Long, original: NovaDirectoryRow?, history: List<NovaDirectoryRow>, client: NovaDirectoryClient, onBack: () -> Unit, onSaved: () -> Unit) {
    val definition = remember(kind) { directoryFields(kind) }
    var fields by remember { mutableStateOf(original?.fields?.mapValues { (_, v) -> (v as? NovaDirectoryValue.Text)?.value ?: "" }.orEmpty()) }
    var options by remember { mutableStateOf(emptyMap<String, List<NovaDirectoryRow>>()) }
    var cursors by remember { mutableStateOf(emptyMap<String, UUID?>()) }
    var more by remember { mutableStateOf<String?>(null) }
    var expanded by remember { mutableStateOf<String?>(null) }
    var archived by remember { mutableStateOf(original?.archived ?: false) }
    var pending by remember { mutableStateOf<NovaDirectoryIntent?>(null) }
    var submitting by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    BackHandler(enabled = !submitting, onBack = onBack)
    suspend fun load(field: DirectoryField, cursor: UUID?) {
        val target = field.choices ?: if (field.id == "previous_id") kind else return
        val result = client.read(scope, target, if (field.id == "previous_id") parent else null, cursor, false); currentCoroutineContext().ensureActive()
        options = options + (field.id to (if (cursor == null) emptyList() else options[field.id].orEmpty()) + result.rows.filter { it.id != original?.id })
        cursors = cursors + (field.id to result.next)
    }
    LaunchedEffect(Unit) {
        if (kind == NovaDirectoryKind.jobs) fields = fields + ("name" to (original?.text("title") ?: ""))
        if (kind == NovaDirectoryKind.employers) fields = fields + ("organization_id" to (original?.text("employer_org_id") ?: ""))
        if (original == null) fields = fields + mapOf("code" to UUID.randomUUID().toString().take(8), "relationship" to "other")
        if (kind == NovaDirectoryKind.engagements && original == null && parent != null) fields = fields + ("organization_id" to parent.toString())
        try { definition.forEach { field -> load(field, null) } }
        catch (_: Exception) { currentCoroutineContext().ensureActive(); message = "Seçenekler yüklenemedi. Geri dönüp tekrar açabilirsiniz." }
    }
    LaunchedEffect(more) {
        val field = definition.firstOrNull { it.id == more }
        if (field != null) {
            try { load(field, cursors[field.id]) } catch (_: Exception) { currentCoroutineContext().ensureActive(); message = "Diğer kayıtlar yüklenemedi." }
            more = null
        }
    }
    LaunchedEffect(submitting) {
        val intent = pending
        if (submitting && intent != null) {
            try { client.save(intent); currentCoroutineContext().ensureActive(); submitting = false; onSaved() }
            catch (error: Exception) {
                currentCoroutineContext().ensureActive(); submitting = false
                if (error is NovaPersonnelFailure && error.kind in setOf(NovaPersonnelFailure.Kind.validation, NovaPersonnelFailure.Kind.conflict)) {
                    pending = null; message = "Kayıt kabul edilmedi. Bilgileri kontrol edin; kayıt değiştiyse geri dönüp güncel halini yükleyin."
                } else message = "İşlem doğrulanamadı. Bilgileri değiştirmeden aynı işlemi tekrar kontrol edin."
            }
        }
    }
    NovaPageSurface {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            DirectoryHeading(kind.title, onBack, !submitting)
            definition.forEach { field -> NovaCard { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                DirectoryLabel(field.label, field.choices?.icon ?: Icons.Outlined.Edit)
                val fixed = when(field.id) { "relationship" -> listOf("subcontractor" to "Alt işveren", "contractor" to "Yüklenici", "supplier" to "Tedarikçi", "other" to "Diğer"); "hazard_class" -> listOf("low" to "Az tehlikeli", "medium" to "Tehlikeli", "high" to "Çok tehlikeli"); else -> null }
                if (field.choices != null || field.id == "previous_id" || fixed != null) {
                    val selected = fields[field.id].orEmpty()
                    TextButton({ expanded = if (expanded == field.id) null else field.id }, enabled = pending == null) {
                        Text(fixed?.firstOrNull { it.first == selected }?.second ?: options[field.id]?.firstOrNull { it.id.toString() == selected }?.title ?: if (selected.isEmpty()) "Seçilmedi" else "Seçildi")
                        NovaGlyph(Icons.Outlined.ExpandMore, "Seçenekler")
                    }
                    if (expanded == field.id && pending == null) {
                        if (field.nullable) TextButton({ fields = fields + (field.id to ""); expanded = null }) { Text("Seçimi kaldır") }
                        val choices = fixed ?: options[field.id].orEmpty().filter { field.choices != NovaDirectoryKind.departments || it.text("workplace_id") == fields["workplace_id"] }.map { it.id.toString() to (it.title + (it.text("starts_on")?.let { day -> " · $day" } ?: "")) }
                        choices.forEach { (value, label) -> TextButton({
                            fields = fields + (field.id to value)
                            if (field.id == "workplace_id") fields = fields + mapOf("parent_id" to "", "department_id" to "")
                            expanded = null
                        }) { Text(label) } }
                        if (cursors[field.id] != null) TextButton({ more = field.id }, enabled = more == null) { Text("Diğer kayıtlar") }
                    }
                } else OutlinedTextField(fields[field.id].orEmpty(), { fields = fields + (field.id to it) }, enabled = pending == null, modifier = Modifier.fillMaxWidth(), singleLine = true)
            } } }
            if (original != null && kind.isCatalog) Row(verticalAlignment = Alignment.CenterVertically) { NovaText("Arşivle", Modifier.weight(1f)); Switch(archived, { archived = it }, enabled = pending == null) }
            message?.let { NovaText(it) }
            DirectoryAction(if (pending == null) "Kaydet" else "Aynı işlemi tekrar kontrol et", Icons.Outlined.Check, !submitting) {
                if (pending != null) { submitting = true; return@DirectoryAction }
                val body = mutableMapOf<String, NovaDirectoryValue>()
                for (field in definition) {
                    val value = fields[field.id].orEmpty().trim()
                    if (value.isEmpty() && !field.nullable) { message = "${field.label} gerekli."; return@DirectoryAction }
                    body[field.id] = if (value.isEmpty() && field.nullable && field.id !in setOf("description", "reason")) NovaDirectoryValue.Null else NovaDirectoryValue.Text(value)
                }
                if (kind.isCatalog) body["is_archived"] = NovaDirectoryValue.Flag(archived)
                if (kind in setOf(NovaDirectoryKind.contexts, NovaDirectoryKind.assignments)) {
                    if (parent == null) { message = "Kayıt kapsamı bulunamadı."; return@DirectoryAction }
                    body[if (kind == NovaDirectoryKind.contexts) "workplace_id" else "employee_id"] = NovaDirectoryValue.Text(parent.toString())
                }
                val expected = if (kind in setOf(NovaDirectoryKind.contexts, NovaDirectoryKind.assignments)) parentVersion else original?.version ?: 0
                pending = NovaDirectoryIntent(scope, kind, UUID.randomUUID(), UUID.randomUUID(), if (kind == NovaDirectoryKind.employers) parent else original?.id, expected, body)
                submitting = true; message = null
            }
            if (submitting) CircularProgressIndicator()
        }
    }
}
@Composable private fun DirectoryHeading(title: String, onBack: () -> Unit, enabled: Boolean = true) {
    Row(verticalAlignment = Alignment.CenterVertically) { IconButton(onBack, enabled = enabled) { NovaGlyph(Icons.Outlined.ChevronLeft, "Geri") }; NovaText(title, style = NovaTypeToken.screenTitle) }
}
@Composable private fun DirectoryLabel(title: String, icon: ImageVector) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) { NovaGlyph(icon, title); NovaText(title, style = NovaTypeToken.cardTitle) }
}
@Composable private fun DirectoryAction(title: String, icon: ImageVector, enabled: Boolean = true, onClick: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) { NovaGlyph(icon, title); NovaButton(title, onClick, Modifier.weight(1f), enabled = enabled) }
}
