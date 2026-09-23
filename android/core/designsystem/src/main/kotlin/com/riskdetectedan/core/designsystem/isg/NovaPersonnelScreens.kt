package com.riskdetectedan.core.designsystem.isg

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import java.util.UUID

/** A per-employee panel the host supplies, such as the training status card (iOS `NovaEmployeeLearningCard`). */
typealias NovaEmployeeExtra = @Composable (employee: UUID, canWrite: Boolean) -> Unit

/**
 * Personeller (iOS `NovaPersonnelDestination`): the scope owns every list, search, form and pending-request
 * state. [initialEmployee] opens straight on one person when the caller already knows who.
 */
@Composable
fun NovaPersonnelDestination(scope: NovaPersonnelScope, companyName: String, client: NovaPersonnelClient, onBack: () -> Unit,
                             directory: NovaDirectoryClient? = null, canWrite: Boolean = true, initialEmployee: UUID? = null,
                             employeeExtra: NovaEmployeeExtra? = null) {
    key(scope, canWrite) { PersonnelContent(scope, companyName, client, onBack, directory, canWrite, initialEmployee, employeeExtra) }
}

private sealed interface PersonnelRoute {
    data object List : PersonnelRoute
    data object Create : PersonnelRoute
    data class Detail(val id: UUID) : PersonnelRoute
    data class Edit(val row: NovaEmployeeRow) : PersonnelRoute
    data class Archive(val row: NovaEmployeeRow) : PersonnelRoute
    data class Advanced(val id: UUID, val kind: NovaDirectoryKind) : PersonnelRoute
}

@Composable
private fun PersonnelContent(scope: NovaPersonnelScope, companyName: String, client: NovaPersonnelClient, onBack: () -> Unit,
                             directory: NovaDirectoryClient?, canWrite: Boolean, initialEmployee: UUID?, employeeExtra: NovaEmployeeExtra?) {
    var route by remember { mutableStateOf<PersonnelRoute>(initialEmployee?.let { PersonnelRoute.Detail(it) } ?: PersonnelRoute.List) }
    var refresh by remember { mutableStateOf(UUID.randomUUID()) }
    NovaPageSurface {
        when (val current = route) {
            PersonnelRoute.List -> EmployeeList(scope, companyName, client, refresh, onBack, { route = PersonnelRoute.Create }, { route = PersonnelRoute.Detail(it) }, canWrite)
            PersonnelRoute.Create -> EmployeeEditor(scope, companyName, client, null, { route = PersonnelRoute.List }) {
                refresh = UUID.randomUUID(); route = PersonnelRoute.Detail(it.id)
            }
            is PersonnelRoute.Detail -> EmployeeDetail(scope, current.id, client, companyName, { route = PersonnelRoute.List }, { route = PersonnelRoute.Edit(it) },
                { route = PersonnelRoute.Archive(it) }, canWrite, if (directory == null) null else { kind -> route = PersonnelRoute.Advanced(current.id, kind) },
                employeeExtra)
            is PersonnelRoute.Advanced -> directory?.let {
                NovaDirectoryDestination(scope, current.kind, current.id, it, canWrite = canWrite) { route = PersonnelRoute.Detail(current.id) }
            }
            is PersonnelRoute.Edit -> key("edit-${current.row.id}-${current.row.version}") {
                EmployeeEditor(scope, companyName, client, current.row, { route = PersonnelRoute.Detail(current.row.id) }) {
                    refresh = UUID.randomUUID(); route = if (it.isArchived) PersonnelRoute.List else PersonnelRoute.Detail(it.id)
                }
            }
            is PersonnelRoute.Archive -> key("archive-${current.row.id}-${current.row.version}") {
                EmployeeEditor(scope, companyName, client, current.row, { route = PersonnelRoute.Detail(current.row.id) }, archiveOnOpen = true) {
                    refresh = UUID.randomUUID(); route = PersonnelRoute.List
                }
            }
        }
    }
}

