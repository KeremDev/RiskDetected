package com.riskdetectedan.feature.nova

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

/** The process-record calls bound to one identity (iOS `NovaProcessService` plus the file client). */
interface NovaProcessClient {
    val companies: suspend () -> List<NovaCompanyOption>
    val files: NovaFileClient
    suspend fun page(kind: String, company: String?, parent: String? = null, query: String = "", offset: Int = 0): NovaProcessPage
    suspend fun record(kind: String, company: String, id: String): NovaProcessRow
    suspend fun visitSummary(company: String?): NovaVisitSummary
    suspend fun attachment(kind: String, record: String, field: String): NovaFileEntry
    suspend fun contents(entry: NovaFileEntry): ByteArray
    suspend fun references(kind: String, company: String, id: String? = null, query: String = "", offset: Int = 0): NovaProcessPage
    suspend fun mutate(company: String, action: String, payload: JsonObject): NovaProcessRow?
}

class NovaServiceProcessClient(private val service: NovaProcessService, private val identity: IsgWorkspaceIdentity,
                               override val companies: suspend () -> List<NovaCompanyOption>, override val files: NovaFileClient) : NovaProcessClient {
    override suspend fun page(kind: String, company: String?, parent: String?, query: String, offset: Int) = service.page(identity, kind, company, parent, query, offset)
    override suspend fun record(kind: String, company: String, id: String) = service.record(identity, kind, company, id)
    override suspend fun visitSummary(company: String?) = service.visitSummary(identity, company)
    override suspend fun attachment(kind: String, record: String, field: String) = service.attachment(identity, kind, record, field)
    override suspend fun contents(entry: NovaFileEntry) = service.contents(identity, entry)
    override suspend fun references(kind: String, company: String, id: String?, query: String, offset: Int) = service.references(identity, kind, company, id, query, offset)
    override suspend fun mutate(company: String, action: String, payload: JsonObject) = service.mutate(identity, company, action, payload)
}

private val longTaskKinds = setOf("site_visit", "annual_work_plan", "board", "completed_drill", "work_permit", "katip_contract", "contractor", "contractor_engagement")

/**
 * One process list (iOS `NovaPilotProcessGate`): İSG-KATİP, yearly plans, board
 * meetings, site visits, work permits and contractors share it.
 */
@Composable
fun NovaProcessGate(client: NovaProcessClient, kind: String, canWrite: Boolean, onBack: () -> Unit, initialCompany: String? = null,
                    parent: String? = null, startInAddMode: Boolean = false) {
    if (kind == "work_permit") {
        NovaWorkPermitLibraryScreen(onBack)
        return
    }
    val spec = remember(kind) { NovaProcessKind.get(kind) }
    val coroutines = rememberCoroutineScope()
    var company by remember { mutableStateOf(initialCompany) }
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var rows by remember { mutableStateOf<List<NovaProcessRow>>(emptyList()) }
    var creating by remember { mutableStateOf(startInAddMode) }
    var selected by remember { mutableStateOf<NovaProcessRow?>(null) }
    var search by remember { mutableStateOf("") }
    var hasMore by remember { mutableStateOf(false) }
    var visitSummary by remember { mutableStateOf<NovaVisitSummary?>(null) }
    var busy by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    var choosingCompany by remember { mutableStateOf(false) }
    suspend fun load(more: Boolean = false) {
        val scope = company
        busy = true; failure = null
        if (!more) visitSummary = null
        try {
            if (companies.isEmpty()) companies = client.companies()
            val page = client.page(kind, scope, parent, search, if (more) rows.size else 0)
            if (company != scope) return
            rows = if (more) rows + page.rows else page.rows; hasMore = page.hasMore
            if (kind == "site_visit") { val summary = client.visitSummary(scope); if (company == scope) visitSummary = summary }
        } catch (error: Exception) { failure = NovaProcessService.message(error) } finally { busy = false }
    }
    val close: () -> Unit = { if (startInAddMode) onBack() else { creating = false; selected = null; coroutines.launch { load() } } }
    val open = selected
    if (open != null) { NovaProcessEditor(client, kind, open.companyId, parent, open.id, canWrite, close); return }
    if (creating) {
        val chosen = company
        if ((parent != null || initialCompany != null) && chosen != null) NovaProcessEditor(client, kind, chosen, parent, null, canWrite, close)
        else NovaCompanyCreateFlow(spec.title, client.companies, { selectedCompany -> client.page(kind, selectedCompany) }, onClose = close) { _, selectedCompany ->
            NovaProcessEditor(client, kind, selectedCompany, parent, null, canWrite, close)
        }
        return
    }
    LaunchedEffect(company) { load() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).padding(bottom = novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaListHeading(spec.title, onBack, actionBelow = true) {
            NovaListActionButton("Ekle", "plus", identifier = "process.add", enabled = canWrite) { creating = true }
        }
        NovaListHint(spec.help)
        if (parent == null && initialCompany == null) {
            NovaChooserButton("Firma", companies.firstOrNull { it.id == company }?.name ?: "Tüm firmalar", "process.company", open = choosingCompany) {
                choosingCompany = !choosingCompany
            }
            if (choosingCompany) NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm firmalar")) + companies.map { NovaChooserOption(it.id, it.name) }, company,
                "process.company.options") { company = it; choosingCompany = false }
        }
        visitSummary?.takeIf { kind == "site_visit" }?.let { summary ->
            NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            NovaIcon("figure.walk", 14.dp); NovaText("${summary.visits}", style = NovaTypeToken.cardTitle)
                        }
                        NovaText("Toplam ziyaret", style = NovaTypeToken.meta)
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            NovaIcon("clock", 14.dp); NovaText(summary.recordedMinutes?.let { "$it dk" } ?: "—", style = NovaTypeToken.cardTitle)
                        }
                        NovaText("${summary.timedVisits} kayıtta süre belirtilmiş", style = NovaTypeToken.meta)
                    }
                }
            }
        }
        NovaSearchCapsule(search, "Kayıt ara", "process.search") { search = it }
        LaunchedEffect(search) { kotlinx.coroutines.delay(350); load() }
        NovaListSectionHeading(spec.title, "${rows.size}${if (hasMore) "+" else ""} kayıt")
        if (busy && rows.isEmpty()) NovaLoadingView("Yükleniyor…", Modifier.heightIn(max = 200.dp))
        failure?.let {
            NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color())
            NovaButton("Yeniden dene", { coroutines.launch { load() } }, variant = NovaButtonVariant.Surface, symbol = "arrow.clockwise")
        }
        if (rows.isEmpty() && !busy && failure == null) NovaEmptyState(spec.emptyTitle, spec.emptyMessage)
        NovaListEntrance(rows.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                rows.forEachIndexed { index, row ->
                    NovaCard(Modifier.fillMaxWidth().novaRowEntrance(index).clip(RoundedCornerShape(22.dp)).novaRowPress { selected = row }
                        .testTag("process.row.${row.id}"), padding = 16) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            NovaText(row.title.replace("[\"", "").replace("\"]", ""), style = NovaTypeToken.cardTitle)
                            NovaText("${row.companyName} · ${NovaDay.label(row.date.take(10))}", style = NovaTypeToken.meta)
                            if (kind == "site_visit") {
                                row.values["duration_minutes"].novaText().takeIf { it.isNotEmpty() }?.let { NovaText("$it dk", style = NovaTypeToken.meta) }
                                row.values["responsible_contact"].novaText().takeIf { it.isNotEmpty() }?.let { NovaText("Görüşülen: $it", style = NovaTypeToken.meta) }
                            }
                            row.values["state"].novaText().takeIf { it.isNotEmpty() }?.let { state ->
                                NovaText(spec.fields.firstOrNull { it.id == "state" }?.choices?.get(state) ?: mapOf("active" to "Aktif", "closed" to "Kapalı")[state] ?: state,
                                    style = NovaTypeToken.meta)
                            }
                            row.childSummary?.let { NovaText("${it.total} alt kayıt · ${it.open} açık · ${it.overdue} gecikmiş", style = NovaTypeToken.meta) }
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                NovaText("Aç / Düzenle", style = NovaTypeToken.meta); NovaIcon("chevron.right", 10.dp)
                            }
                        }
                    }
                }
            }
        }
        if (hasMore) NovaButton("Daha fazla", { coroutines.launch { load(more = true) } }, variant = NovaButtonVariant.Surface, symbol = "chevron.down", enabled = !busy)
    }
}

