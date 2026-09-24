package com.riskdetectedan.feature.nova

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.launch

/** The module's calls bound to one identity (iOS `NovaEquipmentCheckClient`); the design preview supplies its own. */
interface NovaEquipmentClient {
    val companies: suspend () -> List<NovaCompanyOption>
    val files: NovaFileClient
    suspend fun catalogue(company: String?): NovaEquipmentCatalogue
    suspend fun board(query: NovaEquipmentQuery): NovaEquipmentBoard
    suspend fun detail(id: String): NovaEquipmentItem
    suspend fun register(company: String, draft: NovaEquipmentDraft): NovaEquipmentItem
    suspend fun update(item: NovaEquipmentItem, draft: NovaEquipmentDraft): NovaEquipmentItem
    suspend fun archive(item: NovaEquipmentItem)
    suspend fun setRule(company: String, draft: NovaEquipmentRuleDraft): NovaEquipmentRule
    suspend fun recordInspection(item: NovaEquipmentItem, draft: NovaEquipmentInspectionDraft): NovaEquipmentItem
    suspend fun updateInspection(item: NovaEquipmentItem, inspection: NovaEquipmentInspection, draft: NovaEquipmentInspectionDraft): NovaEquipmentItem
    /** Reports the archive already holds for this company, so a check points at a filed document. */
    suspend fun filedReports(company: String): List<NovaFileEntry>
}

class NovaServiceEquipmentClient(private val service: NovaEquipmentService, private val identity: IsgWorkspaceIdentity,
                                 override val companies: suspend () -> List<NovaCompanyOption>, override val files: NovaFileClient) : NovaEquipmentClient {
    override suspend fun catalogue(company: String?) = service.catalogue(identity, company)
    override suspend fun board(query: NovaEquipmentQuery) = service.board(identity, query)
    override suspend fun detail(id: String) = service.detail(identity, id)
    override suspend fun register(company: String, draft: NovaEquipmentDraft) = service.register(identity, company, draft)
    override suspend fun update(item: NovaEquipmentItem, draft: NovaEquipmentDraft) = service.update(identity, item, draft)
    override suspend fun archive(item: NovaEquipmentItem) = service.archive(identity, item)
    override suspend fun setRule(company: String, draft: NovaEquipmentRuleDraft) = service.setRule(identity, company, draft)
    override suspend fun recordInspection(item: NovaEquipmentItem, draft: NovaEquipmentInspectionDraft) = service.recordInspection(identity, item, draft)
    override suspend fun updateInspection(item: NovaEquipmentItem, inspection: NovaEquipmentInspection, draft: NovaEquipmentInspectionDraft) =
        service.updateInspection(identity, item, inspection, draft)
    override suspend fun filedReports(company: String) =
        files.library(NovaFileQuery(state = NovaFileState.promoted.wire, company = company, category = "inspection_report", limit = 50)).rows.filter { it.canDownload }
}

internal fun equipmentMessage(error: Throwable) = (error as? NovaEquipmentException)?.failure?.message ?: NovaEquipmentFailure.unavailable.message

private fun NovaEquipmentGroup.tone() = when (this) {
    NovaEquipmentGroup.overdue, NovaEquipmentGroup.failed -> NovaStatus.Danger
    NovaEquipmentGroup.untracked -> NovaStatus.Warning; NovaEquipmentGroup.dueSoon -> NovaStatus.Info
    NovaEquipmentGroup.current -> NovaStatus.Success
}

/** What a filed report is called when an inspection points at it. */
private fun NovaFileEntry.evidenceId() = assetId ?: id

private fun nextDue(performedOn: String, months: Int?, result: String): String? {
    if (result == "fail" || months == null) return null
    return NovaDay.parse(performedOn)?.plusMonths(months.toLong())?.toString()
}

/**
 * Periyodik Kontroller (iOS `NovaEquipmentCheckScreen`). A company is chosen
 * first, because equipment belongs to one; its inventory opens underneath.
 */