@Composable
private fun PersonnelHeading(title: String, subtitle: String = "", enabled: Boolean = true, backTag: String = "personnel.back",
                             onAdd: (() -> Unit)? = null, onBack: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        if (!LocalNovaPopup.current) NovaBackButton(Modifier.testTag(backTag), enabled = enabled, onClick = onBack)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            NovaText(title, style = NovaTypeToken.screenTitle)
            if (subtitle.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("building.2", 13.dp); NovaText(subtitle, style = NovaTypeToken.metaQuiet)
            }
        }
        if (onAdd != null) NovaButton("Ekle", onAdd, Modifier.testTag("personnel.add"), enabled = enabled, symbol = "plus", compact = true)
    }
}

private fun placement(row: NovaEmployeeRow) = listOfNotNull(row.departmentName, row.jobTitle).joinToString(" · ")

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
    val celebrate = rememberNovaCelebrate()
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
            check(result.ownerID == scope.ownerID && result.companyID == scope.companyID && result.operationID == intent.operationID &&
                (intent.employeeID == null || intent.employeeID == result.id))
            check(result.version == (if (intent.action == NovaEmployeeIntent.Action.create) 0 else intent.expectedVersion + 1) &&
                result.isArchived == (intent.action == NovaEmployeeIntent.Action.archive))
            pending = null; reconciling = false; requestedPage = null; retry = UUID.randomUUID()
            celebrate(personnelSuccess(intent.action))
            if (!result.isArchived) onSelect(result.id)
        } catch (_: Exception) { currentCoroutineContext().ensureActive(); reconciling = false; failed = true; retry = UUID.randomUUID() }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp).padding(top = 4.dp, bottom = 24.dp + novaTabBarInset)
        .testTag("personnel.list"), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        PersonnelHeading("Personeller", companyName, enabled = canWrite && pendingChecked && pending == null && !reconciling,
            onAdd = onAdd, onBack = onBack)
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("magnifyingglass", 18.dp)
                PlainField(query, "Personel ara…", "personnel.search", Modifier.weight(1f)) { query = it; requestedPage = null }
            }
        }
        Row(Modifier.heightIn(min = 28.dp).toggleable(archived, role = Role.Switch) { archived = it; requestedPage = null }.testTag("personnel.archived"),
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon("archivebox", 13.dp)
            NovaText("Arşivdekileri de göster", Modifier.weight(1f), NovaTypeToken.metaQuiet)
            Switch(archived, null, colors = SwitchDefaults.colors(checkedTrackColor = NovaColorToken.accent.color()))
        }
        pending?.let { saved ->
            NovaCard(Modifier.fillMaxWidth(), padding = 18) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon("arrow.clockwise", 22.dp)
                        NovaText("Bekleyen personel işlemi", Modifier.testTag("personnel.pending"), NovaTypeToken.cardTitle)
                    }
                    NovaText("Önceki işlemin sonucu henüz kesinleşmedi. Aynı işlem anahtarıyla kontrol ederek devam edin.")
                    NovaText(saved.name.ifEmpty { "Arşivleme işlemi" }, style = NovaTypeToken.metaQuiet)
                    NovaButton("Bekleyen işlemi tamamla", { reconciling = true }, Modifier.fillMaxWidth().testTag("personnel.recover"), enabled = canWrite,
                        loading = reconciling, symbol = "arrow.clockwise")
                }
            }
        }
        if (!canWrite) NovaText("Salt okunur · yeni kayıt ve düzenleme kullanılamıyor.", style = NovaTypeToken.metaQuiet)
        if (failed) NovaCard(Modifier.fillMaxWidth(), padding = 16) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaText("Personeller yüklenemedi. Lütfen tekrar deneyin.")
                NovaButton("Tekrar dene", { retry = UUID.randomUUID() }, Modifier.testTag("personnel.reload"), variant = NovaButtonVariant.Surface, symbol = "arrow.clockwise")
            }
        }
        if (!loading && !failed && rows.isEmpty()) NovaEmptyState("Henüz personel yok.",
            "Firma personelini ekleyerek eğitim, ekip, zimmet ve diğer İSG kayıtlarında doğrudan seçim yapabilirsiniz.")
        rows.forEach { row ->
            NovaCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(enabled = pending == null && !reconciling) { onSelect(row.id) }
                .testTag("personnel.row.${row.id}"), padding = 16) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    NovaIcon("person", 24.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        NovaText(row.name, style = NovaTypeToken.cardTitle)
                        NovaText(placement(row).ifEmpty { "Departman seçilmedi" }, style = NovaTypeToken.metaQuiet)
                        if (row.isArchived) NovaText("Arşivde", style = NovaTypeToken.metaQuiet)
                    }
                    NovaIcon("chevron.right", 16.dp)
                }
            }
        }
        if (loading) Box(Modifier.fillMaxWidth().testTag("personnel.loading"), contentAlignment = Alignment.Center) { NovaSpinner(NovaColorToken.text.color(), size = 22.dp) }
        next?.takeIf { !loading }?.let { cursor ->
            NovaButton("Daha fazla göster", { requestedPage = cursor }, Modifier.testTag("personnel.more"), variant = NovaButtonVariant.Surface, symbol = "chevron.down")
        }
    }
}