private val scopeTypes = setOf("workplaces", "employee", "organizations")
private val fileTypes = setOf("file", "photo", "pdf", "photos")

private fun fieldSymbol(field: NovaProcessField) = when (field.type) {
    "choice" -> "list.bullet.circle"; "workplaces", "organizations" -> "building.2"; "employees" -> "person.2"; "date" -> "calendar"
    "datetime" -> "calendar.badge.clock"; "multiline", "lines" -> "text.alignleft"; "number" -> "number"; "file", "photo" -> "paperclip"
    else -> "pencil.line"
}

/** The heading a filed document is tagged with in Dosyalarım, per kind. */
private fun fileCategory(kind: String) = when (kind) {
    "katip_contract" -> "contract"; "work_permit" -> "permit_form"; "board", "board_decision" -> "board_document"
    "contractor", "contractor_engagement" -> "contractor_document"; else -> "other"
}

private fun kindSymbol(kind: String) = when (kind) {
    "katip_contract" -> "signature"; "annual_work_plan" -> "calendar"; "annual_work_item" -> "checkmark.circle"; "board" -> "person.3"
    "board_decision" -> "checkmark.seal"; "site_visit" -> "figure.walk"; "approved_notebook" -> "book.closed"; "site_observation" -> "eye"
    "work_permit" -> "doc.badge.gearshape"; "contractor" -> "building.2.crop.circle"; else -> "briefcase"
}