@Composable
fun NovaEquipmentScreen(client: NovaEquipmentClient, canWrite: Boolean, onBack: () -> Unit, initialCompany: String? = null,
                        startInAddMode: Boolean = false, startInInspectionMode: Boolean = false, headingOverride: String? = null,
                        initialRecordId: String? = null) {
    val coroutines = rememberCoroutineScope()
    var board by remember { mutableStateOf<NovaEquipmentBoard?>(null) }
    var catalogue by remember { mutableStateOf(NovaEquipmentCatalogue(emptyList(), emptyList(), emptyList(), 30)) }
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var companyQuery by remember { mutableStateOf("") }
    var query by remember { mutableStateOf("") }
    var group by remember { mutableStateOf<NovaEquipmentGroup?>(null) }
    var equipmentType by remember { mutableStateOf<String?>(null) }
    var company by remember { mutableStateOf(initialCompany) }
    var shown by remember { mutableIntStateOf(10) }
    var inspecting by remember { mutableStateOf<NovaEquipmentItem?>(null) }
    var adding by remember { mutableStateOf(false) }
    var addingInspection by remember { mutableStateOf(false) }
    var inspectionItems by remember { mutableStateOf<List<NovaEquipmentItem>>(emptyList()) }
    var editingPeriods by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var reload by remember { mutableIntStateOf(0) }
    var started by remember { mutableStateOf(false) }
    var openedInitialInspection by remember { mutableStateOf(false) }
    var chooser by remember { mutableStateOf<String?>(null) }
    val locked = initialCompany != null
    val selectedSummary = board?.companies?.firstOrNull { it.id == company }
    val selectedName = selectedSummary?.name ?: companies.firstOrNull { it.id == company }?.name
    // The counters follow what the page shows: the chosen company, otherwise the whole account.
    val visibleCounts = selectedSummary?.counts ?: board?.counts.orEmpty()
    fun count(value: NovaEquipmentGroup) = value.states.sumOf { visibleCounts[it] ?: 0 }
    val trackedHere = NovaEquipmentState.entries.sumOf { visibleCounts[it] ?: 0 }
    fun rule(type: String) = catalogue.rules.firstOrNull { it.equipmentType == type }

    suspend fun loadInspectionItems() {
        val chosen = company ?: run { inspectionItems = emptyList(); return }
        runCatching { client.board(NovaEquipmentQuery(company = chosen, limit = 50)) }.getOrNull()?.let { inspectionItems = it.rows }
    }
    suspend fun openInspection() { loadInspectionItems(); addingInspection = true }

    LaunchedEffect(reload, company, group, equipmentType, shown) {
        error = null; loading = true
        if (!started) {
            started = true
            companies = runCatching { client.companies() }.getOrDefault(emptyList())
            if (startInAddMode && company != null) adding = true
        }
        runCatching { client.catalogue(company) }.getOrNull()?.let { catalogue = it }
        try {
            board = client.board(NovaEquipmentQuery(query, group?.wire, company, equipmentType = equipmentType, limit = shown))
            if (startInInspectionMode && !openedInitialInspection) { openedInitialInspection = true; openInspection() }
        } catch (failure: Exception) {
            board = NovaEquipmentBoard()
            error = if (failure is NovaEquipmentException) failure.failure.message
                else "Ekipman kayıtları alınamadı. Bağlantınızı kontrol edip tekrar deneyin."
        }
        loading = false
    }
    LaunchedEffect(initialRecordId) {
        if (initialRecordId != null) inspecting = runCatching { client.detail(initialRecordId) }.getOrNull()
    }
    fun changeCompany(value: String?) {
        company = value; shown = 10; group = null; equipmentType = null; query = ""; chooser = null
    }

    val opened = inspecting
    if (opened != null) {
        EquipmentItemPage(opened, rule(opened.equipmentType), catalogue.workplaces, client, canWrite,
            onChanged = { reload++ }, onClosed = { inspecting = null })
        return
    }
    val inspectionCompany = company
    if (addingInspection && inspectionCompany != null) {
        EquipmentInspectionFlow(inspectionItems.ifEmpty { board?.rows.orEmpty() }, inspectionCompany, catalogue, client, canWrite,
            onChanged = { reload++; coroutines.launch { loadInspectionItems() } }, onDismiss = { addingInspection = false })
        return
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 4.dp, bottom = novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(11.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaBackButton(onClick = onBack)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(headingOverride ?: NovaDestination.periodicChecks.title, style = NovaTypeToken.screenTitle)
                    selectedName?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
                }
            }
            if (canWrite && company != null) NovaListActionButton("Kontrol Ekle", "plus", identifier = "equipment.inspection.new") {
                coroutines.launch { openInspection() }
            }
        }
        NovaListHint(if (company == null) "Firmayı seçin; ekipmanı ve kontrol raporunu tek akışta ekleyin."
            else "Ekipmanı seçin; kontrol sonucu, tarih ve rapor geçmişine kaydedilsin.")
        if (company == null) {
            NovaSearchCapsule(companyQuery, "Firma ara veya listeden seçin", "equipment.company.search") { companyQuery = it }
            val needle = companyQuery.trim().lowercase()
            val offered = if (needle.isEmpty()) companies else companies.filter { it.name.lowercase().contains(needle) || it.detail.lowercase().contains(needle) }
            when {
                error != null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText(error!!, style = NovaTypeToken.metaQuiet) }
                companies.isEmpty() -> NovaCard(Modifier.fillMaxWidth(), padding = 16) {
                    NovaText(if (loading) "Ekipman kayıtları yükleniyor…" else "Periyodik kontroller için önce bir firma ekleyin.", style = NovaTypeToken.metaQuiet)
                }
                offered.isEmpty() -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText("Bu aramaya uyan firma yok.", style = NovaTypeToken.metaQuiet) }
                else -> offered.forEach { option -> CompanyRow(option, board) { changeCompany(option.id) } }
            }
        } else {
            if (!locked) ChosenCompany(selectedName.orEmpty()) { changeCompany(null); companyQuery = "" }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaListActionButton("Ekipman Ekle", "shippingbox.badge.plus", Modifier.weight(1f), identifier = "equipment.add") { adding = true }
                NovaListActionButton("Kontrol süreleri", "hourglass", Modifier.weight(1f), discovery = true,
                    identifier = "equipment.periods") { editingPeriods = true }
            }
            val statColumns = if (novaFontScaleIsAccessibility()) 2 else 4
            NovaEquipmentGroup.entries.chunked(statColumns).forEach { chunk ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    chunk.forEach { value ->
                        NovaListStat(value.title, value.symbol, count(value), Modifier.weight(1f).testTag("equipment.stat.${value.wire}"),
                            selected = group == value, status = when (value) {
                                NovaEquipmentGroup.overdue, NovaEquipmentGroup.failed -> NovaStatus.Danger
                                NovaEquipmentGroup.untracked -> NovaStatus.Neutral
                                NovaEquipmentGroup.dueSoon -> NovaStatus.Warning
                                NovaEquipmentGroup.current -> NovaStatus.Success
                            }) { group = if (group == value) null else value; shown = 10; chooser = null }
                    }
                    repeat(statColumns - chunk.size) { Spacer(Modifier.weight(1f)) }
                }
            }
            NovaSearchCapsule(query, "Seri/kod veya tür ara", "equipment.search") { query = it }
            LaunchedEffect(query) { if (board != null) { kotlinx.coroutines.delay(350); shown = 10; reload++ } }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaChooserButton("Durum", group?.title ?: "Tümü", "equipment.filter", Modifier.weight(1f),
                    symbol = group?.symbol ?: "line.3.horizontal.decrease", open = chooser == "state") { chooser = if (chooser == "state") null else "state" }
                NovaChooserButton("Tür", equipmentType?.let(NovaEquipmentWords::type) ?: "Tüm türler", "equipment.type", Modifier.weight(1f),
                    symbol = "shippingbox", open = chooser == "type") { chooser = if (chooser == "type") null else "type" }
            }
            if (chooser == "state") NovaChooserPanel(listOf(NovaChooserOption(null, "Tümü", trackedHere, "square.grid.2x2")) +
                NovaEquipmentGroup.entries.map { NovaChooserOption(it.wire, it.title, count(it), it.symbol, it.tone()) }, group?.wire, "equipment.filter") {
                group = NovaEquipmentGroup.ofWire(it); shown = 10; chooser = null
            }
            if (chooser == "type") {
                val held = { code: String -> board?.typeCounts?.get(code)?.values?.sum() ?: 0 }
                NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm türler", trackedHere, "square.grid.2x2")) +
                    catalogue.suggestions.map { it.code }.filter { held(it) > 0 || equipmentType == it }
                        .map { NovaChooserOption(it, NovaEquipmentWords.type(it), held(it), "shippingbox") }, equipmentType, "equipment.type") {
                    equipmentType = it; shown = 10; chooser = null
                }
            }
            val current = board
            current?.let { NovaListSectionHeading("Periyodik Kontroller", "${it.rows.size} / ${it.total} ekipman") }
            when {
                error != null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText(error!!, style = NovaTypeToken.metaQuiet) }
                current == null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText("Ekipman kayıtları yükleniyor…", style = NovaTypeToken.metaQuiet) }
                current.rows.isEmpty() -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    NovaEmptyState(if (trackedHere == 0) "Henüz ekipman kaydı yok" else "Bu filtreye uyan ekipman yok",
                        if (trackedHere == 0) "Periyodik kontrole giren ekipmanları ekleyerek kontrol tarihlerini ve raporlarını takip edebilirsiniz."
                        else "Arama veya filtreleri değiştirerek diğer ekipman kayıtlarını görüntüleyebilirsiniz.")
                }
                else -> NovaListEntrance(true) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        current.rows.forEachIndexed { index, row -> EquipmentCard(row, Modifier.novaRowEntrance(index)) { inspecting = row } }
                        if (current.hasMore) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                            Row(Modifier.heightIn(min = 40.dp).novaRowPress(enabled = !loading) { shown += 10 }.testTag("equipment.more"),
                                horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                                if (loading) NovaText("…", style = NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
                                else NovaIcon("chevron.down", 11.dp, tint = NovaColorToken.accentInk.color())
                                NovaText("Daha fazla göster", style = NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
                        }
                    }
                }
            }
        }
    }
    NovaPopup(adding, { adding = false }, identifier = "equipment.add.sheet") {
        EquipmentAddSheet(company, catalogue, client) { adding = false; reload++ }
    }
    NovaPopup(editingPeriods, { editingPeriods = false }, identifier = "equipment.periods.sheet") {
        EquipmentPeriodSheet(company, catalogue, client) { editingPeriods = false; reload++ }
    }
}

@Composable
private fun CompanyRow(option: NovaCompanyOption, board: NovaEquipmentBoard?, onClick: () -> Unit) {
    val summary = board?.companies?.firstOrNull { it.id == option.id }
    NovaCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onClick).testTag("equipment.company.${option.id.lowercase()}"), padding = 11) {
        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(36.dp), contentAlignment = Alignment.Center) { NovaIcon("building.2", 17.dp) }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(option.name, style = NovaTypeToken.cardTitle, maxLines = 1)
                    if (option.detail.isNotEmpty()) NovaText(option.detail, style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color(), maxLines = 1)
                }
                NovaIcon("chevron.right", 11.dp, tint = NovaColorToken.textTertiary.color())
            }
            if (summary != null && summary.total > 0) Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                NovaTag("shippingbox", "${summary.total} ekipman")
                if (summary.needsAttention > 0) NovaTag("exclamationmark.triangle", "${summary.needsAttention} ilgi bekliyor", NovaStatus.Danger)
            } else if (summary == null && board != null) NovaTag("questionmark.circle", "Envanter yok")
        }
    }
}