private fun personnelSuccess(action: NovaEmployeeIntent.Action) = when (action) {
    NovaEmployeeIntent.Action.create, NovaEmployeeIntent.Action.restore -> "Personel başarıyla eklendi!"
    NovaEmployeeIntent.Action.edit -> "Personel bilgileri başarıyla güncellendi!"
    NovaEmployeeIntent.Action.archive -> "Personel başarıyla arşivlendi!"
}

@Composable
private fun EmployeeDetail(scope: NovaPersonnelScope, id: UUID, client: NovaPersonnelClient, companyName: String, onBack: () -> Unit,
                           onEdit: (NovaEmployeeRow) -> Unit, onArchive: (NovaEmployeeRow) -> Unit, canWrite: Boolean,
                           onDirectory: ((NovaDirectoryKind) -> Unit)?, employeeExtra: NovaEmployeeExtra?) {
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
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp).padding(top = 4.dp, bottom = 18.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        PersonnelHeading("Personel Detayı", onBack = onBack)
        val value = row
        when {
            value != null -> {
                NovaCard(Modifier.fillMaxWidth().testTag("personnel.detail"), padding = 16) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            NovaIcon("person", 23.dp)
                            NovaSizedText(value.name, 16f, FontWeight.Bold, modifier = Modifier.weight(1f))
                            Box(Modifier.size(9.dp).background((if (value.isArchived) NovaColorToken.statusDangerDot else NovaColorToken.statusSuccessDot).color(), CircleShape)
                                .semantics { contentDescription = if (value.isArchived) "Arşivde" else "Aktif" })
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                            NovaIcon("building.2", 18.dp); NovaText(placement(value).ifEmpty { "Departman seçilmedi" }, style = NovaTypeToken.metaQuiet)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                            NovaIcon("building.2", 15.dp, tint = NovaColorToken.accentInk.color()); NovaText(companyName, style = NovaTypeToken.metaQuiet)
                        }
                    }
                }
                employeeExtra?.invoke(id, canWrite && !value.isArchived)
                if (canWrite) NovaButton(if (value.isArchived) "Yeniden etkinleştir" else "Düzenle", { onEdit(value) }, Modifier.fillMaxWidth()
                    .testTag(if (value.isArchived) "personnel.restore" else "personnel.edit"), symbol = if (value.isArchived) "arrow.uturn.backward" else "pencil")
                onDirectory?.let { open ->
                    NovaButton("Görevlendirme geçmişi", { open(NovaDirectoryKind.assignments) }, Modifier.fillMaxWidth().testTag("personnel.assignments"),
                        variant = NovaButtonVariant.Surface, symbol = "clock.arrow.circlepath")
                    NovaButton("İşveren ilişkisi", { open(NovaDirectoryKind.employers) }, Modifier.fillMaxWidth().testTag("personnel.employers"),
                        variant = NovaButtonVariant.Surface, symbol = "building.2")
                }
                if (canWrite && !value.isArchived) NovaButton("Personeli arşivle", { onArchive(value) }, Modifier.fillMaxWidth().testTag("personnel.detail.archive"),
                    variant = NovaButtonVariant.Danger, symbol = "trash")
            }
            failed -> {
                NovaText("Personel yüklenemedi.")
                NovaButton("Tekrar dene", { refresh = UUID.randomUUID() }, Modifier.testTag("personnel.reload"), symbol = "arrow.clockwise")
            }
            else -> NovaSpinner(NovaColorToken.text.color(), size = 22.dp)
        }
    }
}