/** One process record: the visit wizard, the four-step create task, or the full form (iOS `NovaProcessEditor`). */
@Composable
fun NovaProcessEditor(client: NovaProcessClient, kind: String, company: String, parent: String?, record: String?, canWrite: Boolean, onDone: () -> Unit) {
    val spec = remember(kind) { NovaProcessKind.get(kind) }
    val coroutines = rememberCoroutineScope()
    val context = LocalContext.current
    var row by remember { mutableStateOf<NovaProcessRow?>(null) }
    var catalogue by remember { mutableStateOf<NovaProcessPage?>(null) }
    var values by remember { mutableStateOf<Map<String, JsonElement>>(emptyMap()) }
    var document by remember { mutableStateOf("") }
    var relatedKind by remember { mutableStateOf("") }
    var relatedId by remember { mutableStateOf("") }
    var relatedTitle by remember { mutableStateOf("") }
    var choosingRelated by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    var deletePrompt by remember { mutableStateOf(false) }
    var children by remember { mutableStateOf(false) }
    var cancelling by remember { mutableStateOf(false) }
    var cancelReason by remember { mutableStateOf("") }
    var visitStep by remember { mutableIntStateOf(0) }
    var processStep by remember { mutableIntStateOf(0) }
    var saved by remember { mutableStateOf(false) }
    fun text(key: String): String = when (val value = values[key]) {
        is JsonArray -> value.joinToString("\n") { it.novaText() }
        else -> value.novaText()
    }
    fun set(key: String, value: JsonElement) { values = values + (key to value) }
    val automaticDeadline = kind == "completed_drill" || (kind == "personnel_certificate" && text("certificate_kind") == "first_aid")
    val visibleFields = when {
        kind == "completed_drill" || kind == "personnel_certificate" -> spec.fields.filter { field ->
            when (field.id) { "valid_until" -> !automaticDeadline || text("due_override") == "true"; "due_override" -> automaticDeadline; else -> true }
        }
        kind == "board" -> spec.fields.filter { it.id !in setOf("applicability", "state", "held_on", "cancelled_reason") && (it.id != "initial_decisions" || record == null) }
        else -> spec.fields
    }
    val valid = run {
        if (kind == "personnel_certificate" && (!automaticDeadline || text("due_override") == "true") && text("valid_until").isEmpty()) return@run false
        if (kind == "site_visit" && text("duration_minutes").isNotEmpty() && text("duration_minutes").toIntOrNull()?.let { it in 1..1440 } != true) return@run false
        spec.fields.filter { it.required && !(it.type == "workplaces" && catalogue?.workplaces?.isEmpty() == true) }.all { field ->
            when (val value = values[field.id]) { is JsonArray -> value.isNotEmpty(); else -> value.novaText().isNotBlank() }
        }
    }
    LaunchedEffect(kind, company, record) {
        loading = true
        try {
            catalogue = client.page(kind, company, parent)
            if (record != null) {
                val loaded = client.record(kind, company, record)
                row = loaded; values = loaded.values; document = loaded.documentId.orEmpty()
                relatedKind = loaded.relatedKind.orEmpty(); relatedId = loaded.relatedId.orEmpty()
                val related = loaded.relatedId
                if (related != null && relatedKind.isNotEmpty()) {
                    relatedTitle = runCatching { client.references(relatedKind, company, related).rows.firstOrNull()?.title }.getOrNull()
                        ?: "Bağlı kayıt artık erişilebilir değil. Bağlantıyı değiştirebilir veya kaldırabilirsiniz."
                }
            } else {
                val start = mutableMapOf<String, JsonElement>()
                spec.fields.forEach { field ->
                    start[field.id] = when (field.type) { "employees", "photos" -> JsonArray(emptyList()); "bool" -> JsonPrimitive(false); else -> JsonPrimitive("") }
                }
                val today = NovaDay.today()
                listOf("starts_on", "planned_on", "visited_on", "held_on", "issued_on").filter { key -> spec.fields.any { it.id == key } }.forEach { start[it] = JsonPrimitive(today) }
                if (kind == "completed_drill") { start["drill_type"] = JsonPrimitive("emergency"); start["announcement"] = JsonPrimitive("announced") }
                if (kind == "personnel_certificate") {
                    start["certificate_kind"] = JsonPrimitive("first_aid"); start["title"] = JsonPrimitive("İlk Yardım Belgesi")
                    parent?.let { start["employee_id"] = JsonPrimitive(it) }
                }
                if (kind == "approved_notebook") start["title"] = JsonPrimitive("Onaylı Defter")
                if (kind == "annual_work_plan") start["plan_year"] = JsonPrimitive(LocalDate.now().year.toString())
                if (kind == "board") {
                    // No planning workflow: a board record is a meeting that already happened.
                    start["applicability"] = JsonPrimitive("mandatory"); start["state"] = JsonPrimitive("held"); start["held_on"] = JsonPrimitive(today)
                } else if (spec.fields.any { it.id == "state" }) start["state"] = JsonPrimitive(if (kind == "board_decision") "open" else "planned")
                if (kind == "work_permit") start["template_code"] = JsonPrimitive("general")
                val parentKey = spec.parentKey
                if (parentKey != null && parent != null) start[parentKey] = JsonPrimitive(parent)
                if (kind == "contractor_engagement" && parent != null) start["organization_id"] = JsonPrimitive(parent)
                // One workplace is not a choice.
                catalogue?.workplaces?.singleOrNull()?.let { only -> if (spec.fields.any { it.id == "workplace_id" }) start["workplace_id"] = JsonPrimitive(only.id) }
                values = start
            }
        } catch (error: Exception) { failure = NovaProcessService.message(error) }
        loading = false
    }
    // A certificate's default title follows its kind until the expert writes their own.
    LaunchedEffect(text("certificate_kind")) {
        if (kind != "personnel_certificate" || row != null) return@LaunchedEffect
        val defaults = mapOf("first_aid" to "İlk Yardım Belgesi", "myk" to "MYK Belgesi", "custom" to "")
        val current = text("title")
        if (current.isEmpty() || current in defaults.values) set("title", JsonPrimitive(defaults[text("certificate_kind")].orEmpty()))
    }
    fun payload(): JsonObject {
        val selected = mutableMapOf<String, JsonElement>()
        spec.fields.forEach { field ->
            val value = values[field.id] ?: JsonNull
            selected[field.id] = when {
                field.type == "lines" -> JsonArray(text(field.id).split("\n").map { it.trim() }.filter { it.isNotEmpty() }.map(::JsonPrimitive))
                value.novaText().isEmpty() && field.type !in setOf("employees", "photos", "bool") && value !is JsonArray -> JsonNull
                else -> value.novaRpc()
            }
        }
        if (automaticDeadline && text("due_override") != "true") selected["valid_until"] = JsonNull
        spec.parentKey?.let { key -> selected[key] = values[key]?.novaRpc() ?: JsonNull }
        if (kind == "board") {
            if (text("state") == "held") selected["held_on"] = selected["planned_on"] ?: JsonNull else { selected["held_on"] = JsonNull; selected["attendance"] = JsonNull }
            if (text("state") != "cancelled") selected["cancelled_reason"] = JsonNull
        }
        if (kind == "annual_work_item") {
            if (text("state") != "performed") selected["performed_on"] = JsonNull
            if (text("state") != "carried_over") selected["carry_over_reason"] = JsonNull
        }
        return buildJsonObject {
            put("kind", kind); put("id", row?.id?.let(::JsonPrimitive) ?: JsonNull); put("expected", row?.expected?.let(::JsonPrimitive) ?: JsonNull)
            put("values", JsonObject(selected)); put("related_kind", relatedKind.ifEmpty { null }?.let(::JsonPrimitive) ?: JsonNull)
            put("related_id", relatedId.ifEmpty { null }?.let(::JsonPrimitive) ?: JsonNull); put("document_id", document.ifEmpty { null }?.let(::JsonPrimitive) ?: JsonNull)
        }
    }
    val isLongTask = kind in longTaskKinds && kind != "site_visit"
    val usesGenericWizard = record == null && isLongTask
    fun save() = coroutines.launch {
        busy = true; failure = null
        try {
            client.mutate(company, "save", payload())
            if (kind == "site_visit" || usesGenericWizard) saved = true else onDone()
        } catch (error: Exception) { failure = NovaProcessService.message(error) }
        busy = false
    }
    fun remove() = coroutines.launch {
        busy = true; failure = null
        try { client.mutate(company, "delete", payload()); onDone() } catch (error: Exception) { failure = NovaProcessService.message(error) }
        busy = false
    }
    fun export(excel: Boolean) = coroutines.launch {
        busy = true; failure = null
        try {
            val snapshot = client.mutate(company, "export", payload()) ?: throw NovaProcessException("UNAVAILABLE")
            if (excel) novaShareFile(context, NovaProcessExport.xlsx(snapshot, spec), NovaProcessExport.fileName(snapshot, spec, "xlsx"),
                NovaXlsx.MIME)
            else novaShareFile(context, NovaProcessExport.pdf(snapshot, spec), NovaProcessExport.fileName(snapshot, spec, "pdf"), "application/pdf")
        } catch (error: Exception) { failure = NovaProcessService.message(error) }
        busy = false
    }
    fun openAttachment(field: String, record: String) = coroutines.launch {
        busy = true; failure = null
        try {
            val entry = client.attachment(kind, record, field)
            val bytes = client.contents(entry)
            val extension = entry.fileExtension.lowercase()
            novaShareFile(context, bytes, entry.fileName.ifEmpty { "${entry.title}.$extension" },
                android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "application/octet-stream")
        } catch (error: Exception) { failure = NovaProcessService.message(error) }
        busy = false
    }
    val childKind = spec.child
    val loadedRow = row
    if (children && childKind != null && loadedRow != null) {
        NovaProcessGate(client, childKind, canWrite, onBack = { children = false }, initialCompany = company, parent = loadedRow.id)
        return
    }
    val fieldContext = ProcessFieldContext(kind, company, client, loadedRow, busy, ::text, { key -> values[key] }, ::set, { field, id -> openAttachment(field, id) })
    when {
        kind == "site_visit" && saved -> NovaTaskSuccessView(if (record == null) "Saha ziyareti kaydedildi" else "Saha ziyareti güncellendi",
            "Ziyaret bilgileri ve eklediğiniz kanıtlar firma kaydına işlendi.", "Ziyaretlere dön", onDone)
        usesGenericWizard && saved -> NovaTaskSuccessView("${spec.title} kaydedildi", "Kayıt firma kapsamına eklendi ve ilgili listede kullanıma hazır.", "Listeye dön", onDone)
        kind == "site_visit" -> {
            val stepTitle = listOf("İşyeri", "Tarih ve süre", "Ziyaret ayrıntıları", "Dosya ve kontrol")[visitStep]
            val stepValid = when (visitStep) {
                0 -> catalogue?.workplaces?.isEmpty() == true || text("workplace_id").isNotEmpty()
                1 -> text("visited_on").isNotEmpty() && (text("duration_minutes").isEmpty() || text("duration_minutes").toIntOrNull()?.let { it in 1..1440 } == true)
                2 -> text("expert_note").isNotBlank()
                else -> valid
            }
            NovaModuleTask(if (record == null) "Saha ziyareti ekle" else "Saha ziyaretini düzenle", visitStep + 1, 4, stepTitle,
                if (visitStep == 3) "Ziyareti kaydet" else "Devam", if (visitStep == 3) "checkmark" else "arrow.right", busy,
                onBack = { failure = null; if (visitStep > 0) visitStep-- else onDone() },
                onPrimary = {
                    failure = null
                    when {
                        !stepValid -> failure = when (visitStep) {
                            0 -> "Ziyaretin yapıldığı işyerini seçin."; 1 -> "Süre girildiğinde 1 ile 1440 dakika arasında olmalıdır."; else -> "Ziyaret notunu yazın."
                        }
                        visitStep < 3 -> visitStep++
                        else -> save()
                    }
                }, failure = failure) {
                val loadedCatalogue = catalogue
                if (loading) NovaLoadingView("Ziyaret formu hazırlanıyor…", Modifier.heightIn(max = 240.dp))
                else if (loadedCatalogue == null) NovaTaskErrorSummary(failure ?: "Ziyaret formu hazırlanamadı.")
                else when (visitStep) {
                    0 -> {
                        NovaText(if (loadedCatalogue.workplaces.isEmpty()) "Firma kapsamı" else "İşyeri", style = NovaTypeToken.sectionTitle)
                        NovaHelpHint(if (loadedCatalogue.workplaces.isEmpty()) "Ziyaret seçili firma kapsamında kaydedilecek." else "Ziyaretin yapıldığı işyerini seçin. Bu seçim sonraki adımlara otomatik taşınır.")
                        if (loadedCatalogue.workplaces.isNotEmpty()) spec.fields.firstOrNull { it.id == "workplace_id" }?.let { ProcessFieldRow(it, loadedCatalogue, fieldContext) }
                    }
                    1 -> {
                        NovaText("Tarih, saat ve süre", style = NovaTypeToken.sectionTitle)
                        spec.fields.firstOrNull { it.id == "visited_on" }?.let { ProcessFieldRow(it, loadedCatalogue, fieldContext) }
                        NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                            FieldIcon("clock") {
                                NovaTextField("Ziyaret süresi (dakika)", text("duration_minutes"), { value -> set("duration_minutes", JsonPrimitive(value.filter(Char::isDigit))) },
                                    identifier = "process.visit.duration", placeholder = "Örn. 60", keyboardType = KeyboardType.Number)
                            }
                        }
                        NovaText("Saat bilgisi dosya zaman çizelgesinde korunur; süreyi bilmiyorsanız boş bırakabilirsiniz.", style = NovaTypeToken.metaQuiet)
                    }
                    2 -> {
                        NovaText("Ziyaret ayrıntıları", style = NovaTypeToken.sectionTitle)
                        spec.fields.filter { it.id in setOf("expert_note", "location_note", "responsible_contact") }.forEach { ProcessFieldRow(it, loadedCatalogue, fieldContext) }
                    }
                    else -> {
                        NovaText("Dosya ve kontrol", style = NovaTypeToken.sectionTitle)
                        NovaHelpHint("Fotoğraf veya belge eklemek isteğe bağlıdır. Kaydetmeden önce özet bilgileri kontrol edin.")
                        spec.fields.firstOrNull { it.id == "visit_asset_id" }?.let { ProcessFieldRow(it, loadedCatalogue, fieldContext) }
                        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                            Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                                NovaText("Ziyaret özeti", style = NovaTypeToken.bodyStrong)
                                SummaryRow(if (loadedCatalogue.workplaces.isEmpty()) "Firma" else "İşyeri", loadedCatalogue.workplaces.firstOrNull { it.id.equals(text("workplace_id"), true) }?.name ?: if (loadedCatalogue.workplaces.isEmpty()) "Firma geneli" else "—")
                                SummaryRow("Tarih", text("visited_on").ifEmpty { null }?.let(NovaDay::label) ?: "—")
                                SummaryRow("Süre", text("duration_minutes").ifEmpty { null }?.let { "$it dk" } ?: "Belirtilmedi")
                                SummaryRow("Görüşülen kişi", text("responsible_contact").ifEmpty { "Belirtilmedi" })
                            }
                        }
                    }
                }
            }
        }
        usesGenericWizard -> NovaModuleTask(spec.title, processStep + 1, 4, listOf("Kapsam", "Kayıt bilgileri", "Dosya", "Kontrol")[processStep],
            if (processStep == 3) "Kaydet" else "Devam", if (processStep == 3) "checkmark" else "arrow.right", busy,
            onBack = { failure = null; if (processStep > 0) processStep-- else onDone() },
            onPrimary = {
                failure = null
                when {
                    processStep == 0 && !visibleFields.filter { it.type in scopeTypes && it.required && !(it.type == "workplaces" && catalogue?.workplaces?.isEmpty() == true) }.all { text(it.id).isNotEmpty() } -> failure = "Kapsam seçimini tamamlayın."
                    processStep == 3 && !valid -> failure = "Zorunlu alanları ve tarihleri kontrol edin."
                    processStep == 3 -> save()
                    else -> processStep++
                }
            }, failure = failure) {
            val loadedCatalogue = catalogue
            if (loading) NovaLoadingView("Form hazırlanıyor…", Modifier.heightIn(max = 240.dp))
            else if (loadedCatalogue == null) NovaTaskErrorSummary(failure ?: "Form hazırlanamadı.")
            else when (processStep) {
                0 -> {
                    NovaText("Kapsam", style = NovaTypeToken.sectionTitle)
                    NovaHelpHint("Firma seçimi korunur; işyeri ve ilgili kapsam sonraki adımlara otomatik taşınır.")
                    visibleFields.filter { it.type in scopeTypes && !(it.type == "workplaces" && loadedCatalogue.workplaces.isEmpty()) }.forEach { ProcessFieldRow(it, loadedCatalogue, fieldContext) }
                    if (visibleFields.none { it.type in scopeTypes && !(it.type == "workplaces" && loadedCatalogue.workplaces.isEmpty()) }) NovaFormValueRow("Firma kapsamı", "building.2") { NovaText("Seçili firma", style = NovaTypeToken.bodyStrong) }
                }
                1 -> {
                    NovaText("Kayıt bilgileri", style = NovaTypeToken.sectionTitle)
                    visibleFields.filter { it.type !in scopeTypes && it.type !in fileTypes }.forEach { ProcessFieldRow(it, loadedCatalogue, fieldContext) }
                }
                2 -> {
                    NovaText("Dosya ve kanıt", style = NovaTypeToken.sectionTitle)
                    NovaHelpHint("Dosya ve fotoğraflar isteğe bağlıdır; kaydı daha sonra da tamamlayabilirsiniz.")
                    visibleFields.filter { it.type in fileTypes }.forEach { ProcessFieldRow(it, loadedCatalogue, fieldContext) }
                    if (visibleFields.none { it.type in fileTypes }) NovaEmptyState("Bu kayıt için dosya gerekmiyor", "Devam ederek girdiğiniz bilgileri kontrol edebilirsiniz.")
                }
                else -> {
                    NovaText("Kontrol", style = NovaTypeToken.sectionTitle)
                    NovaHelpHint("Kaydetmeden önce bilgileri doğrulayın; değişiklik için Geri ile ilgili adıma dönebilirsiniz.")
                    NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                        Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                            SummaryRow("Kayıt", spec.title)
                            SummaryRow("Zorunlu alanlar", if (valid) "Tamamlandı" else "Eksik bilgi var")
                            SummaryRow("Dosya", if (visibleFields.filter { it.type in fileTypes }.any { text(it.id).isNotEmpty() }) "Eklendi" else "Eklenmedi")
                        }
                    }
                }
            }
        }
        else -> {
            val form: @Composable ColumnScope.() -> Unit = {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(34.dp), contentAlignment = Alignment.Center) { NovaIcon(kindSymbol(kind), 19.dp) }
                    NovaText(spec.title, Modifier.weight(1f), NovaTypeToken.sheetTitle)
                }
                if (kind == "katip_contract") NovaText("Uzmanın sözleşme kaydıdır; resmî İSG-KATİP işlemi yapılmaz.", style = NovaTypeToken.meta)
                if (kind == "work_permit") NovaText("Form hazırlama aracıdır. Çalışmayı başlatma veya saha onayı vermez.", style = NovaTypeToken.meta)
                if (kind == "board" && text("state") == "cancelled") NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                    NovaText("Bu toplantı iptal edildi.", style = NovaTypeToken.label, color = NovaColorToken.statusDangerInk.color())
                    text("cancelled_reason").takeIf { it.isNotEmpty() }?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
                }
                val loadedCatalogue = catalogue
                if (loading) NovaLoadingView("Kayıt yükleniyor…", Modifier.heightIn(max = 200.dp))
                if (loadedCatalogue != null && !loading) {
                    val ordered = (when (kind) {
                        // Company scope and meeting date first.
                        "board" -> visibleFields.sortedBy { when (it.id) { "workplace_id" -> 0; "planned_on" -> 1; else -> 2 } }
                        else -> visibleFields
                    }).filterNot { it.type == "workplaces" && loadedCatalogue.workplaces.isEmpty() }
                    if (automaticDeadline) NovaHelpHint(deadlineHint(kind, text(if (kind == "completed_drill") "held_on" else "issued_on"), row))
                    if (kind == "katip_contract") {
                        ordered.filter { it.id !in setOf("starts_on", "ends_before") && ordered.indexOf(it) < ordered.indexOfFirst { f -> f.id == "starts_on" } }
                            .forEach { ProcessFieldRow(it, loadedCatalogue, fieldContext) }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ordered.filter { it.id in setOf("starts_on", "ends_before") }.forEach { field ->
                                Box(Modifier.weight(1f)) { ProcessFieldRow(field, loadedCatalogue, fieldContext) }
                            }
                        }
                        ordered.filter { ordered.indexOf(it) > ordered.indexOfFirst { f -> f.id == "ends_before" } }.forEach { ProcessFieldRow(it, loadedCatalogue, fieldContext) }
                    } else ordered.forEach { ProcessFieldRow(it, loadedCatalogue, fieldContext) }
                    if (kind in setOf("annual_work_item", "board_decision", "site_observation")) NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                        FieldIcon("link") {
                            NovaText("İlgili süreç kaydı", style = NovaTypeToken.label)
                            NovaText(if (relatedId.isEmpty()) "Gerçek kayda bağlantı ekleyebilirsiniz." else relatedTitle.ifEmpty { "Bağlı kayıt" }, style = NovaTypeToken.meta)
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                NovaButton(if (relatedId.isEmpty()) "Kayıt seç" else "Değiştir", { choosingRelated = true }, variant = NovaButtonVariant.Surface,
                                    compact = true, enabled = canWrite)
                                if (relatedId.isNotEmpty()) NovaButton("Bağlantıyı kaldır", { relatedKind = ""; relatedId = ""; relatedTitle = "" },
                                    variant = NovaButtonVariant.Muted, compact = true, enabled = canWrite)
                            }
                        }
                    }
                    if (kind == "board" && row != null && text("state") != "cancelled") NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                        if (cancelling) {
                            NovaTextField("İptal gerekçesi", cancelReason, { cancelReason = it }, identifier = "process.board.cancel.reason", multiline = true)
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                NovaButton("Vazgeç", { cancelling = false; cancelReason = "" }, Modifier.weight(1f), variant = NovaButtonVariant.Surface, symbol = "xmark")
                                NovaButton("Toplantıyı iptal et", {
                                    set("state", JsonPrimitive("cancelled")); set("cancelled_reason", JsonPrimitive(cancelReason.trim())); save(); cancelling = false
                                }, Modifier.weight(1f), symbol = "xmark.seal", enabled = cancelReason.isNotBlank())
                            }
                        } else NovaButton("Toplantıyı iptal et", { cancelling = true }, variant = NovaButtonVariant.Surface, enabled = canWrite)
                    }
                    if (row != null) {
                        if (childKind != null) NovaButton(NovaProcessKind.get(childKind).title, { children = true }, variant = NovaButtonVariant.Surface, symbol = "list.bullet")
                        if (kind !in setOf("approved_notebook", "personnel_certificate")) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            NovaButton("PDF indir", { export(false) }, Modifier.weight(1f), variant = NovaButtonVariant.Surface, symbol = "arrow.down.doc", enabled = !busy)
                            NovaButton("Excel indir", { export(true) }, Modifier.weight(1f), variant = NovaButtonVariant.Surface, symbol = "tablecells", enabled = !busy)
                        }
                        NovaButton("Kaydı sil", { deletePrompt = true }, variant = NovaButtonVariant.Danger, symbol = "trash", enabled = canWrite && !busy)
                    }
                    NovaButton(if (busy) "Kaydediliyor…" else "Kaydet", { save() }, symbol = "checkmark", enabled = !busy && valid && canWrite, loading = busy)
                }
                failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
            }
            if (isLongTask) {
                androidx.activity.compose.BackHandler(onBack = onDone)
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).padding(bottom = novaTabBarInset),
                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    NovaBackButton(onClick = onDone)
                    form()
                }
            } else NovaPopup(true, onDone, identifier = "process.editor.$kind") { Column(verticalArrangement = Arrangement.spacedBy(10.dp), content = form) }
        }
    }
    NovaPopup(deletePrompt, { deletePrompt = false }) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            NovaPopupHeading("Kayıt aktif listeden kaldırılacak. Geçmişi korunur.", symbol = "trash")
            NovaButton("Sil", { deletePrompt = false; remove() }, variant = NovaButtonVariant.Danger)
            NovaButton("Vazgeç", { deletePrompt = false }, variant = NovaButtonVariant.Surface)
        }
    }
    NovaPopup(choosingRelated, { choosingRelated = false }, identifier = "process.link.picker") {
        ProcessLinkPicker(client, company, record) { selectedRow, selectedKind ->
            relatedKind = selectedKind; relatedId = selectedRow.id; relatedTitle = selectedRow.title; choosingRelated = false
        }
    }
}