@Composable
private fun ChosenCompany(name: String, onChange: () -> Unit) {
    Row(Modifier.fillMaxWidth().novaControlBackground(16.dp).border(1.dp, NovaColorToken.border.color(), RoundedCornerShape(16.dp))
        .padding(horizontal = 12.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon("building.2", 14.dp, tint = NovaColorToken.accentInk.color())
        NovaText(name, Modifier.weight(1f), NovaTypeToken.cardTitle, maxLines = 1)
        Row(Modifier.heightIn(min = 36.dp).novaRowPress(onClick = onChange).testTag("equipment.company.change"),
            horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon("arrow.left.arrow.right", 10.dp, tint = NovaColorToken.accentInk.color())
            NovaText("Firma değiştir", style = NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EquipmentCard(row: NovaEquipmentItem, modifier: Modifier, onClick: () -> Unit) {
    val tone = row.group.tone()
    NovaCard(modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onClick).testTag("equipment.row.${row.id.lowercase()}"), padding = 11) {
        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                Box(Modifier.size(38.dp).background(tone.background.color(), RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
                    NovaIcon(row.group.symbol, 16.dp, tint = tone.ink.color())
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    NovaText(NovaEquipmentWords.type(row.equipmentType), style = NovaTypeToken.cardTitle, maxLines = 1)
                    NovaText(row.serialTag, style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color(), maxLines = 1)
                }
                NovaStatusPill(NovaEquipmentWords.state(row.state), tone, showsDot = false)
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                // No date rather than a blank: the absence is the fact.
                row.nextDueOn?.let { NovaTag("calendar", NovaDay.label(it), tone) } ?: NovaTag("calendar.badge.exclamationmark", "Tarih yok")
                row.periodMonths?.let { NovaTag("hourglass", "$it ay", if (row.periodNeedsReview == true) NovaStatus.Warning else NovaStatus.Neutral) }
                row.locationNote?.takeIf { it.isNotEmpty() }?.let { NovaTag("mappin", it) }
            }
        }
    }
}

/** One item in full and every action on it (iOS `NovaEquipmentItemSheet`, a full-screen page). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EquipmentItemPage(item: NovaEquipmentItem, rule: NovaEquipmentRule?, workplaces: List<NovaEquipmentWorkplace>, client: NovaEquipmentClient,
                              canWrite: Boolean, onChanged: () -> Unit, onClosed: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val context = LocalContext.current
    var current by remember { mutableStateOf<NovaEquipmentItem?>(null) }
    var recording by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf(false) }
    var confirmingArchive by remember { mutableStateOf(false) }
    var moreOpen by remember { mutableStateOf(false) }
    var reports by remember { mutableStateOf<List<NovaFileEntry>>(emptyList()) }
    var correcting by remember { mutableStateOf<NovaEquipmentInspection?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var opening by remember { mutableStateOf<String?>(null) }
    var whyOpen by remember { mutableStateOf(false) }
    val row = current ?: item
    val tone = row.group.tone()
    androidx.activity.compose.BackHandler(onBack = onClosed)
    LaunchedEffect(item.id) {
        val company = row.companyId ?: return@LaunchedEffect
        reports = runCatching { client.filedReports(company) }.getOrDefault(emptyList())
        if (current == null) current = runCatching { client.detail(row.id) }.getOrNull()
    }
    fun run(work: suspend () -> Unit) = coroutines.launch {
        busy = true; error = null
        try { work() } catch (failure: Exception) { error = equipmentMessage(failure) }
        busy = false
    }
    fun open(entry: NovaEquipmentInspection) {
        val download = entry.evidenceDownload ?: return
        opening = entry.id; error = null
        coroutines.launch {
            try {
                val bytes = client.files.download(download.bucket, download.path)
                val name = download.path.substringAfterLast('/').ifEmpty { "belge" }
                val mime = android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase())
                    ?: "application/octet-stream"
                novaShareFile(context, bytes, name, mime)
            } catch (_: Exception) { error = "Dosya servisi şu anda kullanılamıyor." }
            opening = null
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 8.dp, bottom = novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaBackButton(onClick = onClosed)
            NovaText("Ekipman detayı", style = NovaTypeToken.screenTitle)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) { NovaIcon(row.group.symbol, 19.dp, tint = tone.ink.color()) }
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                NovaText(NovaEquipmentWords.type(row.equipmentType), style = NovaTypeToken.sheetTitle, maxLines = 2)
                NovaText(row.serialTag, style = NovaTypeToken.metaQuiet)
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            NovaStatusPill(NovaEquipmentWords.state(row.state), tone)
            row.companyName?.let { NovaTag("building.2", it) }
            row.locationNote?.takeIf { it.isNotEmpty() }?.let { NovaTag("mappin", it) }
        }
        // Why the record says what it says; a missing date needs a reason more than a present one.
        NovaCard(Modifier.fillMaxWidth(), padding = 11, tint = tone.background.color()) { NovaText(NovaEquipmentWords.explain(row), style = NovaTypeToken.meta) }
        NovaCard(Modifier.fillMaxWidth(), padding = 11) {
            val cells = buildList<@Composable (Modifier) -> Unit> {
                row.lastPerformedOn?.let { add { m -> Cell("calendar", "Son kontrol", NovaDay.label(it), m) } }
                row.lastResult?.let { add { m -> Cell("checkmark.seal", "Sonuç", NovaEquipmentWords.result(it), m) } }
                add { m -> Cell("calendar.badge.clock", "Sonraki kontrol", row.nextDueOn?.let(NovaDay::label) ?: "Tarih yok", m,
                    if (row.nextDueOn == null) "" else NovaEquipmentWords.due(row.dueSource)) }
                row.lastInspector?.takeIf { it.isNotEmpty() }?.let { add { m -> Cell("person", "Kontrolü yapan", it, m) } }
                workplaces.firstOrNull { it.id == row.workplaceId }?.name?.let { add { m -> Cell("building.2", "Kapsam", it, m) } }
                row.lastExternalRef?.takeIf { it.isNotEmpty() }?.let { add { m -> Cell("number", "Rapor no", it, m) } }
                // Informational only: it moves no state and no counter.
                add { m -> Cell("text.bubble", "İSG-KATİP", if (row.katipDeclared) "Atama yapıldı" else "İşaretlenmedi", m,
                    if (row.katipDeclared) "uzman beyanı" else "") }
            }
            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                cells.chunked(2).forEach { pair ->
                    Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                        pair.forEach { it(Modifier.weight(1f)) }
                        if (pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
                if (row.lastPerformedOn == null && row.nextDueOn == null && row.lastResult == null)
                    NovaText("Bu ekipman için henüz kontrol kaydı yok.", Modifier.padding(top = 3.dp), NovaTypeToken.metaQuiet)
                if (row.katipDeclared) row.katipNote?.takeIf { it.isNotEmpty() }?.let { NovaText(it, Modifier.padding(top = 7.dp), NovaTypeToken.metaQuiet) }
            }
        }
        // The period and its source together: a duration never appears without attribution.
        NovaCard(Modifier.fillMaxWidth(), padding = 11, tint = NovaColorToken.surfaceMuted.color()) {
            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("hourglass", 12.dp, tint = NovaColorToken.textTertiary.color())
                    NovaText("Kontrol süresi", style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
                }
                val months = row.periodMonths
                if (months != null) {
                    NovaText("$months ay · ${NovaEquipmentWords.source(row.periodSource)}", style = NovaTypeToken.meta)
                    Row(Modifier.heightIn(min = 36.dp).novaRowPress { whyOpen = !whyOpen }, horizontalArrangement = Arrangement.spacedBy(5.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        NovaText("Neden bu süre?", style = NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
                        NovaIcon(if (whyOpen) "chevron.up" else "chevron.down", 10.dp, tint = NovaColorToken.accentInk.color())
                    }
                    AnimatedVisibility(whyOpen, enter = fadeIn() + expandVertically(), exit = fadeOut() + shrinkVertically()) {
                        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                            if (row.periodNeedsReview == true) NovaText(
                                if (row.periodSource == NovaEquipmentPeriodSource.regulationDefault)
                                    "Bu, ürünün bu tür için başlattığı genel süredir; bu firma için henüz onaylanmadı. Süreler ekranından onaylayın veya değiştirin."
                                else "Bu süre uzmanın kendi kararıdır; doğrulanmış bir mevzuat kaynağına bağlanmadı.",
                                style = NovaTypeToken.micro, color = NovaColorToken.statusWarningInk.color())
                            row.periodExceptionNote?.takeIf { it.isNotEmpty() }?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
                        }
                    }
                } else NovaText("Bu tür için süre tanımlı değil. Süre tanımlanana kadar sonraki kontrol tarihi üretilmez.", style = NovaTypeToken.metaQuiet)
            }
        }
        if (canWrite) {
            if (recording) RecordPanel(row, reports, client, onReport = { reports = reports + it }, onCancel = { recording = false }) { saved ->
                current = saved; recording = false; onChanged()
            } else NovaButton("Kontrol kaydet", { recording = true }, Modifier.testTag("equipment.record.open"), symbol = "plus.circle")
        }
        if (row.inspections.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            NovaText("Kontrol geçmişi", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
            row.inspections.forEach { entry ->
                Row(Modifier.fillMaxWidth().background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(12.dp)).padding(9.dp),
                    horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                    HistoryBody(entry, canWrite, Modifier.weight(1f).novaRowPress(enabled = canWrite) { correcting = entry }
                        .testTag("equipment.history.${entry.id.lowercase()}"))
                    if (entry.evidenceDownload != null) Box(Modifier.size(36.dp).novaRowPress(enabled = opening == null) { open(entry) }
                        .semantics { contentDescription = "Raporu aç" }.testTag("equipment.history.${entry.id.lowercase()}.open"), contentAlignment = Alignment.Center) {
                        if (opening == entry.id) NovaSpinner(NovaColorToken.text.color()) else NovaIcon("arrow.up.right.square", 13.dp)
                    }
                }
            }
        }
        error?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
        if (canWrite) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(Modifier.weight(1f).heightIn(min = 44.dp).clip(RoundedCornerShape(14.dp)).background(NovaStatus.Neutral.background.color(), RoundedCornerShape(14.dp))
                    .novaRowPress(enabled = !busy) { editing = true }.testTag("equipment.edit"),
                    horizontalArrangement = Arrangement.spacedBy(7.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("square.and.pencil", 13.dp, tint = NovaStatus.Neutral.ink.color())
                    NovaText("Düzenle", style = NovaTypeToken.meta, color = NovaStatus.Neutral.ink.color())
                }
                Row(Modifier.weight(1f).heightIn(min = 44.dp).clip(RoundedCornerShape(14.dp)).background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(14.dp))
                    .novaRowPress { moreOpen = !moreOpen }.testTag("equipment.more.actions"),
                    horizontalArrangement = Arrangement.spacedBy(7.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("ellipsis.circle", 14.dp, tint = NovaColorToken.textSecondary.color())
                    NovaText("Diğer", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                }
            }
            if (moreOpen && !confirmingArchive) NovaPopupOption("Envanterden çıkar", "archivebox", identifier = "equipment.archive") { confirmingArchive = true }
            if (confirmingArchive) {
                NovaText("Ekipman listeden çıkar; kayıtlı kontrol raporları silinmez.", style = NovaTypeToken.metaQuiet)
                NovaButton("Evet, arşivle", { run { client.archive(row); onChanged(); onClosed() } }, Modifier.testTag("equipment.archive.confirm"),
                    variant = NovaButtonVariant.Danger, enabled = !busy, loading = busy, symbol = "archivebox")
            }
        }
    }
    NovaPopup(editing, { editing = false }, identifier = "equipment.edit.sheet") {
        EquipmentEditSheet(row, workplaces) { draft -> current = client.update(row, draft); editing = false; onChanged() }
    }
    val report = correcting
    NovaPopup(report != null, { correcting = null }, identifier = "equipment.report.sheet") {
        if (report != null) EquipmentReportEditSheet(report, row.periodMonths, reports) { draft ->
            current = client.updateInspection(row, report, draft); correcting = null; onChanged()
        }
    }
}

@Composable
private fun Cell(symbol: String, label: String, value: String, modifier: Modifier, detail: String = "") {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon(symbol, 10.dp, tint = NovaColorToken.textTertiary.color())
            NovaText(label, style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
        }
        NovaText(value, style = NovaTypeToken.meta, maxLines = 2)
        if (detail.isNotEmpty()) NovaText(detail, style = NovaTypeToken.micro, color = NovaColorToken.textMuted.color(), maxLines = 1)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HistoryBody(entry: NovaEquipmentInspection, canWrite: Boolean, modifier: Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(9.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                NovaTag("calendar", NovaDay.label(entry.performedOn))
                NovaTag("checkmark.seal", NovaEquipmentWords.result(entry.result), if (entry.result == "fail") NovaStatus.Danger else NovaStatus.Neutral)
                entry.nextDueOn?.let { NovaTag("calendar.badge.clock", NovaDay.label(it)) }
            }
            entry.inspector?.takeIf { it.isNotEmpty() }?.let { NovaText(it, style = NovaTypeToken.meta) }
            entry.externalRef?.takeIf { it.isNotEmpty() }?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
            entry.note?.takeIf { it.isNotEmpty() }?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
            if (entry.dueSource == NovaEquipmentDueSource.expert || entry.katipDeclared) FlowRow(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                if (entry.dueSource == NovaEquipmentDueSource.expert) NovaTag("pencil", NovaEquipmentWords.due(NovaEquipmentDueSource.expert))
                if (entry.katipDeclared) NovaTag("text.bubble", "KATİP beyanı")
            }
        }
        if (canWrite) NovaIcon("square.and.pencil", 12.dp, tint = NovaColorToken.textTertiary.color())
    }
}

/** A box to tick for the optional İSG-KATİP declaration; never a verification. */
@Composable
private fun KatipField(declared: Boolean, note: String, onDeclared: (Boolean) -> Unit, onNote: (String) -> Unit, identifier: String, hint: String) {
    Row(Modifier.fillMaxWidth().heightIn(min = 40.dp).novaRowPress { onDeclared(!declared) }.testTag(identifier)
        .semantics { role = Role.Checkbox; selected = declared }, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(if (declared) "checkmark.square.fill" else "square", 15.dp, tint = NovaColorToken.accentInk.color())
        NovaSizedText("İSG-KATİP ataması yapıldı", 12.5f, if (declared) FontWeight.Bold else FontWeight.Medium)
    }
    if (declared) NovaTextField("Atama notu", note, onNote, identifier = "$identifier.note")
    NovaText(hint, style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
}

@Composable
private fun ResultPicker(result: String, onPick: (String) -> Unit, identifier: String, accentFill: Boolean = false) {
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        NovaText("Sonuç", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            listOf("pass", "conditional", "fail").forEach { value ->
                val on = result == value
                val fill = when { on && accentFill -> NovaColorToken.accent.color(); on -> NovaColorToken.surface.color(); else -> NovaColorToken.surfaceMuted.color() }
                Box(Modifier.weight(1f).heightIn(min = if (accentFill) 42.dp else 38.dp).clip(RoundedCornerShape(11.dp)).background(fill, RoundedCornerShape(11.dp))
                    .then(if (on && !accentFill) Modifier.border(BorderStroke(1.2.dp, NovaColorToken.accentInk.color()), RoundedCornerShape(11.dp)) else Modifier)
                    .novaRowPress { onPick(value) }.testTag("$identifier.$value").semantics { selected = on }, contentAlignment = Alignment.Center) {
                    NovaSizedText(NovaEquipmentWords.result(value), 12f, if (on) FontWeight.Bold else FontWeight.Medium,
                        if (on && accentFill) Color(0xFF111111) else Color.Unspecified)
                }
            }
        }
    }
}

/** Picks a filed report or uploads a new one inline (iOS `reportPicker`). */
@Composable
private fun ReportPicker(company: String?, reports: List<NovaFileEntry>, client: NovaEquipmentClient, assetId: String?, title: String?,
                         onPick: (NovaFileEntry?) -> Unit, onUploaded: (NovaFileEntry) -> Unit, allowUpload: Boolean, identifier: String) {
    var choosing by remember { mutableStateOf(false) }
    var adding by remember { mutableStateOf(false) }
    var filing by remember { mutableStateOf<NovaFileLibraryService.Catalogue?>(null) }
    LaunchedEffect(adding) { if (adding && filing == null) filing = runCatching { client.files.catalogue() }.getOrNull() }
    NovaChooserButton("Arşivdeki rapor", title ?: "Seçilmedi", identifier, symbol = "doc", open = choosing) { choosing = !choosing; adding = false }
    if (!choosing) return
    if (reports.isNotEmpty()) NovaChooserPanel(listOf(NovaChooserOption(null, "Seçilmedi", symbol = "xmark")) +
        reports.map { NovaChooserOption(it.evidenceId(), it.title, symbol = "doc") }, assetId, "$identifier.panel") { picked ->
        onPick(reports.firstOrNull { it.evidenceId() == picked }); choosing = false
    } else if (!allowUpload) NovaText("Bu firmaya ait hazır rapor bulunamadı.", style = NovaTypeToken.metaQuiet)
    if (!allowUpload) return
    val loaded = filing
    when {
        adding && loaded == null -> NovaText("Dosya seçenekleri yükleniyor…", style = NovaTypeToken.metaQuiet)
        adding && loaded != null -> NovaFileAddInline(emptyList(), company, loaded.categories.filter { it.code == "inspection_report" }.ifEmpty { loaded.categories },
            loaded.accepts, loaded.assurance, client.files) { entry ->
            if (entry != null) onUploaded(entry)
            adding = false; choosing = false
        }
        else -> NovaButton("Yeni dosya ekle", { adding = true }, Modifier.testTag("$identifier.add"), variant = NovaButtonVariant.Surface, symbol = "plus")
    }
}

/** Recording a report inside the item page, in three collapsible steps. */
@Composable
private fun RecordPanel(row: NovaEquipmentItem, reports: List<NovaFileEntry>, client: NovaEquipmentClient, onReport: (NovaFileEntry) -> Unit,
                       onCancel: () -> Unit, onSaved: (NovaEquipmentItem) -> Unit) {
    val coroutines = rememberCoroutineScope()
    var draft by remember { mutableStateOf(NovaEquipmentInspectionDraft(performedOn = NovaDay.today()).let {
        it.copy(nextDueOn = nextDue(it.performedOn, row.periodMonths, it.result).orEmpty()) }) }
    var section by remember { mutableStateOf("control") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    fun refill(value: NovaEquipmentInspectionDraft) =
        if (value.result == "fail") value.copy(nextDueOn = "") else nextDue(value.performedOn, row.periodMonths, value.result)?.let { value.copy(nextDueOn = it) } ?: value
    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
        InspectionStep("control", section, "1 · Kontrol", "calendar.badge.checkmark", NovaEquipmentWords.result(draft.result), { section = it }) {
            NovaDayField("Kontrol", draft.performedOn, { draft = refill(draft.copy(performedOn = it)) }, "equipment.inspection.performed")
            if (draft.result == "fail") NovaCard(Modifier.fillMaxWidth(), padding = 10, tint = NovaColorToken.surfaceMuted.color()) {
                NovaText("Sonraki tarih yok", style = NovaTypeToken.metaQuiet)
            } else NovaDayField("Sonraki", draft.nextDueOn, { draft = draft.copy(nextDueOn = it) }, "equipment.inspection.due", clearable = true)
            ResultPicker(draft.result, { draft = refill(draft.copy(result = it)) }, "equipment.result")
            NovaButton("Detaylara geç", { section = "details" }, variant = NovaButtonVariant.Surface, symbol = "chevron.down")
        }
        InspectionStep("details", section, "2 · Detaylar", "text.justify.left", draft.inspector.ifEmpty { "İsteğe bağlı" }, { section = it }) {
            NovaTextField("Kontrolü yapan", draft.inspector, { draft = draft.copy(inspector = it) }, identifier = "equipment.inspection.inspector")
            NovaTextField("Rapor no", draft.externalRef, { draft = draft.copy(externalRef = it) }, identifier = "equipment.inspection.ref")
            KatipField(draft.katipDeclared, draft.katipNote, { draft = draft.copy(katipDeclared = it) }, { draft = draft.copy(katipNote = it) },
                "equipment.inspection.katip", "İsteğe bağlı uzman beyanı.")
            NovaTextField("Not", draft.note, { draft = draft.copy(note = it) }, identifier = "equipment.inspection.note")
            NovaButton("Rapora geç", { section = "report" }, variant = NovaButtonVariant.Surface, symbol = "chevron.down")
        }
        InspectionStep("report", section, "3 · Rapor", "doc", draft.evidenceTitle ?: "İsteğe bağlı", { section = it }) {
            ReportPicker(row.companyId, reports, client, draft.evidenceAssetId, draft.evidenceTitle,
                onPick = { draft = draft.copy(evidenceAssetId = it?.evidenceId(), evidenceTitle = it?.title) },
                onUploaded = { onReport(it); draft = draft.copy(evidenceAssetId = it.evidenceId(), evidenceTitle = it.title) },
                allowUpload = true, identifier = "equipment.inspection.report")
        }
        error?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaButton("Vazgeç", onCancel, Modifier.weight(1f), variant = NovaButtonVariant.Surface, symbol = "xmark")
            NovaButton("Kaydet", {
                coroutines.launch {
                    busy = true; error = null
                    try { onSaved(client.recordInspection(row, draft)) } catch (failure: Exception) { error = equipmentMessage(failure) }
                    busy = false
                }
            }, Modifier.weight(1f).testTag("equipment.inspection.save"), symbol = "checkmark", enabled = !busy && draft.isReady, loading = busy)
        }
    }
}

@Composable
private fun InspectionStep(id: String, open: String, title: String, symbol: String, summary: String, onToggle: (String) -> Unit,
                           content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().background(NovaColorToken.surface.color(), RoundedCornerShape(15.dp))
        .border(1.dp, NovaColorToken.border.color(), RoundedCornerShape(15.dp)).padding(11.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 42.dp).novaRowPress { onToggle(if (open == id) "" else id) },
            horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon(symbol, 14.dp, Modifier.width(20.dp))
            NovaText(title, Modifier.weight(1f), NovaTypeToken.bodyStrong)
            NovaText(summary, style = NovaTypeToken.micro, color = NovaColorToken.textMuted.color(), maxLines = 1)
            NovaIcon(if (open == id) "chevron.up" else "chevron.down", 10.dp)
        }
        AnimatedVisibility(open == id, enter = fadeIn() + expandVertically(), exit = fadeOut() + shrinkVertically()) {
            Column(Modifier.padding(top = 2.dp), verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
        }
    }
}

/** Correcting a report on file; its date and result are shown, not edited. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EquipmentReportEditSheet(report: NovaEquipmentInspection, periodMonths: Int?, reports: List<NovaFileEntry>,
                                     save: suspend (NovaEquipmentInspectionDraft) -> Unit) {
    val coroutines = rememberCoroutineScope()
    val busyReporter = LocalNovaPopupBusy.current
    var draft by remember { mutableStateOf(NovaEquipmentInspectionDraft(report.performedOn, report.result, report.nextDueOn.orEmpty(),
        report.inspector.orEmpty(), report.externalRef.orEmpty(), report.note.orEmpty(), report.katipDeclared, report.katipNote.orEmpty(),
        report.evidenceAssetId, reports.firstOrNull { it.evidenceId() == report.evidenceAssetId }?.title)) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
        NovaPopupHeading("Kontrol kaydını düzelt", symbol = "square.and.pencil")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            NovaTag("calendar", NovaDay.label(report.performedOn))
            NovaTag("checkmark.seal", NovaEquipmentWords.result(report.result), if (report.result == "fail") NovaStatus.Danger else NovaStatus.Neutral)
        }
        NovaHelpHint("Kontrol tarihi ve sonucu raporun kendisidir; buradan değiştirilmez. Yanlışsa doğru raporu ayrıca kaydedin.")
        if (report.result == "fail") NovaText("Olumsuz sonuç için sonraki kontrol tarihi üretilmez.", style = NovaTypeToken.micro,
            color = NovaColorToken.statusWarningInk.color())
        else {
            NovaDayField("Sonraki kontrol", draft.nextDueOn, { draft = draft.copy(nextDueOn = it) }, "equipment.report.due", clearable = true)
            periodMonths?.let { NovaText("Türün süresi $it ay. Değiştirirseniz kayıt, tarihin sizin belirlediğinizi söyler.", style = NovaTypeToken.micro,
                color = NovaColorToken.textTertiary.color()) }
        }
        NovaTextField("Kontrolü yapan", draft.inspector, { draft = draft.copy(inspector = it) }, identifier = "equipment.report.inspector")
        NovaTextField("Rapor no", draft.externalRef, { draft = draft.copy(externalRef = it) }, identifier = "equipment.report.ref")
        KatipField(draft.katipDeclared, draft.katipNote, { draft = draft.copy(katipDeclared = it) }, { draft = draft.copy(katipNote = it) },
            "equipment.report.katip", "Bu işaret uzmanın kendi beyanıdır. Uygulama İSG-KATİP üzerinde sorgulama veya işlem yapmaz.")
        NovaTextField("Not", draft.note, { draft = draft.copy(note = it) }, identifier = "equipment.report.note")
        error?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
        NovaButton("Kaydet", {
            coroutines.launch {
                busy = true; busyReporter(true); error = null
                try { save(draft) } catch (failure: Exception) {
                    error = (failure as? NovaEquipmentException)?.failure?.message ?: NovaEquipmentFailure.validation.message
                }
                busy = false; busyReporter(false)
            }
        }, Modifier.testTag("equipment.report.save"), symbol = "checkmark", enabled = !busy, loading = busy)
    }
}

/** Start a periodic control: pick the company's equipment, then record its control (iOS `NovaEquipmentInspectionFlow`). */
@Composable
private fun EquipmentInspectionFlow(items: List<NovaEquipmentItem>, company: String,
                                    catalogue: NovaEquipmentCatalogue, client: NovaEquipmentClient, canWrite: Boolean,
                                    onChanged: () -> Unit, onDismiss: () -> Unit) {
    var selected by remember { mutableStateOf<NovaEquipmentItem?>(null) }
    var addingEquipment by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    androidx.activity.compose.BackHandler(onBack = onDismiss)
    val chosen = selected
    if (chosen != null) {
        EquipmentInspectionTask(chosen, client, canWrite, onChanged, onClose = { selected = null }, onDone = onDismiss)
        return
    }
    val filtered = if (query.isBlank()) items else items.filter { it.matches(query) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp).padding(top = 10.dp, bottom = 28.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaTaskHeader("Periyodik kontrol", 1, 3, "Ekipman", onClose = onDismiss)
        NovaText("Kontrol yapılacak ekipmanı seçin. Kayıt, seçtiğiniz ekipmanın geçmişine eklenir.")
        if (items.isNotEmpty()) NovaSearchCapsule(query, "Ekipman türü veya seri/kod ara", "equipment.inspection.search") { query = it }
        if (filtered.isEmpty()) NovaEmptyState(if (items.isEmpty()) "Önce ekipman ekleyin" else "Bu aramaya uyan ekipman yok",
            if (items.isEmpty()) "Ekipman firmaya bir kez kaydedilir; sonraki tüm periyodik kontroller ve raporlar bu ekipmanın geçmişine eklenir."
            else "Aramayı temizleyerek firmanın diğer ekipmanlarını görüntüleyebilirsiniz.")
        else filtered.forEach { item ->
            Row(Modifier.fillMaxWidth().novaControlBackground(14.dp).clip(RoundedCornerShape(14.dp)).novaRowPress { selected = item }.padding(11.dp)
                .testTag("equipment.inspection.choice.${item.id.lowercase()}"), horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(34.dp), contentAlignment = Alignment.Center) { NovaIcon("shippingbox", 16.dp) }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(NovaEquipmentWords.type(item.equipmentType), style = NovaTypeToken.cardTitle)
                    NovaText(item.serialTag, style = NovaTypeToken.metaQuiet)
                }
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(item.lastPerformedOn?.let { "Son: ${NovaDay.label(it)}" } ?: "Henüz kontrol yok", style = NovaTypeToken.micro)
                    NovaText(item.nextDueOn?.let { "Sonraki: ${NovaDay.label(it)}" } ?: "Sonraki tarih yok", style = NovaTypeToken.micro,
                        color = NovaColorToken.textTertiary.color())
                }
                NovaIcon("chevron.right", 11.dp)
            }
        }
        NovaButton(if (items.isEmpty()) "İlk ekipmanı ekle" else "Yeni ekipman ekle", { addingEquipment = true }, variant = NovaButtonVariant.Surface,
            symbol = "plus", enabled = canWrite)
    }
    NovaPopup(addingEquipment, { addingEquipment = false }, identifier = "equipment.add.sheet") {
        EquipmentAddSheet(company, catalogue, client) { addingEquipment = false; onChanged() }
    }
}

