package com.riskdetectedan.core.designsystem.isg

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.util.Locale
import java.util.UUID

/** Catalog forms share the reference canvas/cards; dates appear only in advanced history flows (iOS `NovaDirectoryDestination`). */
@Composable
fun NovaDirectoryDestination(scope: NovaPersonnelScope, kind: NovaDirectoryKind, parent: UUID? = null, client: NovaDirectoryClient, canWrite: Boolean = true, onBack: () -> Unit) {
    key(scope, kind, parent, canWrite) { DirectoryContent(scope, kind, parent, client, canWrite, onBack) }
}

@Composable
private fun DirectoryContent(scope: NovaPersonnelScope, kind: NovaDirectoryKind, parent: UUID?, client: NovaDirectoryClient, canWrite: Boolean, onBack: () -> Unit) {
    val celebrate = rememberNovaCelebrate()
    val inPopup = LocalNovaPopup.current
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
    var query by remember { mutableStateOf("") }
    val term = query.trim().lowercase(Locale.forLanguageTag("tr-TR"))
    val filteredRows = if (term.isEmpty()) rows else rows.filter { term in it.title.lowercase(Locale.forLanguageTag("tr-TR")) }
    if (child != null) {
        val route = child!!
        NovaDirectoryDestination(scope, route.first, route.second, client, canWrite) { child = null }
        return
    }
    if (editing && canWrite) {
        key(original?.id) { DirectoryEditor(scope, kind, parent, parentVersion, original, rows, client, { editing = false; refresh = UUID.randomUUID() }) {
            celebrate(NovaSuccessMessage.recordSaved(kind.title))
            editing = false; page = null; refresh = UUID.randomUUID()
        } }
        return
    }
    BackHandler(onBack = onBack)
    LaunchedEffect(page, archived, refresh) {
        loading = true; error = null; next = null
        if (page == null) { rows = emptyList(); parentVersion = 0 }
        try {
            pending = client.pending(scope); currentCoroutineContext().ensureActive()
            val result = client.read(scope, kind, parent, page, archived); currentCoroutineContext().ensureActive()
            rows = if (page == null) result.rows else rows + result.rows.filter { r -> rows.none { it.id == r.id } }
            next = result.next; parentVersion = result.parentVersion ?: 0
            loading = false
            // A search reaches every page, not just the ones already loaded.
            if (query.isNotBlank() && result.next != null && result.next != page) page = result.next
        } catch (_: Exception) {
            currentCoroutineContext().ensureActive()
            loading = false; error = "Kayıtlar yüklenemedi. Erişiminizi ve bağlantınızı kontrol edin."
        }
    }
    LaunchedEffect(query) {
        val cursor = next
        if (query.isNotBlank() && !loading && cursor != null && cursor != page) page = cursor
    }
    LaunchedEffect(recovering) {
        val intent = pending
        if (canWrite && recovering && intent != null) {
            try {
                client.save(intent); currentCoroutineContext().ensureActive()
                celebrate(NovaSuccessMessage.recordSaved(kind.title))
                pending = null
            } catch (_: Exception) { currentCoroutineContext().ensureActive(); error = "İşlem henüz doğrulanamadı." }
            recovering = false; refresh = UUID.randomUUID()
        }
    }
    NovaPageSurface {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 18.dp, end = 18.dp, top = 4.dp, bottom = 18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            DirectoryHeading(kind.title, onBack, showsBack = !inPopup)
            NovaHelpHint(kind.help)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaCard(Modifier.weight(1f), padding = 12) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon("magnifyingglass", 16.dp)
                        DirectoryInput(query, "Kayıt ara…", "directory.search", Modifier.weight(1f)) { query = it }
                    }
                }
                if (kind.isCatalog) {
                    val shape = RoundedCornerShape(12.dp)
                    Box(Modifier.size(48.dp).clip(shape)
                        .background(if (archived) NovaColorToken.accentSoft.color() else NovaPopupStyle.controlBackground(inPopup), shape)
                        .toggleable(archived, role = Role.Switch) { archived = it; page = null }
                        .semantics { contentDescription = "Arşivdekileri göster" }.testTag("directory.archived"),
                        contentAlignment = Alignment.Center) {
                        NovaIcon("archivebox", 18.dp, tint = if (archived) NovaColorToken.accentInk.color() else NovaColorToken.text.color())
                    }
                }
            }
            pending?.let { p -> NovaCard(Modifier.fillMaxWidth(), padding = 18) { Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                DirectoryLabel("Bekleyen işlem · ${p.kind.title}", "arrow.clockwise")
                NovaText("Önceki işlemi doğrulamadan yeni kayıt göndermeyin.")
                NovaButton("Bekleyen işlemi tamamla", { recovering = true }, enabled = canWrite, loading = recovering, symbol = "arrow.clockwise")
            } } }
            if (!canWrite) NovaText("Salt okunur · kayıt geçmişiniz korunuyor.", style = NovaTypeToken.metaQuiet)
            NovaButton(if (kind == NovaDirectoryKind.employers) "İşveren ilişkisini düzenle" else "Yeni kayıt", {
                original = if (kind == NovaDirectoryKind.employers) rows.firstOrNull() else null; editing = true
            }, Modifier.testTag("directory.add"), enabled = canWrite && !loading && error == null && pending == null, symbol = "plus")
            error?.let { NovaCard(Modifier.fillMaxWidth(), padding = 16) { Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaText(it)
                NovaButton("Tekrar yükle", { refresh = UUID.randomUUID() }, variant = NovaButtonVariant.Surface, symbol = "arrow.clockwise")
            } } }
            filteredRows.forEach { row -> NovaCard(Modifier.fillMaxWidth(), padding = 14) { Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon(kind.symbol, 24.dp)
                    NovaText(row.title, Modifier.weight(1f), NovaTypeToken.cardTitle)
                    if (row.archived) NovaText("Arşivde", style = NovaTypeToken.metaQuiet)
                }
                row.text("starts_on")?.let { NovaText("$it → ${row.text("ends_before") ?: "Devam ediyor"}", style = NovaTypeToken.metaQuiet) }
                row.text("department_name_snapshot")?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
                val editable = canWrite && (kind.isCatalog || kind == NovaDirectoryKind.engagements)
                val link = when (kind) {
                    NovaDirectoryKind.workplaces -> Triple("Bilgi geçmişi", "clock.arrow.circlepath", NovaDirectoryKind.contexts)
                    NovaDirectoryKind.contractors -> Triple("Çalışılan işyerleri", "building.2", NovaDirectoryKind.engagements)
                    else -> null
                }
                if (editable || link != null) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (editable) NovaButton("Düzenle", { original = row; editing = true }, Modifier.weight(1f).testTag("directory.edit.${row.id}"),
                        variant = NovaButtonVariant.Muted, enabled = !loading && error == null && pending == null, symbol = "pencil", compact = true)
                    link?.let { (label, symbol, target) ->
                        NovaButton(label, { child = target to row.id }, Modifier.weight(1f), variant = NovaButtonVariant.Surface, symbol = symbol, compact = true)
                    }
                }
            } } }
            if (loading) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { NovaSpinner(NovaColorToken.accent.color(), size = 22.dp) }
            if (!loading && filteredRows.isEmpty() && error == null) {
                if (query.isEmpty()) NovaEmptyState("Henüz kayıt yok.",
                    "Yeni kayıt ekleyerek bu başlıktaki firma bilgilerini dijital ortamda düzenli ve erişilebilir tutabilirsiniz.")
                else NovaEmptyState("Aramanızla eşleşen kayıt yok.",
                    "Arama ifadesini değiştirerek veya arşiv filtresini kontrol ederek kayda yeniden ulaşabilirsiniz.")
            }
            next?.let { cursor -> NovaButton("Daha fazla", { page = cursor }, variant = NovaButtonVariant.Surface, enabled = !loading, symbol = "chevron.down") }
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