private fun deadlineHint(kind: String, start: String, row: NovaProcessRow?): String {
    val months = if (kind == "completed_drill") row?.values?.get("period_months").novaText().toIntOrNull() ?: 12 else 36
    val due = NovaDay.parse(start)?.plusMonths(months.toLong())?.toString()?.let(NovaDay::label) ?: "—"
    return if (kind == "completed_drill") "Otomatik takip: $due. Genel aralık 12 ay; kayıtlı maden işyerinde sunucu 6 ay uygular. Gerektiğinde tarihi değiştirebilirsiniz."
    else "İlk yardım belgesi için 3 yıl: $due. Belgenizdeki tarih farklıysa değiştirebilirsiniz."
}

@Composable
private fun SummaryRow(title: String, value: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        NovaText(title, style = NovaTypeToken.metaQuiet)
        Spacer(Modifier.weight(1f))
        NovaText(value, style = NovaTypeToken.bodyStrong)
    }
}

/** What a field row needs from its editor. */
private class ProcessFieldContext(val kind: String, val company: String, val client: NovaProcessClient, val row: NovaProcessRow?, val busy: Boolean,
                                  val text: (String) -> String, val raw: (String) -> JsonElement?, val set: (String, JsonElement) -> Unit,
                                  val openAttachment: (String, String) -> Unit)