private enum class InspectionStepKind(val title: String) { control("Kontrol"), details("Detaylar"), report("Rapor") }

/** The inspection itself: three linear steps with sticky actions (iOS `NovaEquipmentInspectionTask`). */
@Composable
private fun EquipmentInspectionTask(item: NovaEquipmentItem, client: NovaEquipmentClient, canWrite: Boolean, onChanged: () -> Unit,
                                    onClose: () -> Unit, onDone: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    var draft by remember { mutableStateOf(NovaEquipmentInspectionDraft(performedOn = NovaDay.today()).let {
        it.copy(nextDueOn = nextDue(it.performedOn, item.periodMonths, it.result).orEmpty()) }) }
    var step by remember { mutableStateOf(InspectionStepKind.control) }
    var reports by remember { mutableStateOf<List<NovaFileEntry>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    var didSave by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmingExit by remember { mutableStateOf(false) }
    fun refill(value: NovaEquipmentInspectionDraft) =
        if (value.result == "fail") value.copy(nextDueOn = "") else nextDue(value.performedOn, item.periodMonths, value.result)?.let { value.copy(nextDueOn = it) } ?: value
    LaunchedEffect(item.id) { item.companyId?.let { company -> reports = runCatching { client.filedReports(company) }.getOrDefault(emptyList()) } }
    if (didSave) {
        NovaTaskSuccessView("Kontrol kaydedildi", "${NovaEquipmentWords.type(item.equipmentType)} kontrolü ekipman geçmişine eklendi.",
            "Kontrollere dön", onDone)
        return
    }
    fun save() {
        if (!canWrite || !draft.isReady) { error = "Kontrol tarihi ve geçerli bir sonuç girin."; return }
        coroutines.launch {
            busy = true; error = null
            try { client.recordInspection(item, draft); onChanged(); didSave = true } catch (failure: Exception) { error = equipmentMessage(failure) }
            busy = false
        }
    }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 18.dp).padding(top = 10.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            NovaTaskHeader("Periyodik kontrol", step.ordinal + 1, InspectionStepKind.entries.size, step.title) { confirmingExit = true }
            NovaCard(Modifier.fillMaxWidth(), padding = 13, tint = NovaColorToken.surfaceMuted.color()) {
                NovaText(NovaEquipmentWords.type(item.equipmentType), style = NovaTypeToken.bodyStrong)
                NovaText(listOfNotNull(item.serialTag, item.locationNote).joinToString(" · "), style = NovaTypeToken.metaQuiet)
            }
            error?.let { NovaTaskErrorSummary(it) }
            when (step) {
                InspectionStepKind.control -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    NovaText("Kontrol sonucu", style = NovaTypeToken.sectionTitle)
                    NovaDayField("Kontrol tarihi", draft.performedOn, { draft = refill(draft.copy(performedOn = it)) }, "equipment.task.performed")
                    ResultPicker(draft.result, { draft = refill(draft.copy(result = it)) }, "equipment.task.result", accentFill = true)
                    if (draft.result == "fail") NovaTaskErrorSummary("Olumsuz sonuçta sonraki kontrol tarihi oluşturulmaz.")
                    else {
                        NovaDayField("Sonraki kontrol (isteğe bağlı)", draft.nextDueOn, { draft = draft.copy(nextDueOn = it) }, "equipment.task.due", clearable = true)
                        item.periodMonths?.let { NovaText("$it aylık süreye göre otomatik dolduruldu; gerekirse değiştirebilirsiniz.", style = NovaTypeToken.micro) }
                    }
                }
                InspectionStepKind.details -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    NovaText("Ek bilgileri yalnız gerekiyorsa doldurun.")
                    NovaTextField("Kontrolü yapan", draft.inspector, { draft = draft.copy(inspector = it) }, identifier = "equipment.task.inspector")
                    NovaTextField("Rapor no", draft.externalRef, { draft = draft.copy(externalRef = it) }, identifier = "equipment.task.ref")
                    KatipField(draft.katipDeclared, draft.katipNote, { draft = draft.copy(katipDeclared = it) }, { draft = draft.copy(katipNote = it) },
                        "equipment.task.katip", "İsteğe bağlı uzman beyanı.")
                    NovaTextField("Not (isteğe bağlı)", draft.note, { draft = draft.copy(note = it) }, identifier = "equipment.task.note", multiline = true)
                }
                InspectionStepKind.report -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    NovaText("Rapor bağlamak isteğe bağlıdır. Arşivde hazır olan bir dosyayı seçebilirsiniz.")
                    ReportPicker(item.companyId, reports, client, draft.evidenceAssetId, draft.evidenceTitle ?: "Rapor seçilmedi",
                        onPick = { draft = draft.copy(evidenceAssetId = it?.evidenceId(), evidenceTitle = it?.title) }, onUploaded = {},
                        allowUpload = false, identifier = "equipment.task.report")
                    NovaCard(Modifier.fillMaxWidth(), padding = 13, tint = NovaColorToken.surfaceMuted.color()) {
                        NovaText("Kayda hazır", style = NovaTypeToken.bodyStrong)
                        NovaText("Tarih, sonuç ve eklediğiniz bilgiler ekipmanın kontrol geçmişine yazılacak.", style = NovaTypeToken.metaQuiet)
                    }
                }
            }
        }
        NovaTaskStickyActions(if (step == InspectionStepKind.report) "Kontrolü kaydet" else "Devam", onBack = {
            if (step.ordinal > 0) step = InspectionStepKind.entries[step.ordinal - 1]
        }, onPrimary = {
            when {
                step == InspectionStepKind.report -> save()
                step == InspectionStepKind.control && draft.performedOn.isBlank() -> error = "Bu adımı tamamlamak için kontrol tarihini girin."
                else -> { error = null; step = InspectionStepKind.entries[step.ordinal + 1] }
            }
        }, Modifier.navigationBarsPadding().padding(bottom = novaTabBarClearance), if (step == InspectionStepKind.report) "checkmark" else "arrow.right",
            working = busy, canGoBack = step != InspectionStepKind.control)
    }
    NovaPopup(confirmingExit, { confirmingExit = false }) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            NovaPopupHeading("Kontrol akışından çıkılsın mı?", symbol = "exclamationmark.triangle")
            NovaText("Henüz kaydedilmemiş bilgiler silinir.")
            NovaButton("Çık", { confirmingExit = false; onClose() }, variant = NovaButtonVariant.Danger)
            NovaButton("Devam et", { confirmingExit = false }, variant = NovaButtonVariant.Surface)
        }
    }
}