@Composable
private fun PlainField(value: String, placeholder: String, tag: String, modifier: Modifier = Modifier, enabled: Boolean = true,
                       capitalization: KeyboardCapitalization = KeyboardCapitalization.Words, onChange: (String) -> Unit) {
    val ink = NovaColorToken.text.color()
    Box(modifier) {
        if (value.isEmpty()) NovaText(placeholder, color = NovaColorToken.textPlaceholder.color())
        BasicTextField(value, onChange, Modifier.fillMaxWidth().testTag(tag).semantics { contentDescription = placeholder }, enabled = enabled, singleLine = true,
            textStyle = novaTextStyle(NovaTypeToken.body).copy(color = ink), cursorBrush = SolidColor(ink),
            keyboardOptions = KeyboardOptions(capitalization = capitalization))
    }
}

@Composable
private fun EmployeeEditor(scope: NovaPersonnelScope, companyName: String, client: NovaPersonnelClient, original: NovaEmployeeRow?, onBack: () -> Unit,
                           archiveOnOpen: Boolean = false, onSaved: (NovaEmployeeCommit) -> Unit) {
    var state by remember { mutableStateOf(NovaEmployeeEditorState(name = original?.name ?: "", selectedDepartment = original?.departmentID?.let { id ->
        original.departmentName?.let { NovaDepartmentRow(id, scope.ownerID, scope.companyID, it) } })) }
    var departments by remember { mutableStateOf(emptyList<NovaDepartmentRow>()) }
    var departmentPage by remember { mutableStateOf<UUID?>(null) }
    var departmentNext by remember { mutableStateOf<UUID?>(null) }
    var departmentsFailed by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var confirmation by remember { mutableStateOf(archiveOnOpen) }
    var jobDraft by remember { mutableStateOf("") }
    val celebrate = rememberNovaCelebrate()
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
            if (state.phase == NovaEmployeeEditorState.Phase.committed) { celebrate(personnelSuccess(intent.action)); onSaved(result) }
            else state = state.uncertain(intent, scope)
        } catch (error: Exception) {
            currentCoroutineContext().ensureActive()
            if (error is NovaPersonnelFailure && error.kind != NovaPersonnelFailure.Kind.unavailable) {
                state = state.reject(intent, scope, error.kind in setOf(NovaPersonnelFailure.Kind.denied, NovaPersonnelFailure.Kind.conflict))
                message = when (error.kind) {
                    NovaPersonnelFailure.Kind.selectionRequired -> "Aynı adlı birden fazla departman var. Listeden seçin."
                    NovaPersonnelFailure.Kind.conflict -> "Kayıt değişmiş. Geri dönüp güncel kaydı açın."
                    else -> "İşlem reddedildi. Bilgileri ve erişiminizi kontrol edin."
                }
            } else state = state.uncertain(intent, scope)
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp).padding(top = 4.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        PersonnelHeading(if (original?.isArchived == true) "Personeli Etkinleştir" else if (original == null) "Personel Ekle" else "Personeli Düzenle",
            companyName, canLeave, onBack = onBack)
        if (original?.isArchived == true) NovaCard(Modifier.fillMaxWidth(), padding = 18) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("person", 24.dp); NovaText(original.name, style = NovaTypeToken.cardTitle)
                }
                NovaText("Personel yeniden etkinleştirilecek. Tarihler ve geçmiş kayıtlar değişmez; gerekirse daha sonra yeni görevlendirme ekleyebilirsiniz.")
            }
        } else {
            NovaCard(Modifier.fillMaxWidth(), padding = 18) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("person", 18.dp)
                    PlainField(state.name, "Ad soyad", "personnel.name", Modifier.weight(1f), enabled = state.canEdit) { state = state.copy(name = it) }
                }
            }
            NovaCard(Modifier.fillMaxWidth(), padding = 18) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon("building.2", 20.dp); NovaText("Departman · isteğe bağlı", style = NovaTypeToken.cardTitle)
                    }
                    val selected = state.selectedDepartment
                    if (selected != null) Row(verticalAlignment = Alignment.CenterVertically) {
                        NovaText(selected.name, Modifier.weight(1f))
                        NovaText("Kaldır", Modifier.novaRowPress(enabled = state.canEdit) { state = state.copy(selectedDepartment = null, departmentText = "") },
                            NovaTypeToken.buttonSm, color = NovaColorToken.accentInk.color())
                    } else {
                        PlainField(state.departmentText, "Departman seç veya yeni ad yaz", "personnel.department", Modifier.fillMaxWidth(),
                            enabled = state.canEdit) { state = state.copy(departmentText = it); departmentPage = null }
                        departments.forEach { d ->
                            Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).novaRowPress(enabled = state.canEdit) {
                                state = state.copy(selectedDepartment = d, departmentText = "")
                            }.testTag("personnel.department.${d.id}"), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                NovaIcon("building.2", 18.dp); NovaText(d.name, Modifier.weight(1f)); NovaIcon("plus", 16.dp)
                            }
                        }
                        departmentNext?.let { cursor ->
                            NovaText("Diğer departmanlar", Modifier.novaRowPress(enabled = state.canEdit) { departmentPage = cursor }, NovaTypeToken.buttonSm,
                                color = NovaColorToken.accentInk.color())
                        }
                        if (departmentsFailed) NovaText("Departman listesi yüklenemedi. Boş bırakabilir veya yeni ad yazabilirsiniz.", style = NovaTypeToken.metaQuiet)
                    }
                }
            }
            NovaCard(Modifier.fillMaxWidth(), padding = 18) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("briefcase", 18.dp)
                    PlainField(jobDraft, "Görev · isteğe bağlı", "personnel.job", Modifier.weight(1f)) { jobDraft = it }
                }
            }
            if (jobDraft.isNotEmpty()) NovaText("Görev alanı tasarım önizlemesidir; henüz kaydedilmez.", style = NovaTypeToken.metaQuiet)
        }
        message?.let { NovaText(it, Modifier.testTag("personnel.message")) }
        if (state.phase == NovaEmployeeEditorState.Phase.uncertain) {
            NovaText("Kayıt sonucu doğrulanamadı. Yeni kayıt açmadan aynı işlemi kontrol edin.")
            NovaButton("Aynı işlemi tekrar kontrol et", { state = state.retry(scope) }, Modifier.fillMaxWidth().testTag("personnel.retry"), symbol = "arrow.clockwise")
        } else {
            NovaButton(if (original?.isArchived == true) "Yeniden etkinleştir" else if (original == null) "Personeli kaydet" else "Değişiklikleri kaydet", {
                val next = state.begin(scope, original, restore = original?.isArchived == true)
                if (next.phase == NovaEmployeeEditorState.Phase.submitting) state = next else message = "Ad soyad alanını kontrol edin."
            }, Modifier.fillMaxWidth().testTag("personnel.save"), enabled = state.canEdit,
                loading = state.phase == NovaEmployeeEditorState.Phase.submitting, symbol = "checkmark")
            if (original != null && !original.isArchived) NovaButton("Personeli arşivle", { confirmation = true }, Modifier.fillMaxWidth().testTag("personnel.archive"),
                variant = NovaButtonVariant.Danger, enabled = state.canEdit, symbol = "archivebox")
        }
    }
    NovaPopup(confirmation, { confirmation = false }, identifier = "personnel.archive.popup") {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            NovaText("Personel arşivlensin mi?", style = NovaTypeToken.sectionTitle)
            NovaText("Geçmiş kayıtlar silinmez.")
            NovaButton("Arşivle", { confirmation = false; state = state.begin(scope, original, archive = true) }, Modifier.fillMaxWidth().testTag("personnel.archive.confirm"),
                variant = NovaButtonVariant.Danger, symbol = "archivebox")
            NovaButton("Vazgeç", { confirmation = false }, Modifier.fillMaxWidth().testTag("personnel.archive.cancel"), variant = NovaButtonVariant.Surface,
                symbol = "chevron.left")
        }
    }
}
