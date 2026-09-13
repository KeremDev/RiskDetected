package com.riskdetectedan.core.designsystem.isg

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import java.util.UUID

@Composable
fun NovaPersonnelDestination(scope: NovaPersonnelScope, companyName: String, client: NovaPersonnelClient, onBack: () -> Unit, directory: NovaDirectoryClient? = null, canWrite: Boolean = true) {
    key(scope, canWrite) { PersonnelContent(scope, companyName, client, onBack, directory, canWrite) }
}
private sealed interface PersonnelRoute {
    data object List: PersonnelRoute
    data object Create: PersonnelRoute
    data class Detail(val id: UUID): PersonnelRoute
    data class Edit(val row: NovaEmployeeRow): PersonnelRoute
    data class Advanced(val id: UUID, val kind: NovaDirectoryKind): PersonnelRoute
}
@Composable
private fun PersonnelContent(scope: NovaPersonnelScope, companyName: String, client: NovaPersonnelClient, onBack: () -> Unit, directory: NovaDirectoryClient?, canWrite: Boolean) {
    var route by remember { mutableStateOf<PersonnelRoute>(PersonnelRoute.List) }
    var refresh by remember { mutableStateOf(UUID.randomUUID()) }
    NovaPageSurface {
        when(val current = route) {
            PersonnelRoute.List -> EmployeeList(scope, companyName, client, refresh, onBack, { route = PersonnelRoute.Create }, { route = PersonnelRoute.Detail(it) }, canWrite)
            PersonnelRoute.Create -> EmployeeEditor(scope, companyName, client, null, { route = PersonnelRoute.List }) { refresh = UUID.randomUUID(); route = PersonnelRoute.Detail(it.id) }
            is PersonnelRoute.Detail -> EmployeeDetail(scope, current.id, client, { route = PersonnelRoute.List }, { route = PersonnelRoute.Edit(it) }, canWrite,
                if (directory == null) null else { kind -> route = PersonnelRoute.Advanced(current.id, kind) })
            is PersonnelRoute.Advanced -> directory?.let { NovaDirectoryDestination(scope, current.kind, current.id, it, canWrite = canWrite) { route = PersonnelRoute.Detail(current.id) } }
            is PersonnelRoute.Edit -> EmployeeEditor(scope, companyName, client, current.row, { route = PersonnelRoute.Detail(current.row.id) }) {
                refresh = UUID.randomUUID(); route = if (it.isArchived) PersonnelRoute.List else PersonnelRoute.Detail(it.id)
            }
        }
    }
}
@Composable
private fun PersonnelHeading(title: String, subtitle: String = "", enabled: Boolean = true, onBack: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        IconButton(onBack, enabled = enabled, modifier = Modifier.testTag("personnel.back")) { NovaGlyph(Icons.Outlined.ChevronLeft, "Geri") }
        Column { NovaText(title, style = NovaTypeToken.screenTitle); if (subtitle.isNotEmpty()) NovaText(subtitle, style = NovaTypeToken.metaQuiet) }
    }
}
@Composable
private fun EmployeeList(scope: NovaPersonnelScope, companyName: String, client: NovaPersonnelClient, refresh: UUID,
    onBack: () -> Unit, onAdd: () -> Unit, onSelect: (UUID) -> Unit, canWrite: Boolean) {
    var rows by remember { mutableStateOf(emptyList<NovaEmployeeRow>()) }
    var query by remember { mutableStateOf("") }
    var archived by remember { mutableStateOf(false) }
    var next by remember { mutableStateOf<UUID?>(null) }
    var requestedPage by remember { mutableStateOf<UUID?>(null) }
    var retry by remember { mutableStateOf(UUID.randomUUID()) }
    var loading by remember { mutableStateOf(true) }
    var failed by remember { mutableStateOf(false) }
    var pending by remember { mutableStateOf<NovaEmployeeIntent?>(null) }
    var pendingChecked by remember { mutableStateOf(false) }
    var reconciling by remember { mutableStateOf(false) }
    BackHandler { onBack() }
    LaunchedEffect(query, archived, requestedPage, refresh, retry) {
        val page = requestedPage
        loading = true; failed = false; pendingChecked = false
        if (page == null) { rows = emptyList(); next = null }
        try {
            delay(180)
            val recovered = client.pending(scope); currentCoroutineContext().ensureActive()
            check(recovered == null || recovered.scope == scope); pending = recovered; pendingChecked = true
            val result = client.employees(scope, query, archived, page); currentCoroutineContext().ensureActive()
            check(result.rows.size <= 50 && result.rows.all { it.ownerID == scope.ownerID && it.companyID == scope.companyID && (archived || !it.isArchived) })
            check(result.rows.map { it.id }.distinct().size == result.rows.size && (result.next == null || result.next == result.rows.lastOrNull()?.id))
            rows = if (page == null) result.rows else (rows + result.rows).distinctBy { it.id }; next = result.next; loading = false
        } catch (_: Exception) { currentCoroutineContext().ensureActive(); failed = true; loading = false }
    }
    LaunchedEffect(reconciling) {
        val intent = pending
        if (!canWrite || !reconciling || intent == null) return@LaunchedEffect
        try {
            val result = client.save(intent); currentCoroutineContext().ensureActive()
            check(result.ownerID == scope.ownerID && result.companyID == scope.companyID && result.operationID == intent.operationID && (intent.employeeID == null || intent.employeeID == result.id))
            check(result.version == (if (intent.action == NovaEmployeeIntent.Action.create) 0 else intent.expectedVersion + 1) && result.isArchived == (intent.action == NovaEmployeeIntent.Action.archive))
            pending = null; reconciling = false; requestedPage = null; retry = UUID.randomUUID()
            if (!result.isArchived) onSelect(result.id)
        } catch (_: Exception) { currentCoroutineContext().ensureActive(); reconciling = false; failed = true; retry = UUID.randomUUID() }
    }
    LazyColumn(Modifier.fillMaxSize().testTag("personnel.list"), contentPadding = PaddingValues(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item { PersonnelHeading("Personeller", companyName, onBack = onBack) }
        item { NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            TextField(query, { query = it; requestedPage = null }, placeholder = { NovaText("Personel ara…") },
                leadingIcon = { NovaGlyph(Icons.Outlined.Search, null) }, textStyle = NovaTypeToken.body.textStyle(),
                modifier = Modifier.fillMaxWidth().testTag("personnel.search"), colors = personnelFieldColors(), singleLine = true)
        } }
        item { Row(verticalAlignment = Alignment.CenterVertically) { Switch(archived, { archived = it; requestedPage = null }, Modifier.testTag("personnel.archived")); NovaText("Arşivdekileri de göster") } }
        pending?.let { saved -> item {
            NovaCard(Modifier.fillMaxWidth().testTag("personnel.pending"), padding = 18) {
                Row { NovaGlyph(Icons.Outlined.Refresh, null); NovaText("Bekleyen personel işlemi", style = NovaTypeToken.cardTitle) }
                NovaText("Önceki işlemin sonucu henüz kesinleşmedi. Aynı işlem anahtarıyla kontrol ederek devam edin.")
                NovaText(saved.name.ifEmpty { "Arşivleme işlemi" }, style = NovaTypeToken.metaQuiet)
                PersonnelAction("Bekleyen işlemi tamamla", Icons.Outlined.Refresh, "personnel.recover", enabled = canWrite && !reconciling, onClick = { reconciling = true })
            }
        } }
        if (!canWrite) item { NovaText("Salt okunur · yeni kayıt ve düzenleme kullanılamıyor.", style = NovaTypeToken.metaQuiet) }
        item { PersonnelAction("Personel Ekle", Icons.Outlined.Add, "personnel.add", enabled = canWrite && pendingChecked && pending == null && !reconciling, onClick = onAdd) }
        if (failed) item { NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText("Personeller yüklenemedi. Lütfen tekrar deneyin."); PersonnelAction("Tekrar dene", Icons.Outlined.Refresh, "personnel.reload", onClick = { retry = UUID.randomUUID() }) } }
        if (!loading && !failed && rows.isEmpty()) item { NovaCard(Modifier.fillMaxWidth(), padding = 18) { NovaText("Henüz personel yok.") } }
        items(rows, key = { it.id }) { row ->
            NovaCard(Modifier.fillMaxWidth().clickable(enabled = pending == null && !reconciling) { onSelect(row.id) }.testTag("personnel.row.${row.id}"), padding = 16) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    NovaGlyph(Icons.Outlined.Person, null, Modifier.size(24.dp))
                    Column(Modifier.weight(1f)) { NovaText(row.name, style = NovaTypeToken.cardTitle); NovaText(row.departmentName ?: "Departman seçilmedi", style = NovaTypeToken.metaQuiet); if (row.isArchived) NovaText("Arşivde", style = NovaTypeToken.metaQuiet) }
                    NovaGlyph(Icons.Outlined.ChevronRight, null)
                }
            }
        }
        if (loading) item { CircularProgressIndicator(Modifier.testTag("personnel.loading")) }
        next?.takeIf { !loading }?.let { cursor -> item { PersonnelAction("Daha fazla göster", Icons.Outlined.ExpandMore, "personnel.more", onClick = { requestedPage = cursor }) } }
        item { Spacer(Modifier.height(24.dp)) }
    }
}
@Composable
private fun EmployeeDetail(scope: NovaPersonnelScope, id: UUID, client: NovaPersonnelClient, onBack: () -> Unit, onEdit: (NovaEmployeeRow) -> Unit, canWrite: Boolean, onDirectory: ((NovaDirectoryKind) -> Unit)?) {
    var row by remember(id) { mutableStateOf<NovaEmployeeRow?>(null) }
    var failed by remember { mutableStateOf(false) }
    var refresh by remember { mutableStateOf(UUID.randomUUID()) }
    BackHandler { onBack() }
    LaunchedEffect(id, refresh) {
        row = null; failed = false
        try {
            val result = client.detail(scope, id); currentCoroutineContext().ensureActive()
            check(result.id == id && result.companyID == scope.companyID && result.ownerID == scope.ownerID); row = result
        } catch (_: Exception) { currentCoroutineContext().ensureActive(); failed = true }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        PersonnelHeading("Personel Detayı", onBack = onBack)
        row?.let { value ->
            NovaCard(Modifier.fillMaxWidth().testTag("personnel.detail"), padding = 18) {
                Row { NovaGlyph(Icons.Outlined.Person, null); Spacer(Modifier.width(8.dp)); NovaText(value.name, style = NovaTypeToken.cardTitle) }
                Spacer(Modifier.height(12.dp))
                Row { NovaGlyph(Icons.Outlined.Business, null); Spacer(Modifier.width(8.dp)); NovaText(value.departmentName ?: "Departman seçilmedi") }
                NovaText(if (value.isArchived) "Arşivde" else "Aktif", style = NovaTypeToken.metaQuiet)
            }
            if (canWrite && !value.isArchived) PersonnelAction("Düzenle", Icons.Outlined.Edit, "personnel.edit", onClick = { onEdit(value) })
            onDirectory?.let { open ->
                PersonnelAction("Görevlendirme geçmişi", Icons.Outlined.History, "personnel.assignments", onClick = { open(NovaDirectoryKind.assignments) })
                PersonnelAction("İşveren ilişkisi", Icons.Outlined.Business, "personnel.employers", onClick = { open(NovaDirectoryKind.employers) })
            }
        } ?: if (failed) { NovaText("Personel yüklenemedi."); PersonnelAction("Tekrar dene", Icons.Outlined.Refresh, "personnel.reload", onClick = { refresh = UUID.randomUUID() }) } else CircularProgressIndicator()
    }
}
@Composable
private fun EmployeeEditor(scope: NovaPersonnelScope, companyName: String, client: NovaPersonnelClient, original: NovaEmployeeRow?, onBack: () -> Unit, onSaved: (NovaEmployeeCommit) -> Unit) {
    var state by remember { mutableStateOf(NovaEmployeeEditorState(name = original?.name ?: "", selectedDepartment = original?.departmentID?.let { id -> original.departmentName?.let { NovaDepartmentRow(id, scope.ownerID, scope.companyID, it) } })) }
    var departments by remember { mutableStateOf(emptyList<NovaDepartmentRow>()) }
    var departmentPage by remember { mutableStateOf<UUID?>(null) }
    var departmentNext by remember { mutableStateOf<UUID?>(null) }
    var departmentsFailed by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var confirmation by remember { mutableStateOf(false) }
    val canLeave = state.phase != NovaEmployeeEditorState.Phase.submitting && state.phase != NovaEmployeeEditorState.Phase.uncertain
    BackHandler { if (canLeave) onBack() }
    LaunchedEffect(state.departmentText, departmentPage) {
        val page = departmentPage; departmentsFailed = false
        if (page == null) { departments = emptyList(); departmentNext = null }
        try {
            delay(180)
            val result = client.departments(scope, state.departmentText, page); currentCoroutineContext().ensureActive()
            check(result.rows.size <= 50 && result.rows.all { it.companyID == scope.companyID && it.ownerID == scope.ownerID })
            check(result.rows.map { it.id }.distinct().size == result.rows.size && (result.next == null || result.next == result.rows.lastOrNull()?.id))
            departments = if (page == null) result.rows else (departments + result.rows).distinctBy { it.id }; departmentNext = result.next
        } catch (_: Exception) { currentCoroutineContext().ensureActive(); departmentsFailed = true }
    }
    LaunchedEffect(state.phase, state.pending) {
        val intent = state.pending
        if (state.phase != NovaEmployeeEditorState.Phase.submitting || intent == null) return@LaunchedEffect
        message = null
        try {
            val result = client.save(intent); currentCoroutineContext().ensureActive()
            state = state.complete(intent, result, scope)
            if (state.phase == NovaEmployeeEditorState.Phase.committed) onSaved(result) else state = state.uncertain(intent, scope)
        } catch (error: Exception) {
            currentCoroutineContext().ensureActive()
            if (error is NovaPersonnelFailure && error.kind != NovaPersonnelFailure.Kind.unavailable) {
                state = state.reject(intent, scope, error.kind in setOf(NovaPersonnelFailure.Kind.denied, NovaPersonnelFailure.Kind.conflict))
                message = when(error.kind) {
                    NovaPersonnelFailure.Kind.selectionRequired -> "Aynı adlı birden fazla departman var. Listeden seçin."
                    NovaPersonnelFailure.Kind.conflict -> "Kayıt değişmiş. Geri dönüp güncel kaydı açın."
                    else -> "İşlem reddedildi. Bilgileri ve erişiminizi kontrol edin."
                }
            } else state = state.uncertain(intent, scope)
        }
    }
    Column(Modifier.fillMaxSize().blur(if (confirmation) 7.dp else 0.dp).verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        PersonnelHeading(if (original == null) "Personel Ekle" else "Personeli Düzenle", companyName, canLeave, onBack)
        NovaCard(Modifier.fillMaxWidth(), padding = 18) {
            Row { NovaGlyph(Icons.Outlined.Person, null); Spacer(Modifier.width(8.dp)); NovaText("Ad soyad", style = NovaTypeToken.cardTitle) }
            TextField(state.name, { state = state.copy(name = it) }, enabled = state.canEdit, placeholder = { NovaText("Ad soyad") }, textStyle = NovaTypeToken.body.textStyle(), colors = personnelFieldColors(), singleLine = true, modifier = Modifier.fillMaxWidth().testTag("personnel.name"))
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 18) {
            Row { NovaGlyph(Icons.Outlined.Business, null); Spacer(Modifier.width(8.dp)); NovaText("Departman · isteğe bağlı", style = NovaTypeToken.cardTitle) }
            state.selectedDepartment?.let { selected -> Row(verticalAlignment = Alignment.CenterVertically) { NovaText(selected.name, Modifier.weight(1f)); TextButton({ state = state.copy(selectedDepartment = null, departmentText = "") }, enabled = state.canEdit) { NovaText("Kaldır") } } } ?: run {
                TextField(state.departmentText, { state = state.copy(departmentText = it); departmentPage = null }, enabled = state.canEdit, placeholder = { NovaText("Departman seç veya yeni ad yaz") }, textStyle = NovaTypeToken.body.textStyle(), colors = personnelFieldColors(), singleLine = true, modifier = Modifier.fillMaxWidth().testTag("personnel.department"))
                NovaText("Boş bırakabilirsiniz. Yeni ad, personelle birlikte kaydedilir.", style = NovaTypeToken.metaQuiet)
                departments.forEach { d -> Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(enabled = state.canEdit) { state = state.copy(selectedDepartment = d, departmentText = "") }.testTag("personnel.department.${d.id}"), verticalAlignment = Alignment.CenterVertically) { NovaGlyph(Icons.Outlined.Business, null); Spacer(Modifier.width(8.dp)); NovaText(d.name, Modifier.weight(1f)); NovaGlyph(Icons.Outlined.Add, null) } }
                departmentNext?.let { cursor -> TextButton({ departmentPage = cursor }, enabled = state.canEdit) { NovaText("Diğer departmanlar") } }
                if (departmentsFailed) NovaText("Departman listesi yüklenemedi. Boş bırakabilir veya yeni ad yazabilirsiniz.", style = NovaTypeToken.metaQuiet)
            }
        }
        message?.let { NovaText(it, Modifier.testTag("personnel.message")) }
        if (state.phase == NovaEmployeeEditorState.Phase.uncertain) {
            NovaText("Kayıt sonucu doğrulanamadı. Yeni kayıt açmadan aynı işlemi kontrol edin.")
            PersonnelAction("Aynı işlemi tekrar kontrol et", Icons.Outlined.Refresh, "personnel.retry", onClick = { state = state.retry(scope) })
        } else {
            PersonnelAction(if (original == null) "Personeli kaydet" else "Değişiklikleri kaydet", Icons.Outlined.Check, "personnel.save", enabled = state.canSubmit, loading = state.phase == NovaEmployeeEditorState.Phase.submitting) { state = state.begin(scope, original) }
            if (original != null) PersonnelAction("Personeli arşivle", Icons.Outlined.Archive, "personnel.archive", enabled = state.canEdit, onClick = { confirmation = true })
        }
        Spacer(Modifier.height(24.dp))
    }
    if (confirmation) Dialog(onDismissRequest = { confirmation = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        val window = (LocalView.current.parent as? DialogWindowProvider)?.window
        DisposableEffect(window) {
            val previous = window?.attributes?.dimAmount
            window?.setDimAmount(.34f)
            onDispose { if (previous != null) window.setDimAmount(previous) }
        }
        NovaPopupSurface(Modifier.fillMaxWidth().padding(14.dp)) {
            NovaText("Personel arşivlensin mi?", style = NovaTypeToken.sectionTitle)
            NovaText("Geçmiş kayıtlar silinmez.")
            PersonnelAction("Arşivle", Icons.Outlined.Archive, "personnel.archive.confirm") { confirmation = false; state = state.begin(scope, original, archive = true) }
            PersonnelAction("Vazgeç", Icons.Outlined.Close, "personnel.archive.cancel") { confirmation = false }
        }
    }
}
@Composable private fun personnelFieldColors() = TextFieldDefaults.colors(focusedContainerColor = NovaColorToken.surface.color(), unfocusedContainerColor = NovaColorToken.surface.color(), disabledContainerColor = NovaColorToken.surface.color())
@Composable
private fun PersonnelAction(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, tag: String, enabled: Boolean = true, loading: Boolean = false, onClick: () -> Unit) {
    // Icons have no colored tile/background; button surface belongs to the action, not glyph.
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        NovaGlyph(icon, null, Modifier.size(22.dp), tint = NovaColorToken.statusSuccessInk.color())
        NovaButton(label, onClick, Modifier.weight(1f).testTag(tag), enabled = enabled, loading = loading)
    }
}