/** Registering equipment; a chosen type name never arrives with a period of its own. */
@Composable
private fun EquipmentAddSheet(company: String?, catalogue: NovaEquipmentCatalogue, client: NovaEquipmentClient, onDone: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val busyReporter = LocalNovaPopupBusy.current
    var draft by remember { mutableStateOf(NovaEquipmentDraft(workplaceId = catalogue.workplaces.firstOrNull()?.id)) }
    var choosing by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val type = draft.equipmentType
    val rule = type?.let { code -> catalogue.rules.firstOrNull { it.equipmentType == code } }
    Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
        NovaPopupHeading("Ekipman ekle", symbol = "shippingbox")
        NovaChooserButton("Ekipman türü", type?.let(NovaEquipmentWords::type) ?: "Tür seçin", "equipment.add.type", symbol = "shippingbox",
            open = choosing == "type") { choosing = if (choosing == "type") null else "type" }
        if (choosing == "type") NovaChooserPanel(catalogue.suggestions.map { NovaChooserOption(it.code, NovaEquipmentWords.type(it.code), it.defaultPeriodMonths, "shippingbox") },
            type, "equipment.add.type") { draft = draft.copy(equipmentType = it); choosing = null }
        if (type != null) {
            val defaultMonths = catalogue.suggestions.firstOrNull { it.code == type }?.defaultPeriodMonths
            when {
                rule != null -> NovaText("${rule.periodMonths} ay · ${NovaEquipmentWords.source(rule.source)}", style = NovaTypeToken.micro,
                    color = if (rule.needsReview) NovaColorToken.statusWarningInk.color() else NovaColorToken.textTertiary.color())
                defaultMonths != null -> NovaText("Bu tür $defaultMonths ay ile başlar · ${NovaEquipmentWords.source(NovaEquipmentPeriodSource.regulationDefault)}",
                    style = NovaTypeToken.micro, color = NovaColorToken.statusWarningInk.color())
                else -> NovaText("Bu tür için süre tanımlı değil. Süre tanımlanmadan sonraki kontrol tarihi hesaplanmaz.", style = NovaTypeToken.micro,
                    color = NovaColorToken.statusWarningInk.color())
            }
        }
        if (catalogue.workplaces.isNotEmpty()) {
            NovaChooserButton("Kapsam", catalogue.workplaces.firstOrNull { it.id == draft.workplaceId }?.name ?: "İşyeri seçin", "equipment.add.workplace",
                symbol = "building.2", open = choosing == "workplace") { choosing = if (choosing == "workplace") null else "workplace" }
            if (choosing == "workplace") NovaChooserPanel(catalogue.workplaces.map { NovaChooserOption(it.id, it.name, symbol = "building.2") },
                draft.workplaceId, "equipment.add.workplace") { draft = draft.copy(workplaceId = it); choosing = null }
        }
        NovaTextField("Seri / kod", draft.serialTag, { draft = draft.copy(serialTag = it) }, identifier = "equipment.add.serial")
        NovaTextField("Yeri (isteğe bağlı)", draft.locationNote, { draft = draft.copy(locationNote = it) }, identifier = "equipment.add.location")
        NovaDayField("Ediniliş tarihi", draft.acquiredOn, { draft = draft.copy(acquiredOn = it) }, "equipment.add.acquired", clearable = true)
        error?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
        NovaButton("Envantere ekle", {
            val chosen = company ?: return@NovaButton
            coroutines.launch {
                busy = true; busyReporter(true); error = null
                try { client.register(chosen, draft); onDone() } catch (failure: Exception) { error = equipmentMessage(failure) }
                busy = false; busyReporter(false)
            }
        }, Modifier.testTag("equipment.add.save"), symbol = "checkmark", enabled = !busy && draft.isReady && company != null, loading = busy)
    }
}