/** Fixed choice sets shown as segmented controls (iOS pickers). */
private fun fixedChoices(field: String): List<Pair<String, String>>? = when (field) {
    "relationship" -> listOf("subcontractor" to "Alt işveren", "contractor" to "Yüklenici", "supplier" to "Tedarikçi", "other" to "Diğer")
    "hazard_class" -> listOf("" to "Seçin", "low" to "Az", "medium" to "Tehlikeli", "high" to "Çok")
    else -> null
}

@Composable
private fun DirectoryEditor(scope: NovaPersonnelScope, kind: NovaDirectoryKind, parent: UUID?, parentVersion: Long, original: NovaDirectoryRow?, history: List<NovaDirectoryRow>, client: NovaDirectoryClient, onBack: () -> Unit, onSaved: () -> Unit) {
    val inPopup = LocalNovaPopup.current
    var fields by remember { mutableStateOf(original?.fields?.mapValues { (_, v) -> (v as? NovaDirectoryValue.Text)?.value ?: "" }.orEmpty()) }
    var options by remember { mutableStateOf(emptyMap<String, List<NovaDirectoryRow>>()) }
    val definition = directoryFields(kind).map { field ->
        if (field.id == "workplace_id" && options["workplace_id"]?.isEmpty() == true) field.copy(nullable = true) else field
    }
    var cursors by remember { mutableStateOf(emptyMap<String, UUID?>()) }
    var more by remember { mutableStateOf<String?>(null) }
    var expanded by remember { mutableStateOf<String?>(null) }
    var archived by remember { mutableStateOf(original?.archived ?: false) }
    var pending by remember { mutableStateOf<NovaDirectoryIntent?>(null) }
    var submitting by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var optionsLoading by remember { mutableStateOf(true) }
    var optionsFailed by remember { mutableStateOf(false) }
    var optionsRefresh by remember { mutableStateOf(0) }
    BackHandler(enabled = !submitting, onBack = onBack)
    suspend fun load(field: DirectoryField, cursor: UUID?) {
        val target = field.choices ?: if (field.id == "previous_id") kind else return
        val result = client.read(scope, target, if (field.id == "previous_id") parent else null, cursor, false); currentCoroutineContext().ensureActive()
        val existing = if (cursor == null) emptyList() else options[field.id].orEmpty()
        options = options + (field.id to (existing + result.rows).distinctBy { it.id })
        cursors = cursors + (field.id to result.next)
    }
    LaunchedEffect(Unit) {
        if (kind == NovaDirectoryKind.jobs) fields = fields + ("name" to (original?.text("title") ?: ""))
        if (kind == NovaDirectoryKind.employers) fields = fields + ("organization_id" to (original?.text("employer_org_id") ?: ""))
        if (original == null) fields = fields + mapOf("code" to UUID.randomUUID().toString().take(8), "relationship" to "other")
        if (kind == NovaDirectoryKind.engagements && original == null && parent != null) fields = fields + ("organization_id" to parent.toString())
    }
    LaunchedEffect(optionsRefresh) {
        optionsLoading = true; optionsFailed = false; message = null
        definition.forEach { field ->
            try { load(field, null) }
            catch (_: Exception) { currentCoroutineContext().ensureActive(); optionsFailed = true; message = "Seçenekler yüklenemedi. Bilgileriniz korunuyor; tekrar yükleyin." }
        }
        optionsLoading = false
    }
    LaunchedEffect(more) {
        val field = definition.firstOrNull { it.id == more }
        if (field != null) {
            try { load(field, cursors[field.id]) } catch (_: Exception) { currentCoroutineContext().ensureActive(); optionsFailed = true; message = "Diğer kayıtlar yüklenemedi. Seçenekleri tekrar yükleyin." }
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
                } else message = "İşlem doğrulanamadı. Bilgileri değiştirmeden aynı işlemi kontrol edin veya geri dönüp bekleyen işlem durumunu yenileyin."
            }
        }
    }
    fun begin() {
        if (pending != null) { submitting = true; return }
        val body = mutableMapOf<String, NovaDirectoryValue>()
        for (field in definition) {
            val value = fields[field.id].orEmpty().trim()
            if (value.isEmpty() && !field.nullable) { message = "${field.label} gerekli."; return }
            body[field.id] = if (value.isEmpty() && field.nullable && field.id !in setOf("description", "reason")) NovaDirectoryValue.Null else NovaDirectoryValue.Text(value)
        }
        val validation = NovaDirectoryFormRules.validation(kind, fields, options, original?.id)
        if (validation != null) { message = validation; return }
        if (kind.isCatalog) body["is_archived"] = NovaDirectoryValue.Flag(archived)
        if (kind in setOf(NovaDirectoryKind.contexts, NovaDirectoryKind.assignments)) {
            if (parent == null) { message = "Kayıt kapsamı bulunamadı."; return }
            body[if (kind == NovaDirectoryKind.contexts) "workplace_id" else "employee_id"] = NovaDirectoryValue.Text(parent.toString())
        }
        val expected = if (kind in setOf(NovaDirectoryKind.contexts, NovaDirectoryKind.assignments)) parentVersion else original?.version ?: 0
        pending = NovaDirectoryIntent(scope, kind, UUID.randomUUID(), UUID.randomUUID(), if (kind == NovaDirectoryKind.employers) parent else original?.id, expected, body)
        submitting = true; message = null
    }
    NovaPageSurface {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 18.dp, end = 18.dp, top = 4.dp, bottom = 18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            DirectoryHeading(kind.title, onBack, enabled = !submitting, showsBack = !inPopup)
            if (kind in setOf(NovaDirectoryKind.contexts, NovaDirectoryKind.assignments)) NovaCard(Modifier.fillMaxWidth(), padding = 16) {
                NovaText("Önceki dönemi seçerseniz bu kayıt başlangıç tarihinde bölünür; eski bilgiler korunur. Bitiş günü döneme dahil değildir.", style = NovaTypeToken.metaQuiet)
            }
            if (kind == NovaDirectoryKind.engagements && original != null) NovaText("Firma, işyeri ve başlangıç değişmez. Bitişi ve açıklamayı düzenleyebilirsiniz.", style = NovaTypeToken.metaQuiet)
            definition.filterNot { it.id == "workplace_id" && options["workplace_id"]?.isEmpty() == true }.forEach { field -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                val fixed = fixedChoices(field.id)
                // A fixed choice names itself in its chooser row.
                if (fixed == null) DirectoryLabel(field.label, field.choices?.symbol ?: "pencil")
                val editable = pending == null && !(kind == NovaDirectoryKind.engagements && original != null && field.id in setOf("organization_id", "workplace_id", "starts_on"))
                if (fixed != null) {
                    val hazard = field.id == "hazard_class"
                    NovaChoiceField(field.label, if (hazard) NovaHazardChoice.placeholder else "${field.label} seçin",
                        if (hazard) "exclamationmark.triangle" else "link",
                        if (hazard) NovaHazardChoice.options else fixed.filter { it.first.isNotEmpty() }.map { NovaChoiceOption(it.first, it.second) },
                        fields[field.id]?.ifEmpty { null }, { value -> fields = fields + (field.id to value.orEmpty()) }, "directory.field.${field.id}",
                        message = if (hazard) NovaHazardChoice.message else null, enabled = editable,
                        // The class may be left open, as the old "Seçin" segment allowed.
                        noneTitle = if (fixed.any { it.first.isEmpty() }) "Seçilmedi" else null)
                } else if (field.choices != null || field.id == "previous_id") {
                    val selected = fields[field.id].orEmpty()
                    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).alpha(if (editable) 1f else 0.5f)
                        .novaRowPress(enabled = editable) { expanded = if (expanded == field.id) null else field.id }.testTag("directory.field.${field.id}"),
                        verticalAlignment = Alignment.CenterVertically) {
                        NovaText(options[field.id]?.firstOrNull { it.id.toString() == selected }?.title ?: if (selected.isEmpty()) "Seçilmedi" else "Seçildi", Modifier.weight(1f))
                        NovaIcon("chevron.down", 16.dp)
                    }
                    if (expanded == field.id && editable) {
                        if (field.nullable) DirectoryOption("Seçimi kaldır", null, "directory.option.${field.id}.none") { fields = fields + (field.id to ""); expanded = null }
                        NovaDirectoryFormRules.allowedOptions(options[field.id].orEmpty(), field.id, fields["workplace_id"], original?.id).forEach { option ->
                            val label = option.title + (option.text("starts_on")?.let { day -> " · $day → ${option.text("ends_before") ?: "Devam ediyor"}" } ?: "")
                            DirectoryOption(label, "checkmark.circle", "directory.option.${field.id}.${option.id}") {
                                fields = NovaDirectoryFormRules.selecting(field.id, option.id.toString(), fields)
                                expanded = null
                            }
                        }
                        if (cursors[field.id] != null) DirectoryOption("Diğer kayıtlar", "chevron.down", "directory.option.${field.id}.more",
                            enabled = more == null && !optionsLoading) { more = field.id }
                    }
                } else {
                    val capitalize = field.id !in setOf("starts_on", "ends_before", "timezone", "code")
                    DirectoryInput(fields[field.id].orEmpty(), field.label, "directory.field.${field.id}", Modifier.fillMaxWidth(), editable,
                        if (capitalize) KeyboardCapitalization.Sentences else KeyboardCapitalization.None) { fields = fields + (field.id to it) }
                }
            } } }
            if (original != null && kind.isCatalog) Row(Modifier.fillMaxWidth().toggleable(archived, enabled = pending == null, role = Role.Switch) { archived = it },
                verticalAlignment = Alignment.CenterVertically) {
                NovaText("Arşivle", Modifier.weight(1f))
                Switch(archived, null, enabled = pending == null, colors = SwitchDefaults.colors(checkedTrackColor = NovaColorToken.accent.color()))
            }
            if (optionsLoading || more != null) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { NovaSpinner(NovaColorToken.accent.color(), size = 22.dp) }
            if (optionsFailed) NovaButton("Seçenekleri tekrar yükle", { optionsRefresh++ }, Modifier.testTag("directory.options.retry"),
                variant = NovaButtonVariant.Surface, enabled = !optionsLoading && pending == null, symbol = "arrow.clockwise")
            message?.let { NovaText(it, Modifier.testTag("directory.error")) }
            NovaButton(if (pending == null) "Kaydet" else "Aynı işlemi tekrar kontrol et", ::begin, Modifier.testTag("directory.save"),
                enabled = pending != null || (!optionsLoading && !optionsFailed && more == null), loading = submitting,
                symbol = if (pending == null) "checkmark" else "arrow.clockwise")
        }
    }
}