@Composable
private fun ProcessFieldRow(field: NovaProcessField, catalogue: NovaProcessPage, context: ProcessFieldContext) {
    val title = field.title + if (field.required) " *" else ""
    when (field.type) {
        "date" -> NovaDayField(title, context.text(field.id), { context.set(field.id, JsonPrimitive(it)) }, "process.date.${field.id}", clearable = !field.required)
        in fileTypes -> ProcessControl(field, catalogue, context)
        else -> NovaCard(Modifier.fillMaxWidth(), padding = 12) {
            FieldIcon(fieldSymbol(field)) {
                NovaText(title, style = NovaTypeToken.label)
                ProcessControl(field, catalogue, context)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProcessControl(field: NovaProcessField, catalogue: NovaProcessPage, context: ProcessFieldContext) {
    val value = context.text(field.id)
    var open by remember(field.id) { mutableStateOf(false) }
    when (field.type) {
        "lines" -> NumberedItemsEditor(field.title, value) { context.set(field.id, JsonPrimitive(it)) }
        "bool" -> Row(verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.weight(1f))
            Switch(value == "true", { context.set(field.id, JsonPrimitive(it)) }, Modifier.testTag("process.bool.${field.id}"),
                colors = SwitchDefaults.colors(checkedTrackColor = NovaColorToken.accent.color()))
        }
        "employee" -> {
            var search by remember { mutableStateOf("") }
            NovaSearchCapsule(search, "Personel ara", "process.employee.search") { search = it }
            catalogue.employees.filter { search.isEmpty() || it.name.contains(search, ignoreCase = true) }.forEach { person ->
                val on = value.equals(person.id, true)
                Row(Modifier.fillMaxWidth().heightIn(min = 40.dp).novaRowPress { context.set(field.id, JsonPrimitive(person.id)) }
                    .semantics { role = Role.RadioButton; selected = on }, verticalAlignment = Alignment.CenterVertically) {
                    NovaText(person.name, Modifier.weight(1f))
                    NovaIcon(if (on) "checkmark.circle" else "circle", 15.dp)
                }
            }
        }
        "photos" -> {
            val ids = photoIds(context)
            ids.forEachIndexed { index, id ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("photo", 14.dp); NovaText("Fotoğraf ${index + 1}", Modifier.weight(1f))
                    context.row?.let { row -> NovaButton("Aç", { context.openAttachment("photo_ids:$id", row.id) }, variant = NovaButtonVariant.Surface, compact = true) }
                    Box(Modifier.size(36.dp).novaRowPress { context.set("photo_ids", JsonArray(ids.filter { it != id }.map(::JsonPrimitive))) }
                        .semantics { contentDescription = "Fotoğrafı kaldır" }, contentAlignment = Alignment.Center) { NovaIcon("xmark", 12.dp) }
                }
            }
            if (ids.size < 10) key(ids.size) {
                NovaInlineFileField("other", context.company, context.client.files, "", { added ->
                    if (added.isNotEmpty() && added !in ids) context.set("photo_ids", JsonArray((ids + added).map(::JsonPrimitive)))
                }, imagesOnly = true)
            }
        }
        "file", "photo", "pdf" -> {
            NovaInlineFileField(fileCategory(context.kind), context.company, context.client.files, value, { context.set(field.id, JsonPrimitive(it)) },
                label = field.title, imagesOnly = field.type == "photo", pdfOnly = field.type == "pdf")
            val row = context.row
            val saved = row?.values?.get(field.id).novaText()
            if (row != null && saved.isNotEmpty() && saved == value) NovaButton("Ekli dosyayı aç", { context.openAttachment(field.id, row.id) },
                variant = NovaButtonVariant.Surface, symbol = "doc.viewfinder", enabled = !context.busy)
        }
        "choice" -> {
            NovaChooserButton(field.title, field.choices[value] ?: "Seçin", "process.choice.${field.id}", open = open) { open = !open }
            if (open) NovaChooserPanel(field.choices.map { (key, label) -> NovaChooserOption(key, label) }, value.ifEmpty { null }, "process.choice.${field.id}.panel") {
                context.set(field.id, JsonPrimitive(it.orEmpty())); open = false
            }
        }
        "workplaces", "organizations" -> {
            val options = if (field.type == "workplaces") catalogue.workplaces else catalogue.organizations
            // No workplace to choose from, or exactly one: nothing to ask.
                    if (field.type == "workplaces" && options.isEmpty()) Unit
                    else if (field.type == "workplaces" && options.size == 1) NovaText(options[0].name, style = NovaTypeToken.cardTitle)
            else {
                NovaChooserButton(field.title, options.firstOrNull { it.id.equals(value, true) }?.name ?: "Seçin", "process.${field.type}.${field.id}", open = open) { open = !open }
                if (open) NovaChooserPanel(options.map { NovaChooserOption(it.id, it.name) }, options.firstOrNull { it.id.equals(value, true) }?.id,
                    "process.${field.type}.${field.id}.panel") { context.set(field.id, JsonPrimitive(it.orEmpty())); open = false }
            }
        }
        "employees" -> {
            val people = selectedPeople(field.id, context)
            catalogue.employees.forEach { person ->
                val checked = people.any { it.first.equals(person.id, true) }
                Row(Modifier.fillMaxWidth().heightIn(min = 40.dp).novaRowPress {
                    val next = people.filterNot { it.first.equals(person.id, true) } + if (checked) emptyList() else listOf(person.id to person.name)
                    context.set(field.id, JsonArray(next.map { (id, name) -> buildJsonObject { put("id", id); put("name", name) } }))
                }.semantics { role = Role.Checkbox; selected = checked }, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon(if (checked) "checkmark.square.fill" else "square", 15.dp, tint = NovaColorToken.accentInk.color())
                    NovaText(person.name)
                }
            }
        }
        "datetime" -> DateTimeControl(field, value, context)
        else -> NovaTextField(field.title, value, { context.set(field.id, JsonPrimitive(if (field.type == "number") it.filter(Char::isDigit) else it)) },
            identifier = "process.text.${field.id}", multiline = field.type == "multiline",
            keyboardType = if (field.type == "number") KeyboardType.Number else KeyboardType.Text)
    }
}

private fun photoIds(context: ProcessFieldContext): List<String> =
    (context.raw("photo_ids") as? JsonArray).orEmpty().map { it.novaText() }.filter { it.isNotEmpty() }

/** Stored as `{id, name}` objects, so a later rename in personnel never edits the record. */
private fun selectedPeople(key: String, context: ProcessFieldContext): List<Pair<String, String>> =
    (context.raw(key) as? JsonArray).orEmpty().mapNotNull { entry -> (entry as? JsonObject)?.let { it["id"].novaText() to it["name"].novaText() } }

/** An optional or required ISO date-time; iOS stores `ISO8601DateFormatter` text. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DateTimeControl(field: NovaProcessField, value: String, context: ProcessFieldContext) {
    val zone = ZoneId.of("Europe/Istanbul")
    val instant = runCatching { Instant.parse(value) }.getOrNull()
    val local = instant?.atZone(zone)
    fun write(day: LocalDate, time: LocalTime) = context.set(field.id, JsonPrimitive(day.atTime(time).atZone(zone).toInstant().truncatedTo(java.time.temporal.ChronoUnit.SECONDS).toString()))
    if (!field.required) Row(verticalAlignment = Alignment.CenterVertically) {
        NovaText("Tarih belirt", Modifier.weight(1f), NovaTypeToken.meta)
        Switch(value.isNotEmpty(), { enabled ->
            if (enabled) write(LocalDate.now(zone), LocalTime.now(zone).withSecond(0).withNano(0)) else context.set(field.id, JsonNull)
        }, colors = SwitchDefaults.colors(checkedTrackColor = NovaColorToken.accent.color()))
    }
    if (field.required || value.isNotEmpty()) {
        val day = local?.toLocalDate() ?: LocalDate.now(zone)
        val time = local?.toLocalTime() ?: LocalTime.of(9, 0)
        NovaDayField("Gün", day.toString(), { picked -> NovaDay.parse(picked)?.let { write(it, time) } }, "process.datetime.${field.id}.day")
        NovaTimeField("Saat", time, "process.datetime.${field.id}.time") { write(day, it) }
    }
}

/** One string array presented as individually editable numbered rows (iOS `NovaNumberedItemsEditor`). */
@Composable
private fun NumberedItemsEditor(title: String, value: String, onChange: (String) -> Unit) {
    val lines = if (value.isEmpty()) listOf("") else value.split("\n")
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        lines.forEachIndexed { index, line ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaText("${index + 1}.", Modifier.width(24.dp), NovaTypeToken.label)
                NovaTextField("Madde ${index + 1}", line, { text ->
                    onChange(lines.toMutableList().also { it[index] = text.replace("\n", " ") }.joinToString("\n"))
                }, Modifier.weight(1f), identifier = "process.lines.$index")
                Box(Modifier.size(44.dp).novaRowPress { onChange(lines.toMutableList().also { it.removeAt(index) }.joinToString("\n")) }
                    .semantics { contentDescription = "Madde ${index + 1} sil" }, contentAlignment = Alignment.Center) { NovaIcon("minus.circle", 18.dp) }
            }
        }
        Row(Modifier.heightIn(min = 44.dp).novaRowPress { onChange((lines + "").joinToString("\n")) }, horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically) {
            NovaIcon("plus", 13.dp); NovaText("Madde ekle", style = NovaTypeToken.buttonSm)
        }
        NovaText(title, style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
    }
}

/** Search constrained to the editor's company; choosing a source never changes its state. */
@Composable
private fun ProcessLinkPicker(client: NovaProcessClient, company: String, excluding: String?, onSelect: (NovaProcessRow, String) -> Unit) {
    val kinds = listOf("checklist_run", "training_record", "equipment_inspection", "nonconformity", "site_visit", "board", "work_permit", "katip_contract",
        "annual_work_plan", "contractor")
    val coroutines = rememberCoroutineScope()
    var kind by remember { mutableStateOf("site_visit") }
    var query by remember { mutableStateOf("") }
    var rows by remember { mutableStateOf<List<NovaProcessRow>>(emptyList()) }
    var hasMore by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var choosingKind by remember { mutableStateOf(false) }
    suspend fun load(more: Boolean = false) {
        val selectedKind = kind; val search = query
        loading = true; error = null
        try {
            val page = client.references(selectedKind, company, query = search, offset = if (more) rows.size else 0)
            if (kind == selectedKind && query == search) {
                rows = (if (more) rows else emptyList()) + page.rows.filter { it.id != excluding }; hasMore = page.hasMore
            }
        } catch (failure: Exception) { if (kind == selectedKind) error = NovaProcessService.message(failure) }
        loading = false
    }
    LaunchedEffect(kind) { query = ""; rows = emptyList(); load() }
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaText("İlgili kaydı seç", style = NovaTypeToken.cardTitle)
        NovaChooserButton("Kayıt türü", NovaProcessKind.referenceTitle(kind), "process.link.kind", open = choosingKind) { choosingKind = !choosingKind }
        if (choosingKind) NovaChooserPanel(kinds.map { NovaChooserOption(it, NovaProcessKind.referenceTitle(it)) }, kind, "process.link.kind.panel") {
            if (it != null) kind = it; choosingKind = false
        }
        NovaSearchCapsule(query, "Kayıt ara", "process.link.search") { query = it }
        NovaButton("Ara", { coroutines.launch { load() } }, variant = NovaButtonVariant.Surface, symbol = "magnifyingglass", enabled = !loading, compact = true)
        if (loading) NovaSpinner(NovaColorToken.text.color())
        error?.let {
            NovaText(it, style = NovaTypeToken.meta)
            NovaButton("Yeniden dene", { coroutines.launch { load() } }, variant = NovaButtonVariant.Surface, compact = true)
        }
        rows.forEach { row ->
            Column(Modifier.fillMaxWidth().novaControlBackground(14.dp).clip(RoundedCornerShape(14.dp)).novaRowPress(enabled = !loading) { onSelect(row, kind) }
                .padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                NovaText(row.title)
                NovaText(NovaDay.label(row.date.take(10)), style = NovaTypeToken.meta)
            }
        }
        if (rows.isEmpty() && !loading && error == null) NovaText("Bu firmada uygun kayıt bulunamadı.")
        if (hasMore) NovaButton("Daha fazla", { coroutines.launch { load(more = true) } }, variant = NovaButtonVariant.Surface, enabled = !loading)
    }
}