/** Editing what the item is, never what its record says; the type stays because the period hangs on it. */
@Composable
private fun EquipmentEditSheet(item: NovaEquipmentItem, workplaces: List<NovaEquipmentWorkplace>, save: suspend (NovaEquipmentDraft) -> Unit) {
    val coroutines = rememberCoroutineScope()
    val busyReporter = LocalNovaPopupBusy.current
    var draft by remember { mutableStateOf(NovaEquipmentDraft(item.equipmentType, item.serialTag, item.workplaceId, item.acquiredOn.orEmpty(), item.locationNote.orEmpty())) }
    var choosing by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
        NovaPopupHeading("Ekipman kaydını düzenle", symbol = "square.and.pencil")
        NovaText(NovaEquipmentWords.type(item.equipmentType), style = NovaTypeToken.metaQuiet)
        if (workplaces.isNotEmpty()) NovaChooserButton("Kapsam", workplaces.firstOrNull { it.id == draft.workplaceId }?.name ?: "Firma geneli", "equipment.edit.workplace",
            symbol = "building.2", open = choosing) { choosing = !choosing }
        if (choosing && workplaces.isNotEmpty()) NovaChooserPanel(workplaces.map { NovaChooserOption(it.id, it.name, symbol = "building.2") }, draft.workplaceId,
            "equipment.edit.workplace") { draft = draft.copy(workplaceId = it); choosing = false }
        NovaTextField("Seri / kod", draft.serialTag, { draft = draft.copy(serialTag = it) }, identifier = "equipment.edit.serial")
        NovaTextField("Yeri (isteğe bağlı)", draft.locationNote, { draft = draft.copy(locationNote = it) }, identifier = "equipment.edit.location")
        NovaDayField("Ediniliş tarihi", draft.acquiredOn, { draft = draft.copy(acquiredOn = it) }, "equipment.edit.acquired", clearable = true)
        error?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
        NovaButton("Kaydet", {
            coroutines.launch {
                busy = true; busyReporter(true); error = null
                try { save(draft) } catch (failure: Exception) {
                    error = (failure as? NovaEquipmentException)?.failure?.message ?: NovaEquipmentFailure.validation.message
                }
                busy = false; busyReporter(false)
            }
        }, Modifier.testTag("equipment.edit.save"), symbol = "checkmark", enabled = !busy && draft.isReady, loading = busy)
    }
}