@Composable private fun DirectoryHeading(title: String, onBack: () -> Unit, enabled: Boolean = true, showsBack: Boolean = true) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        if (showsBack) NovaBackButton(enabled = enabled, onClick = onBack)
        NovaText(title, style = NovaTypeToken.screenTitle)
    }
}

@Composable private fun DirectoryLabel(title: String, symbol: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        NovaIcon(symbol, 20.dp)
        NovaText(title, style = NovaTypeToken.cardTitle)
    }
}

@Composable private fun DirectoryOption(label: String, symbol: String?, tag: String, enabled: Boolean = true, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).novaRowPress(enabled = enabled, onClick = onClick).testTag(tag),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        if (symbol != null) NovaIcon(symbol, 20.dp)
        NovaText(label, Modifier.weight(1f), color = if (symbol == null) NovaColorToken.textSecondary.color() else NovaColorToken.text.color())
    }
}

@Composable private fun DirectoryInput(value: String, placeholder: String, tag: String, modifier: Modifier = Modifier, enabled: Boolean = true,
                                       capitalization: KeyboardCapitalization = KeyboardCapitalization.Sentences, onChange: (String) -> Unit) {
    val focus = LocalFocusManager.current
    val ink = NovaColorToken.text.color()
    Box(modifier.heightIn(min = 24.dp), contentAlignment = Alignment.CenterStart) {
        if (value.isEmpty()) NovaText(placeholder, color = NovaColorToken.textPlaceholder.color())
        BasicTextField(value, onChange, Modifier.fillMaxWidth().testTag(tag).semantics { contentDescription = placeholder }, enabled = enabled,
            singleLine = true, textStyle = novaTextStyle(NovaTypeToken.body).copy(color = if (enabled) ink else NovaColorToken.textSecondary.color()),
            cursorBrush = SolidColor(ink), keyboardOptions = KeyboardOptions(capitalization = capitalization, autoCorrectEnabled = false, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { focus.clearFocus() }))
    }
}