/** The inspection periods by type; an unverified source is labelled as the expert's own decision. */
@Composable
private fun EquipmentPeriodSheet(company: String?, catalogue: NovaEquipmentCatalogue, client: NovaEquipmentClient, onDone: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val busyReporter = LocalNovaPopupBusy.current
    var draft by remember { mutableStateOf(NovaEquipmentRuleDraft()) }
    var saved by remember { mutableStateOf<List<NovaEquipmentRule>>(emptyList()) }
    var choosing by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val current = saved.ifEmpty { catalogue.rules }
    Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
        NovaPopupHeading("Kontrol süreleri", symbol = "hourglass")
        NovaHelpHint("Süre ekipman türüne göre tanımlanır ve hiçbir tür için önceden doldurulmaz. Doğrulanmış bir kaynağa dayanmayan süre, uzman kararı olarak işaretlenir.")
        NovaChooserButton("Ekipman türü", draft.equipmentType?.let(NovaEquipmentWords::type) ?: "Tür seçin", "equipment.period.type",
            symbol = "shippingbox", open = choosing) { choosing = !choosing }
        if (choosing) NovaChooserPanel(catalogue.suggestions.map { entry ->
            NovaChooserOption(entry.code, NovaEquipmentWords.type(entry.code),
                current.firstOrNull { it.equipmentType == entry.code }?.periodMonths ?: entry.defaultPeriodMonths, "shippingbox")
        }, draft.equipmentType, "equipment.period.type") { picked ->
            // Pre-fill from what is on file, or from the product's own starting period.
            val existing = current.firstOrNull { it.equipmentType == picked }
            draft = when {
                picked == null -> draft.copy(equipmentType = null)
                existing != null -> draft.copy(equipmentType = picked, periodMonths = existing.periodMonths.toString(),
                    source = if (existing.source.needsReview) NovaEquipmentPeriodSource.manufacturer else existing.source,
                    exceptionNote = existing.exceptionNote.orEmpty())
                else -> draft.copy(equipmentType = picked, periodMonths = catalogue.suggestions.firstOrNull { it.code == picked }?.defaultPeriodMonths?.toString()
                    ?: draft.periodMonths)
            }
            choosing = false
        }
        NovaTextField("Süre (ay)", draft.periodMonths, { value -> draft = draft.copy(periodMonths = value.filter(Char::isDigit).take(3)) },
            identifier = "equipment.period.months", keyboardType = KeyboardType.Number)
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            NovaText("Sürenin kaynağı", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
            // The product default is not offered: choosing a source means standing behind it.
            NovaEquipmentPeriodSource.choosable.forEach { value ->
                val on = draft.source == value
                Row(Modifier.fillMaxWidth().heightIn(min = 40.dp).novaControlBackground(11.dp).clip(RoundedCornerShape(11.dp))
                    .novaRowPress { draft = draft.copy(source = value) }.padding(horizontal = 10.dp).testTag("equipment.period.source.${value.wire}")
                    .semantics { role = Role.RadioButton; selected = on }, horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon(if (on) "largecircle.fill.circle" else "circle", 13.dp, tint = NovaColorToken.accentInk.color())
                    NovaSizedText(NovaEquipmentWords.source(value), 12.5f, if (on) FontWeight.Bold else FontWeight.Medium)
                }
            }
        }
        if (draft.source == NovaEquipmentPeriodSource.unapprovedFixture)
            NovaTextField("Gerekçe", draft.exceptionNote, { draft = draft.copy(exceptionNote = it) }, identifier = "equipment.period.exception")
        error?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
        NovaButton("Süreyi kaydet", {
            val chosen = company ?: return@NovaButton
            coroutines.launch {
                busy = true; busyReporter(true); error = null
                try {
                    val rule = client.setRule(chosen, draft)
                    saved = current.filter { it.equipmentType != rule.equipmentType } + rule
                    draft = NovaEquipmentRuleDraft()
                } catch (failure: Exception) { error = (failure as? NovaEquipmentException)?.failure?.message ?: NovaEquipmentFailure.validation.message }
                busy = false; busyReporter(false)
            }
        }, Modifier.testTag("equipment.period.save"), symbol = "checkmark", enabled = !busy && draft.isReady && company != null, loading = busy)
        if (current.isNotEmpty()) {
            NovaText("Tanımlı süreler", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
            current.forEach { rule ->
                Column(Modifier.fillMaxWidth().background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(12.dp)).padding(9.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(NovaEquipmentWords.type(rule.equipmentType), style = NovaTypeToken.meta)
                    NovaText("${rule.periodMonths} ay · ${NovaEquipmentWords.source(rule.source)}", style = NovaTypeToken.micro,
                        color = if (rule.needsReview) NovaColorToken.statusWarningInk.color() else NovaColorToken.textTertiary.color())
                }
            }
        }
        NovaButton("Kapat", onDone, Modifier.testTag("equipment.periods.close"), variant = NovaButtonVariant.Surface, symbol = "xmark")
    }
}
