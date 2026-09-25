package com.riskdetectedan.feature.nova

import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/** The checklist module's calls bound to one identity (iOS `NovaChecklistClient`). */
interface NovaChecklistClient {
    val companies: suspend () -> List<NovaCompanyOption>
    suspend fun catalogue(company: String?): NovaChecklistCatalogue
    suspend fun library(search: String, sector: String?, kind: String?, offset: Int): NovaChecklistLibrary
    suspend fun templateDetail(template: String): NovaChecklistTemplateDetail
    suspend fun templates(company: String?): List<NovaChecklistTemplate>
    suspend fun assignments(company: String): List<NovaChecklistAssignment>
    suspend fun board(query: NovaChecklistQuery): NovaChecklistBoard
    suspend fun detail(run: String): NovaChecklistRun
    suspend fun startRun(company: String?, workplace: String?, template: String, startedOn: String, area: String, equipment: String, document: String): NovaChecklistRun?
    /** Records an answer; an unreachable server queues it on the device and answers null. */
    suspend fun answer(company: String?, draft: NovaChecklistAnswerDraft): NovaChecklistRun?
    suspend fun uploadEvidence(company: String, attachment: NovaChecklistAttachment): String
    suspend fun submit(company: String?, run: String, revision: Long): NovaChecklistRun?
    suspend fun cancel(company: String?, run: String, revision: Long): NovaChecklistRun?
    suspend fun revise(company: String?, run: String, revision: Long, startedOn: String): NovaChecklistRun?
    suspend fun draftTemplate(company: String?, title: String)
    suspend fun setItem(company: String?, template: String, version: Int, revision: Long, itemCode: String, prompt: String, allowsNotApplicable: Boolean, position: Int)
    suspend fun copyItems(company: String?, template: String, version: Int, revision: Long, items: List<NovaChecklistItemSelection>)
    suspend fun reorderItems(company: String?, template: String, version: Int, revision: Long, itemCodes: List<String>)
    suspend fun removeItem(company: String?, template: String, version: Int, revision: Long, itemCode: String)
    suspend fun publishTemplate(company: String?, template: String, version: Int, revision: Long, note: String)
    suspend fun copyTemplate(company: String?, template: String, title: String?)
    suspend fun assignTemplate(company: String, workplace: String?, template: String)
    suspend fun deactivateAssignment(company: String, assignment: String)
    fun pendingAnswers(): Pair<Int, Int>
    suspend fun syncPendingAnswers(): Pair<Int, Int>
    /** `setItem` with a section title; the checklist wizard files its own questions under their topic. */
    suspend fun setSectionItem(company: String?, template: String, version: Int, revision: Long, itemCode: String, prompt: String, allowsNotApplicable: Boolean,
                               position: Int, section: String) = setItem(company, template, version, revision, itemCode, prompt, allowsNotApplicable, position)
}

class NovaServiceChecklistClient(private val service: NovaChecklistService, private val queue: NovaChecklistOfflineQueue, private val files: NovaFileLibraryService,
                                 private val identity: IsgWorkspaceIdentity, override val companies: suspend () -> List<NovaCompanyOption>) : NovaChecklistClient {
    override suspend fun catalogue(company: String?) = service.catalogue(identity, company)
    override suspend fun library(search: String, sector: String?, kind: String?, offset: Int) = service.library(identity, search, sector, kind, 30, offset)
    override suspend fun templateDetail(template: String) = service.templateDetail(identity, template)
    override suspend fun templates(company: String?) = service.templates(identity, company)
    override suspend fun assignments(company: String) = service.assignments(identity, company)
    override suspend fun board(query: NovaChecklistQuery) = service.board(identity, query)
    /** A run row from a start, answer or detail call carries no company name (only the board's
     *  list read joins it), so the company picker's own names fill it in. */
    private var companyNames: Map<String, String>? = null
    private suspend fun named(run: NovaChecklistRun?): NovaChecklistRun? {
        val company = run?.companyId ?: return run
        if (!run.companyName.isNullOrBlank()) return run
        val names = companyNames ?: runCatching { companies().associate { it.id to it.name } }.getOrNull()?.also { companyNames = it }
        return names?.get(company)?.let { run.copy(companyName = it) } ?: run
    }
    override suspend fun detail(run: String) = named(service.detail(identity, run))!!
    override suspend fun startRun(company: String?, workplace: String?, template: String, startedOn: String, area: String, equipment: String, document: String) =
        named(service.startRun(identity, company, workplace, template, startedOn, area, equipment, document))
    override suspend fun answer(company: String?, draft: NovaChecklistAnswerDraft): NovaChecklistRun? = try {
        named(service.recordAnswer(identity, company, draft))
    } catch (failure: NovaChecklistException) {
        if (failure.failure != NovaChecklistFailure.unavailable) throw failure
        queue.enqueue(identity, company, draft); null
    }
    /** The evidence goes through the same archive as every other file; only a filed copy counts. */
    override suspend fun uploadEvidence(company: String, attachment: NovaChecklistAttachment): String {
        val extension = attachment.fileName.substringAfterLast('.', "").lowercase()
        val entry = files.file(identity, company, NovaFileDraft(tags = "kontrol listesi, kanıt", title = attachment.title, category = "inspection_report",
            fileName = attachment.fileName, fileExtension = extension, bytes = attachment.data.size, sha256 = NovaFileDraft.sha256(attachment.data)), attachment.data)
        if (!entry.state.isFiled) throw NovaFileException(NovaFileFailure.inspectionUnavailable)
        return entry.assetId ?: throw NovaFileException(NovaFileFailure.inspectionUnavailable)
    }
    override suspend fun submit(company: String?, run: String, revision: Long) = named(service.submitRun(identity, company, run, revision))
    override suspend fun cancel(company: String?, run: String, revision: Long) = named(service.cancelRun(identity, company, run, revision))
    override suspend fun revise(company: String?, run: String, revision: Long, startedOn: String) = named(service.reviseRun(identity, company, run, revision, startedOn))
    override suspend fun draftTemplate(company: String?, title: String) = service.draftTemplate(identity, company, title)
    override suspend fun setItem(company: String?, template: String, version: Int, revision: Long, itemCode: String, prompt: String, allowsNotApplicable: Boolean,
                                 position: Int) = service.setItem(identity, company, template, version, revision, itemCode, prompt, allowsNotApplicable, position)
    override suspend fun setSectionItem(company: String?, template: String, version: Int, revision: Long, itemCode: String, prompt: String,
                                        allowsNotApplicable: Boolean, position: Int, section: String) =
        service.setItem(identity, company, template, version, revision, itemCode, prompt, allowsNotApplicable, position, section)
    override suspend fun copyItems(company: String?, template: String, version: Int, revision: Long, items: List<NovaChecklistItemSelection>) =
        service.copyItems(identity, company, template, version, revision, items)
    override suspend fun reorderItems(company: String?, template: String, version: Int, revision: Long, itemCodes: List<String>) =
        service.reorderItems(identity, company, template, version, revision, itemCodes)
    override suspend fun removeItem(company: String?, template: String, version: Int, revision: Long, itemCode: String) =
        service.removeItem(identity, company, template, version, revision, itemCode)
    override suspend fun publishTemplate(company: String?, template: String, version: Int, revision: Long, note: String) =
        service.publishTemplate(identity, company, template, version, revision, note)
    override suspend fun copyTemplate(company: String?, template: String, title: String?) = service.copyTemplate(identity, company, template, title)
    override suspend fun assignTemplate(company: String, workplace: String?, template: String) = service.assignTemplate(identity, company, workplace, template)
    override suspend fun deactivateAssignment(company: String, assignment: String) = service.deactivateAssignment(identity, company, assignment)
    override fun pendingAnswers() = queue.count(identity) to queue.conflictCount(identity)
    override suspend fun syncPendingAnswers(): Pair<Int, Int> {
        queue.flush(identity) { company, draft -> service.recordAnswer(identity, company, draft) }
        return pendingAnswers()
    }
}

internal fun checklistMessage(error: Throwable) = when (error) {
    is NovaChecklistException -> error.failure.message
    is NovaFileException -> error.failure.message
    else -> NovaChecklistFailure.unavailable.message
}

private val dayOutput = DateTimeFormatter.ofPattern("d MMM yyyy", Locale.forLanguageTag("tr-TR"))
internal fun checklistDay(value: String) = runCatching { LocalDate.parse(value).format(dayOutput) }.getOrDefault(value)

private fun NovaChecklistResult.status() = when (this) {
    NovaChecklistResult.conform -> NovaStatus.Success; NovaChecklistResult.nonconform -> NovaStatus.Warning; NovaChecklistResult.notApplicable -> NovaStatus.Neutral
}

/** A centred message with an optional retry (iOS `NovaChecklistMessageState`). */
@Composable
internal fun ChecklistMessage(symbol: String, title: String, message: String, actionTitle: String? = null, action: () -> Unit = {}) {
    Column(Modifier.fillMaxWidth().padding(vertical = 36.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        NovaIcon(symbol, 30.dp, tint = NovaColorToken.textMuted.color())
        NovaText(title, style = NovaTypeToken.cardTitle, textAlign = TextAlign.Center)
        NovaText(message, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color(), textAlign = TextAlign.Center)
        actionTitle?.let { NovaButton(it, action, Modifier.widthIn(max = 220.dp), variant = NovaButtonVariant.Surface, symbol = "arrow.clockwise") }
    }
}

/** A plain header with a labelled back control and a centred title (the checklist flows' own header). */
@Composable
internal fun ChecklistHeader(title: String, backTitle: String, back: () -> Unit, action: @Composable () -> Unit = {}) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)) {
        Row(Modifier.align(Alignment.CenterStart).heightIn(min = 44.dp).novaRowPress(onClick = back), horizontalArrangement = Arrangement.spacedBy(5.dp),
            verticalAlignment = Alignment.CenterVertically) {
            NovaIcon("chevron.left", 13.dp); NovaText(backTitle, style = NovaTypeToken.buttonSm)
        }
        NovaText(title, Modifier.align(Alignment.Center).padding(horizontal = 100.dp), NovaTypeToken.label, maxLines = 1)
        Box(Modifier.align(Alignment.CenterEnd)) { action() }
    }
}

/** A sticky bottom action above the tab bar. */
@Composable
internal fun ChecklistBottomAction(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(bottom = novaTabBarClearance)) {
        Column(Modifier.fillMaxWidth().background(NovaColorToken.surface.color(), RoundedCornerShape(bottomStart = 22.dp, bottomEnd = 22.dp))
            .padding(horizontal = 20.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(9.dp), content = content)
    }
}

/** Kontroller (iOS `NovaChecklistScreen`). */
@Composable
fun NovaChecklistScreen(client: NovaChecklistClient, canWrite: Boolean, onBack: () -> Unit, initialCompany: String? = null, headingOverride: String? = null,
                        /** A run to open as soon as the screen appears ("Senin İçin" continues an open check). */
                        initialRunId: String? = null) {
    val coroutines = rememberCoroutineScope()
    var board by remember { mutableStateOf<NovaChecklistBoard?>(null) }
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var query by remember { mutableStateOf(NovaChecklistQuery(company = initialCompany)) }
    var loading by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    var showingFilters by remember { mutableStateOf(false) }
    var showingStart by remember { mutableStateOf(false) }
    var showingLists by remember { mutableStateOf(false) }
    var showingWizard by remember { mutableStateOf(false) }
    var detail by remember { mutableStateOf<NovaChecklistRun?>(null) }
    var preselectedTemplate by remember { mutableStateOf<String?>(null) }
    var pending by remember { mutableStateOf(0 to 0) }
    suspend fun load(reset: Boolean) {
        query = if (reset) query.copy(offset = 0) else query.copy(offset = query.offset + query.limit)
        loading = true; failure = null
        try {
            if (companies.isEmpty()) companies = client.companies()
            val answer = client.board(query)
            val existing = board
            board = if (reset || existing == null) answer else answer.copy(rows = existing.rows + answer.rows)
        } catch (error: Exception) {
            failure = (error as? NovaChecklistException)?.failure?.message ?: "İnternet bağlantınızı kontrol edip yeniden deneyin."
        }
        loading = false
    }
    suspend fun sync() { pending = client.syncPendingAnswers() }
    fun reload() = coroutines.launch { load(true) }
    suspend fun act(run: NovaChecklistRun, work: suspend () -> NovaChecklistRun?): String? = try {
        work()?.let { detail = it }; load(true); null
    } catch (error: Exception) { checklistMessage(error) }
    val open = detail
    if (open != null) {
        ChecklistRunTask(open, canWrite, onAnswer = { input ->
            try {
                var draft = input.copy(expectedRevision = open.revision)
                draft.attachment?.let { attachment ->
                    val company = open.companyId ?: return@ChecklistRunTask "Bağımsız kontrole firma kanıtı eklenemez."
                    draft = draft.copy(evidenceAssetId = client.uploadEvidence(company, attachment), attachment = null)
                }
                detail = client.answer(open.companyId, draft) ?: optimistic(draft, open)
                pending = client.pendingAnswers()
                load(true); null
            } catch (error: Exception) { checklistMessage(error) }
        }, onSubmit = { act(open) { client.submit(open.companyId, open.id, open.revision) } },
            onCancel = { act(open) { client.cancel(open.companyId, open.id, open.revision) } },
            onRevise = { act(open) { client.revise(open.companyId, open.id, open.revision, NovaDay.today()) } },
            onClose = { detail = null; reload() })
        return
    }
    if (showingStart) {
        ChecklistStartFlow(client, initialCompany, preselectedTemplate, onStarted = { run ->
            preselectedTemplate = null; showingStart = false; detail = run
        }, onClose = { showingStart = false; reload() })
        return
    }
    if (showingLists) {
        NovaChecklistListsScreen(client, canWrite, initialCompany, onBack = { showingLists = false }, onStart = { template ->
            preselectedTemplate = template; showingLists = false; showingStart = true
        })
        return
    }
    if (showingWizard) {
        ChecklistWizard(client, initialCompany ?: query.company, onStart = { template ->
            preselectedTemplate = template; showingWizard = false; showingStart = true
        }, onBack = { showingWizard = false; reload() })
        return
    }
    LaunchedEffect(Unit) {
        sync()
        initialRunId?.let { id -> runCatching { client.detail(id) }.getOrNull()?.let { detail = it } }
        load(true)
    }
    LaunchedEffect(query.search) { delay(280); if (board != null) load(true) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        NovaListHeading(headingOverride ?: "Kontroller", onBack, actionBelow = true) {
            if (canWrite) NovaListActionButton("Yeni kontrol", "plus", identifier = "nova.checklist.start") { showingStart = true }
        }
        if (canWrite) NovaButton(NovaChecklistWords.openWizard, { showingWizard = true }, Modifier.testTag("nova.checklist.wizard"), symbol = "sparkles",
            variant = NovaButtonVariant.Surface)
        Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).novaRowPress { showingLists = true }.testTag("nova.checklist.lists.open").padding(vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon("list.bullet.rectangle", 17.dp, Modifier.width(28.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                NovaText("Kontrol Listeleri", style = NovaTypeToken.label)
                NovaText("Hazır listeleri bulun veya kendi listelerinizi yönetin.", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            }
            NovaIcon("chevron.right", 12.dp, tint = NovaColorToken.textMuted.color())
        }
        if (pending.first > 0) Row(Modifier.fillMaxWidth().background(NovaColorToken.statusWarningBg.color(), RoundedCornerShape(12.dp)).padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            NovaIcon(if (pending.second > 0) "exclamationmark.arrow.triangle.2.circlepath" else "icloud.slash", 14.dp)
            NovaText(if (pending.second > 0) "${pending.first} çevrimdışı yanıt bekliyor; ${pending.second} yanıt yeniden doğrulanmalı."
                else "Çevrimdışısınız. ${pending.first} değişiklik cihazda güvenle bekliyor.", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        }
        NovaSegmentedControl(NovaChecklistRunState.entries.map { it.title }, NovaChecklistRunState.entries.indexOfFirst { it.wire == query.state }.coerceAtLeast(0),
            Modifier.testTag("nova.checklist.state.picker")) { index -> query = query.copy(state = NovaChecklistRunState.entries[index].wire); reload() }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { NovaSearchCapsule(query.search, "Kontrol ara", "nova.checklist.search") { query = query.copy(search = it) } }
            Box(Modifier.size(46.dp).clip(RoundedCornerShape(12.dp)).background(NovaColorToken.surface.color(), RoundedCornerShape(12.dp))
                .novaRowPress { showingFilters = true }.semantics { contentDescription = if (query.company == null) "Filtre" else "Filtre, 1 etkin" }
                .testTag("nova.checklist.filter"), contentAlignment = Alignment.Center) {
                NovaIcon("line.3.horizontal.decrease", 16.dp)
                if (query.company != null) Box(Modifier.align(Alignment.TopEnd).padding(7.dp).size(9.dp).background(NovaColorToken.accent.color(), CircleShape))
            }
        }
        board?.let { NovaText("${it.count(NovaChecklistRunState.`open`)} devam eden · ${it.count(NovaChecklistRunState.submitted)} tamamlanan",
            style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color()) }
        val shown = board
        val state = NovaChecklistRunState.of(query.state) ?: NovaChecklistRunState.`open`
        when {
            loading && shown == null -> NovaLoadingView("Kontroller yükleniyor…", Modifier.heightIn(max = 220.dp))
            failure != null -> ChecklistMessage("wifi.exclamationmark", "Kontrol bilgileri yüklenemedi", failure!!, "Yeniden dene") { reload() }
            shown != null && shown.rows.isEmpty() -> ChecklistMessage("checklist",
                when (state) { NovaChecklistRunState.`open` -> "Devam eden kontrol yok"; NovaChecklistRunState.submitted -> "Tamamlanan kontrol yok"; else -> "İptal edilen kontrol yok" },
                if (query.search.isEmpty() && query.company == null) "Bu durumdaki kontroller burada görünecek." else "Arama kelimenizi veya filtreleri değiştirin.")
            shown != null -> NovaListEntrance(true) {
                Column {
                    shown.rows.forEachIndexed { index, run ->
                        ChecklistRunRow(run, Modifier.novaRowEntrance(index)) {
                            coroutines.launch { detail = runCatching { client.detail(run.id) }.getOrDefault(run) }
                        }
                        NovaDivider()
                    }
                    if (shown.hasMore) NovaButton("Daha fazla göster", { coroutines.launch { load(false) } }, Modifier.padding(top = 14.dp),
                        variant = NovaButtonVariant.Surface, symbol = "chevron.down")
                }
            }
        }
    }
    NovaPopup(showingFilters, { showingFilters = false }, identifier = "nova.checklist.filter.sheet") {
        NovaPopupHeading("Filtre", symbol = "line.3.horizontal.decrease")
        NovaText("Firma", style = NovaTypeToken.label)
        (listOf<NovaCompanyOption?>(null) + companies).forEach { option ->
            val on = query.company == option?.id
            Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).novaRowPress { query = query.copy(company = option?.id) }.semantics { selected = on },
                verticalAlignment = Alignment.CenterVertically) {
                NovaText(option?.name ?: "Tüm firmalar", Modifier.weight(1f))
                if (on) NovaIcon("checkmark", 13.dp)
            }
        }
        if (query.company != null) NovaButton("Tüm filtreleri temizle", { query = query.copy(company = null) }, variant = NovaButtonVariant.Muted)
        NovaButton("Uygula", { showingFilters = false; reload() }, symbol = "checkmark")
    }
}

/** The answers as they will read once the queued one is sent (iOS `NovaChecklistOptimisticAnswer`). */
private fun optimistic(draft: NovaChecklistAnswerDraft, run: NovaChecklistRun): NovaChecklistRun {
    val answers = run.answers.map { answer ->
        if (answer.itemCode != draft.itemCode) answer
        else answer.copy(result = draft.resultValue, note = draft.note, evidenceAssetId = draft.evidenceAssetId ?: answer.evidenceAssetId)
    }
    val answered = answers.count { it.isAnswered }
    return run.copy(answers = answers, answered = answered, remaining = maxOf(0, run.expected - answered),
        conform = answers.count { it.result == NovaChecklistResult.conform }, nonconform = answers.count { it.result == NovaChecklistResult.nonconform },
        notApplicable = answers.count { it.result == NovaChecklistResult.notApplicable },
        progressPercent = if (run.expected > 0) answered * 100.0 / run.expected else null)
}

/** Only a run with no company is standalone; a company run whose name did not come back
 *  still reads as a company inspection. */
private fun checklistRunScope(run: NovaChecklistRun): String =
    listOfNotNull(run.companyName?.takeIf { it.isNotBlank() }, run.workplaceName?.takeIf { it.isNotBlank() })
        .joinToString(" · ").ifEmpty { if (run.companyId == null) "Bağımsız kontrol" else "Firma kontrolü" }

@Composable
private fun ChecklistRunRow(run: NovaChecklistRun, modifier: Modifier, onClick: () -> Unit) {
    val scope = checklistRunScope(run)
    Column(modifier.fillMaxWidth().novaRowPress(onClick = onClick).padding(vertical = 14.dp).testTag("nova.checklist.row.${run.id}"),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                NovaText(run.templateTitle ?: run.templateCode, style = NovaTypeToken.cardTitle)
                NovaText(scope, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                NovaText(checklistDay(run.startedOn), style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
            }
            Box(Modifier.size(32.dp, 44.dp), contentAlignment = Alignment.Center) { NovaIcon("chevron.right", 12.dp, tint = NovaColorToken.textMuted.color()) }
        }
        when (run.state) {
            NovaChecklistRunState.`open` -> Column(Modifier.semantics(mergeDescendants = true) {
                contentDescription = "Kontrol ilerlemesi: ${run.expected} sorudan ${run.answered} tamamlandı"
            }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                NovaText("${run.answered} / ${run.expected}", style = NovaTypeToken.meta)
                LinearProgressIndicator({ run.answered.toFloat() / maxOf(run.expected, 1) }, Modifier.fillMaxWidth(),
                    color = NovaColorToken.accentInk.color(), trackColor = NovaColorToken.surfaceMuted.color(), drawStopIndicator = {})
            }
            NovaChecklistRunState.submitted -> NovaText("${run.conform} uygun · ${run.nonconform} uygun değil · ${run.notApplicable} uygulanamaz",
                style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            else -> Unit
        }
        if (run.nonconformitiesOpened > 0) Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon("exclamationmark.triangle", 12.dp, tint = NovaColorToken.statusWarningInk.color())
            NovaText("${run.nonconformitiesOpened} uygunsuzluk", style = NovaTypeToken.meta, color = NovaColorToken.statusWarningInk.color())
        }
    }
}

private enum class StartStep { scope, list, details, information }

/** Starting a control: where, which list, then the day and site details (iOS `NovaChecklistStartFlowScreen`). */
@Composable
private fun ChecklistStartFlow(client: NovaChecklistClient, initialCompany: String?, preselectedTemplate: String?, onStarted: (NovaChecklistRun) -> Unit,
                               onClose: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    var step by remember { mutableStateOf(StartStep.scope) }
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var company by remember { mutableStateOf<String?>(null) }
    var catalogue by remember { mutableStateOf<NovaChecklistCatalogue?>(null) }
    var selectedTemplate by remember { mutableStateOf<String?>(null) }
    var templateDetail by remember { mutableStateOf<NovaChecklistTemplateDetail?>(null) }
    var search by remember { mutableStateOf("") }
    var sector by remember { mutableStateOf<String?>(null) }
    var kind by remember { mutableStateOf<String?>(null) }
    var workplace by remember { mutableStateOf<String?>(null) }
    var day by remember { mutableStateOf(NovaDay.today()) }
    var area by remember { mutableStateOf("") }
    var equipment by remember { mutableStateOf("") }
    var document by remember { mutableStateOf("") }
    var showsSite by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(true) }
    var working by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    var chooser by remember { mutableStateOf<String?>(null) }
    val selectedCompany = companies.firstOrNull { it.id == company }
    val starters = catalogue?.starters.orEmpty()
    val selectedStarter = starters.firstOrNull { it.templateCode == selectedTemplate }
    suspend fun loadCatalogue(id: String?) {
        loading = true; failure = null
        try {
            val loaded = client.catalogue(id)
            catalogue = loaded
            workplace = if (id != null) loaded.workplaces.singleOrNull()?.id else null
            if (preselectedTemplate != null && loaded.starters.any { it.templateCode == preselectedTemplate }) selectedTemplate = preselectedTemplate
        } catch (error: Exception) { failure = (error as? NovaChecklistException)?.failure?.message ?: "Kontrol listeleri yüklenemedi. Seçimi yeniden deneyin." }
        loading = false
    }
    suspend fun selectCompany(id: String?) { company = id; loadCatalogue(id); if (failure == null) step = StartStep.list }
    LaunchedEffect(Unit) {
        loading = true; failure = null
        try { companies = client.companies(); if (initialCompany != null) selectCompany(initialCompany) }
        catch (_: Exception) { failure = "İnternet bağlantınızı kontrol edip yeniden deneyin." }
        loading = false
    }
    val goBack: () -> Unit = { when (step) { StartStep.scope -> onClose(); StartStep.list -> step = StartStep.scope; else -> step = StartStep.list } }
    androidx.activity.compose.BackHandler(onBack = goBack)
    val canStart = selectedTemplate != null && !working && (company == null || (catalogue?.workplaces?.size ?: 0) <= 1 || workplace != null)
    Column(Modifier.fillMaxSize()) {
        when (step) {
            StartStep.scope -> {
                ChecklistHeader("Yeni kontrol", "Vazgeç", onClose)
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp).padding(bottom = novaTabBarInset),
                    verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    NovaText("Kontrol nerede yapılacak?", style = NovaTypeToken.screenTitle)
                    when {
                        loading -> NovaLoadingView("Yükleniyor…", Modifier.heightIn(max = 200.dp))
                        failure != null -> ChecklistMessage("wifi.exclamationmark", "Kontrol kapsamı yüklenemedi", failure!!, "Yeniden dene") {
                            coroutines.launch { companies = runCatching { client.companies() }.getOrDefault(emptyList()); failure = null }
                        }
                        else -> {
                            if (initialCompany == null) { ScopeRow("Bağımsız kontrol", "Firma seçmeden kontrol yapın", "person.crop.square") { coroutines.launch { selectCompany(null) } }; NovaDivider() }
                            companies.filter { initialCompany == null || it.id == initialCompany }.forEach { item ->
                                ScopeRow(item.name, item.detail.ifEmpty { "Firma kapsamında kontrol yapın" }, "building.2") { coroutines.launch { selectCompany(item.id) } }
                                NovaDivider()
                            }
                        }
                    }
                }
            }
            StartStep.list -> {
                ChecklistHeader("Kontrol listesini seç", "Kapsam", { step = StartStep.scope })
                val needle = novaFold(search)
                val tokens = needle.split(' ').filter { it.isNotEmpty() }
                val seen = mutableSetOf<String>()
                val filtered = starters.filter { item ->
                    (sector == null || item.sectorCode == sector) && (kind == null || item.kind == kind) &&
                        novaFold(listOfNotNull(item.title, item.kindTitle, item.sectorCode, item.scopeNote).joinToString(" ")).let { text -> tokens.all { text.contains(it) } } &&
                        seen.add(novaFold(item.title) + ":" + (item.kind ?: "general"))
                }
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 14.dp, bottom = 30.dp + novaTabBarInset),
                    verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            NovaText(selectedCompany?.name ?: "Bağımsız kontrol", style = NovaTypeToken.label)
                            NovaText("Kontrol kapsamı", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                        }
                        NovaButton("Değiştir", { step = StartStep.scope }, variant = NovaButtonVariant.Muted, compact = true)
                    }
                    NovaHelpHint("Sektör, ekipman, faaliyet veya tehlikeye göre arayın; yalnızca işinize uygun listeyi seçin.")
                    NovaSearchCapsule(search, "Sektör, ekipman veya iş ara", "nova.checklist.start.search") { search = it }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        NovaChooserButton("Sektör", sector?.let(::sectorTitle) ?: "Tüm sektörler", "nova.checklist.start.sector", Modifier.weight(1f),
                            open = chooser == "sector") { chooser = if (chooser == "sector") null else "sector" }
                        NovaChooserButton("Liste türü", kind?.let { novaChecklistKindTitle(it) } ?: "Tüm türler", "nova.checklist.start.kind", Modifier.weight(1f),
                            open = chooser == "kind") { chooser = if (chooser == "kind") null else "kind" }
                    }
                    if (chooser == "sector") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm sektörler")) +
                        starters.mapNotNull { it.sectorCode }.distinct().sorted().map { NovaChooserOption(it, sectorTitle(it)) }, sector, "nova.checklist.start.sector.options") {
                        sector = it; chooser = null
                    }
                    if (chooser == "kind") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm türler")) +
                        starters.mapNotNull { it.kind }.distinct().sorted().map { NovaChooserOption(it, novaChecklistKindTitle(it) ?: "Genel") }, kind,
                        "nova.checklist.start.kind.options") { kind = it; chooser = null }
                    when {
                        loading -> NovaLoadingView("Listeler yükleniyor…", Modifier.heightIn(max = 200.dp))
                        failure != null -> ChecklistMessage("wifi.exclamationmark", "Kontrol listeleri yüklenemedi", failure!!, "Yeniden dene") {
                            coroutines.launch { loadCatalogue(company) }
                        }
                        filtered.isEmpty() -> ChecklistMessage("magnifyingglass", "Liste bulunamadı",
                            if (search.isEmpty()) "Yayımlanmış bir kontrol listesi bulunmuyor." else "Başka bir liste adı veya konu yazmayı deneyin.")
                        else -> filtered.forEach { starter ->
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f).heightIn(min = 64.dp).novaRowPress { selectedTemplate = starter.templateCode; failure = null; step = StartStep.details },
                                    verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically)) {
                                    NovaText(starter.title, style = NovaTypeToken.bodyStrong)
                                    NovaText("${starter.kindTitle} · ${starter.items} soru", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                                }
                                Box(Modifier.size(44.dp).novaRowPress {
                                    coroutines.launch {
                                        loading = true; failure = null; templateDetail = null; step = StartStep.information
                                        try { templateDetail = client.templateDetail(starter.templateCode) } catch (error: Exception) { failure = checklistMessage(error) }
                                        loading = false
                                    }
                                }.semantics { contentDescription = "Liste bilgilerini aç" }, contentAlignment = Alignment.Center) { NovaIcon("info.circle", 18.dp) }
                            }
                            NovaDivider()
                        }
                    }
                }
            }
            StartStep.details -> {
                ChecklistHeader("Kontrol ayrıntıları", "Liste seçimi", { step = StartStep.list })
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
                    DetailRow("Firma", selectedCompany?.name ?: "Bağımsız kontrol")
                    DetailRow("Liste", selectedStarter?.title ?: "—")
                    NovaDayField("Kontrol tarihi", day, { picked -> if ((NovaDay.parse(picked) ?: LocalDate.MAX) <= LocalDate.now()) day = picked }, "nova.checklist.start.day")
                    val workplaces = catalogue?.workplaces.orEmpty()
                    if (company != null && workplaces.size > 1) {
                        NovaChoiceField("İşyeri", "İşyeri seçin", "building.2", workplaces.map { NovaChoiceOption(it.id, it.name) }, workplace, { workplace = it },
                            "nova.checklist.start.workplace", searchable = true, boxed = true)
                    } else if (company != null) workplaces.firstOrNull()?.let { DetailRow("İşyeri", it.name) }
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).novaRowPress { showsSite = !showsSite }, verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                NovaText("Saha ayrıntıları", style = NovaTypeToken.label)
                                NovaText(if (listOf(area, equipment, document).all { it.isEmpty() }) "İsteğe bağlı" else "Ayrıntılar eklendi", style = NovaTypeToken.meta,
                                    color = NovaColorToken.textSecondary.color())
                            }
                            NovaIcon(if (showsSite) "chevron.up" else "chevron.down", 11.dp)
                        }
                        if (showsSite) {
                            NovaTextField("Bölüm / alan", area, { area = it }, identifier = "nova.checklist.start.area")
                            NovaTextField("Makine / ekipman", equipment, { equipment = it }, identifier = "nova.checklist.start.equipment")
                            NovaTextField("Belge numarası", document, { document = it }, identifier = "nova.checklist.start.document")
                        }
                    }
                    if (company == null) NovaText("Bağımsız kontrolde firma uygunsuzluğu veya firma kanıtı oluşturulmaz.", style = NovaTypeToken.meta,
                        color = NovaColorToken.textSecondary.color())
                    failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
                }
                ChecklistBottomAction {
                    NovaButton(if (working) "Başlatılıyor…" else "Kontrolü başlat", {
                        val template = selectedTemplate
                        if (canStart && template != null) coroutines.launch {
                            working = true; failure = null
                            try {
                                val created = client.startRun(company, workplace, template, day, area, equipment, document)
                                    ?: throw NovaChecklistException(NovaChecklistFailure.unavailable)
                                onStarted(runCatching { client.detail(created.id) }.getOrDefault(created))
                            } catch (error: Exception) { failure = checklistMessage(error) }
                            working = false
                        }
                    }, symbol = "play", enabled = canStart, loading = working)
                }
            }
            StartStep.information -> {
                ChecklistHeader("Liste bilgileri", "Liste seçimi", { step = StartStep.list })
                val detail = templateDetail
                when {
                    loading -> NovaLoadingView("Liste yükleniyor…", Modifier.padding(20.dp).heightIn(max = 200.dp))
                    detail != null -> {
                        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                            NovaText(detail.title, style = NovaTypeToken.screenTitle)
                            NovaText(listOfNotNull(novaChecklistKindTitle(detail.kind), "${detail.items.size} soru").joinToString(" · "), color = NovaColorToken.textSecondary.color())
                            detail.scopeNote?.takeIf { it.isNotEmpty() }?.let { NovaText(it) }
                            NovaText("Sorular", style = NovaTypeToken.sectionTitle)
                            detail.items.forEach { item ->
                                Row(Modifier.padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                    NovaText("${item.position}.", style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
                                    NovaText(item.prompt)
                                }
                                NovaDivider()
                            }
                        }
                        ChecklistBottomAction { NovaButton("Bu listeyi seç", { selectedTemplate = detail.templateCode; step = StartStep.details }, symbol = "checkmark") }
                    }
                    failure != null -> ChecklistMessage("wifi.exclamationmark", "Liste yüklenemedi", failure!!)
                }
            }
        }
    }
}

private fun sectorTitle(value: String) = value.replace('_', ' ').split(' ').joinToString(" ") { word ->
    word.replaceFirstChar { it.titlecase(Locale.forLanguageTag("tr-TR")) }
}

@Composable
private fun ScopeRow(title: String, subtitle: String, symbol: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().novaRowPress(onClick = onClick).padding(vertical = 15.dp), horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 20.dp, Modifier.width(30.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            NovaText(title, style = NovaTypeToken.cardTitle)
            NovaText(subtitle, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        }
        NovaIcon("chevron.right", 12.dp, tint = NovaColorToken.textMuted.color())
    }
}

@Composable
private fun DetailRow(title: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        NovaText(title, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        NovaText(value, style = NovaTypeToken.bodyStrong)
    }
}

private enum class RunPage { question, answers, summary, result, information, extras, nonconformity, notApplicable, cancel }

/** One control, question by question, then its summary and result (iOS `NovaChecklistRunTaskScreen`). */
@Composable
private fun ChecklistRunTask(run: NovaChecklistRun, canWrite: Boolean, onAnswer: suspend (NovaChecklistAnswerDraft) -> String?, onSubmit: suspend () -> String?,
                             onCancel: suspend () -> String?, onRevise: suspend () -> String?, onClose: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val context = LocalContext.current
    val ordered = remember(run) { run.answers.sortedBy { it.position } }
    var page by remember { mutableStateOf(if (run.state != NovaChecklistRunState.`open`) RunPage.result else if (run.remaining == 0) RunPage.summary else RunPage.question) }
    var currentIndex by remember { mutableIntStateOf(ordered.indexOfFirst { !it.isAnswered }.takeIf { it >= 0 } ?: maxOf(0, ordered.size - 1)) }
    var localDrafts by remember { mutableStateOf<Map<String, NovaChecklistAnswerDraft>>(emptyMap()) }
    var editing by remember { mutableStateOf<NovaChecklistAnswerDraft?>(null) }
    var cancellationReason by remember { mutableStateOf<String?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }
    var working by remember { mutableStateOf(false) }
    var confirmingExit by remember { mutableStateOf(false) }
    LaunchedEffect(run.state) { if (run.state != NovaChecklistRunState.`open`) page = RunPage.result }
    val scope = checklistRunScope(run)
    val current = ordered.getOrNull(currentIndex)
    fun draftFor(answer: NovaChecklistAnswer) = localDrafts[answer.itemCode] ?: NovaChecklistAnswerDraft(run.id, answer.itemCode, answer.prompt,
        answer.allowsNotApplicable, answer.verificationMethod, answer.helpText, answer.naReasonRequired, answer.evidenceRecommended, answer.photoRequired,
        (answer.result ?: NovaChecklistResult.conform).wire, answer.note.orEmpty(), answer.evidenceAssetId, openNonconformity = answer.nonconformityId != null,
        expectedRevision = run.revision)
    fun persist(draft: NovaChecklistAnswerDraft) = coroutines.launch {
        working = true; failure = onAnswer(draft); working = false
        if (failure != null) return@launch
        localDrafts = localDrafts - draft.itemCode; editing = null
        delay(350)
        if (currentIndex < ordered.size - 1) { currentIndex++; page = RunPage.question } else page = RunPage.summary
    }
    val requestExit: () -> Unit = { if (run.state == NovaChecklistRunState.`open`) confirmingExit = true else onClose() }
    androidx.activity.compose.BackHandler { when (page) { RunPage.question -> requestExit(); RunPage.result -> onClose(); else -> page = RunPage.question } }
    Column(Modifier.fillMaxSize()) {
        when (page) {
            RunPage.question -> {
                ChecklistHeader(run.templateTitle ?: run.templateCode, "Kontrolden çık", requestExit) {
                    Box(Modifier.heightIn(min = 44.dp).novaRowPress { page = RunPage.answers }.semantics { contentDescription = "Yanıtlar, ${run.answered} tamamlandı" },
                        contentAlignment = Alignment.Center) { NovaText("Yanıtlar ${run.answered}", style = NovaTypeToken.buttonSm) }
                }
                if (current == null) ChecklistMessage("checklist", "Bu kontrolde soru yok", "Kontrol listesi içeriği bulunamadı.")
                else {
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 14.dp, bottom = 20.dp),
                        verticalArrangement = Arrangement.spacedBy(20.dp)) {
                        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                            NovaText(scope, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                            NovaText("${run.answered} / ${run.expected}", style = NovaTypeToken.label)
                            LinearProgressIndicator({ run.answered.toFloat() / maxOf(run.expected, 1) }, Modifier.fillMaxWidth(), color = NovaColorToken.accentInk.color(),
                                trackColor = NovaColorToken.surfaceMuted.color(), drawStopIndicator = {})
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            NovaText("Soru ${current.position}", style = NovaTypeToken.sectionTitle, color = NovaColorToken.textSecondary.color())
                            NovaText(current.prompt, style = NovaTypeToken.screenTitle)
                        }
                        current.helpText?.takeIf { it.isNotEmpty() }?.let { help ->
                            NovaWhyDisclosure("Neye bakmalıyım?") { NovaText(help, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color()) }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            val note = localDrafts[current.itemCode]?.note ?: current.note.orEmpty()
                            val hasEvidence = localDrafts[current.itemCode]?.attachment != null || current.evidenceAssetId != null
                            Row(Modifier.heightIn(min = 44.dp).novaRowPress { editing = draftFor(current); page = RunPage.extras }, horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalAlignment = Alignment.CenterVertically) {
                                NovaIcon("note.text.badge.plus", 14.dp); NovaText(if (note.isEmpty()) "Not ekle" else "1 not", style = NovaTypeToken.label)
                            }
                            Row(Modifier.heightIn(min = 44.dp).novaRowPress { editing = draftFor(current); page = RunPage.extras }, horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalAlignment = Alignment.CenterVertically) {
                                NovaIcon("camera", 14.dp); NovaText(if (hasEvidence) "1 kanıt" else "Fotoğraf ekle", style = NovaTypeToken.label)
                            }
                        }
                        current.result?.let { result ->
                            Row(Modifier.fillMaxWidth().background(result.status().background.color(), RoundedCornerShape(12.dp)).padding(12.dp),
                                horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                                NovaIcon(result.symbol, 14.dp); NovaText(result.title, style = NovaTypeToken.label)
                                if (current.nonconformityId != null) NovaText("· Uygunsuzluk", style = NovaTypeToken.meta, color = NovaColorToken.statusWarningInk.color())
                            }
                        }
                        failure?.let { ErrorText(it) }
                    }
                    ChecklistBottomAction {
                        if (canWrite && run.state == NovaChecklistRunState.`open`) {
                            AnswerButton(NovaChecklistResult.conform, current.result == NovaChecklistResult.conform, working) {
                                persist(draftFor(current).copy(result = NovaChecklistResult.conform.wire, openNonconformity = false))
                            }
                            AnswerButton(NovaChecklistResult.nonconform, current.result == NovaChecklistResult.nonconform, working) {
                                editing = draftFor(current).copy(result = NovaChecklistResult.nonconform.wire, openNonconformity = !run.isPersonal); page = RunPage.nonconformity
                            }
                            if (current.allowsNotApplicable) AnswerButton(NovaChecklistResult.notApplicable, current.result == NovaChecklistResult.notApplicable, working) {
                                editing = draftFor(current).copy(result = NovaChecklistResult.notApplicable.wire, openNonconformity = false); page = RunPage.notApplicable
                            }
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Row(Modifier.heightIn(min = 44.dp).novaRowPress(enabled = currentIndex > 0 && !working) { currentIndex = maxOf(0, currentIndex - 1) },
                                horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                                NovaIcon("chevron.left", 12.dp); NovaText("Önceki", style = NovaTypeToken.buttonSm)
                            }
                            Spacer(Modifier.weight(1f))
                            Row(Modifier.heightIn(min = 44.dp).novaRowPress(enabled = current.isAnswered && !working) {
                                if (currentIndex < ordered.size - 1) currentIndex++ else page = RunPage.summary
                            }, horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                                NovaText(if (currentIndex == ordered.size - 1) "Özete git" else "Sonraki", style = NovaTypeToken.buttonSm); NovaIcon("chevron.right", 12.dp)
                            }
                        }
                    }
                }
            }
            RunPage.answers -> {
                ChecklistHeader("Yanıtlar", "Kontrole dön", { page = RunPage.question })
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 30.dp + novaTabBarInset)) {
                    ordered.forEachIndexed { index, answer ->
                        Row(Modifier.fillMaxWidth().novaRowPress { currentIndex = index; page = RunPage.question }.padding(vertical = 14.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            NovaIcon(answer.result?.symbol ?: "circle", 16.dp, Modifier.size(24.dp),
                                tint = answer.result?.status()?.ink?.color() ?: NovaColorToken.textMuted.color())
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                NovaText("${answer.position}. ${answer.prompt}")
                                NovaText(answer.result?.title ?: "Cevaplanmadı", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                            }
                            NovaIcon("chevron.right", 11.dp, tint = NovaColorToken.textMuted.color())
                        }
                        NovaDivider()
                    }
                }
            }
            RunPage.summary -> {
                ChecklistHeader("Kontrol özeti", "Kontrole dön", { page = RunPage.question })
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        NovaText(if (run.remaining == 0) "Kontrol tamamlanmaya hazır" else "Kontrol henüz tamamlanmadı", style = NovaTypeToken.screenTitle)
                        NovaText("${run.answered} / ${run.expected} soru yanıtlandı", color = NovaColorToken.textSecondary.color())
                    }
                    Column {
                        SummaryLine("Uygun", run.conform, "checkmark.circle"); NovaDivider()
                        SummaryLine("Uygun değil", run.nonconform, "exclamationmark.triangle"); NovaDivider()
                        SummaryLine("Uygulanamaz", run.notApplicable, "minus.circle"); NovaDivider()
                        SummaryLine("Uygunsuzluk kaydı", run.nonconformitiesOpened, "exclamationmark.bubble")
                    }
                    Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).novaRowPress { page = RunPage.answers }, verticalAlignment = Alignment.CenterVertically) {
                        NovaText("Yanıtları gözden geçir", Modifier.weight(1f), NovaTypeToken.label); NovaIcon("chevron.right", 12.dp)
                    }
                    if (canWrite && run.state == NovaChecklistRunState.`open`) Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).novaRowPress { page = RunPage.cancel },
                        verticalAlignment = Alignment.CenterVertically) {
                        NovaText("Kontrolü iptal et", Modifier.weight(1f), NovaTypeToken.label, NovaColorToken.statusDangerInk.color())
                    }
                    failure?.let { ErrorText(it) }
                }
                ChecklistBottomAction {
                    NovaButton(if (working) "Tamamlanıyor…" else "Kontrolü tamamla", {
                        if (run.remaining == 0) coroutines.launch { working = true; failure = onSubmit(); working = false; if (failure == null) page = RunPage.result }
                    }, symbol = "checkmark.circle", enabled = run.remaining == 0, loading = working)
                }
            }
            RunPage.result -> {
                ChecklistHeader(if (run.state == NovaChecklistRunState.cancelled) "Kontrol iptal edildi" else "Kontrol sonucu", "Kontroller", onClose)
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp).padding(bottom = novaTabBarInset),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    val cancelled = run.state == NovaChecklistRunState.cancelled
                    NovaIcon(if (cancelled) "xmark.circle" else "checkmark.circle.fill", 52.dp,
                        tint = if (cancelled) NovaColorToken.textMuted.color() else NovaColorToken.statusSuccessInk.color())
                    NovaText(if (cancelled) "Kontrol iptal edildi" else "Kontrol tamamlandı", style = NovaTypeToken.screenTitle, textAlign = TextAlign.Center)
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        NovaText(run.templateTitle ?: run.templateCode, style = NovaTypeToken.cardTitle, textAlign = TextAlign.Center)
                        NovaText(scope, color = NovaColorToken.textSecondary.color())
                        NovaText(checklistDay(run.startedOn), style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
                    }
                    if (run.state == NovaChecklistRunState.submitted) {
                        Column {
                            SummaryLine("Soru", run.expected, "list.number"); NovaDivider()
                            SummaryLine("Uygun", run.conform, "checkmark.circle"); NovaDivider()
                            SummaryLine("Uygun değil", run.nonconform, "exclamationmark.triangle"); NovaDivider()
                            SummaryLine("Uygulanamaz", run.notApplicable, "minus.circle")
                        }
                        NovaButton("Raporu görüntüle", {
                            runCatching { novaShareFile(context, NovaChecklistExport.pdf(run), NovaChecklistExport.name(run.id, "pdf"), "application/pdf") }
                                .onFailure { failure = "Rapor oluşturulamadı." }
                        }, symbol = "doc.richtext")
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            NovaButton("Excel", {
                                runCatching { novaShareFile(context, NovaChecklistExport.xlsx(run), NovaChecklistExport.name(run.id, "xlsx"), NovaXlsx.MIME) }
                                    .onFailure { failure = "Excel dosyası oluşturulamadı." }
                            }, Modifier.weight(1f), variant = NovaButtonVariant.Surface, symbol = "tablecells")
                            if (canWrite) NovaButton("Yeni doğrulama", {
                                coroutines.launch { working = true; failure = onRevise(); working = false; if (failure == null) { currentIndex = 0; page = RunPage.question } }
                            }, Modifier.weight(1f), variant = NovaButtonVariant.Surface, symbol = "arrow.triangle.2.circlepath", enabled = !working)
                        }
                    }
                    failure?.let { ErrorText(it) }
                    NovaButton("Kontrollerime dön", onClose, variant = NovaButtonVariant.Surface, symbol = "chevron.left")
                }
            }
            RunPage.information -> {
                ChecklistHeader("Kontrol bilgileri", "Kontrole dön", { page = RunPage.question })
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
                    DetailRow("Liste", run.templateTitle ?: run.templateCode)
                    DetailRow("Liste sürümü", "v${run.templateVersion}")
                    DetailRow("Kontrol tarihi", checklistDay(run.startedOn))
                    DetailRow("Kapsam", scope)
                    run.areaLabel?.takeIf { it.isNotEmpty() }?.let { DetailRow("Bölüm / alan", it) }
                    run.equipmentLabel?.takeIf { it.isNotEmpty() }?.let { DetailRow("Makine / ekipman", it) }
                    if (run.sourceIds.isNotEmpty()) DetailRow("Kaynaklar", run.sourceIds.joinToString(" · "))
                    NovaText("Bu kontrol, başladığı andaki soru sürümünü saklar. Sonraki liste değişiklikleri bu kaydı değiştirmez.", style = NovaTypeToken.meta,
                        color = NovaColorToken.textSecondary.color())
                }
            }
            RunPage.extras -> {
                var draft by remember(editing) { mutableStateOf(editing ?: NovaChecklistAnswerDraft()) }
                ChecklistHeader("Not ve fotoğraf", "Geri", { page = RunPage.question })
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    NovaText(draft.prompt, style = NovaTypeToken.bodyStrong)
                    NovaTextField("Not", draft.note, { draft = draft.copy(note = it) }, identifier = "nova.checklist.extras.note", multiline = true)
                    ChecklistAttachmentField("Fotoğraf veya belge ekle", "Görsel, PDF veya Office belgesi · en fazla 50 MB", draft.attachment) { draft = draft.copy(attachment = it) }
                    NovaText("Not ve kanıt, soruyu yanıtladığınızda kaydedilir.", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                }
                ChecklistBottomAction {
                    NovaButton("Kaydet", { localDrafts = localDrafts + (draft.itemCode to draft); editing = draft; page = RunPage.question }, symbol = "checkmark")
                }
            }
            RunPage.notApplicable -> {
                var draft by remember(editing) { mutableStateOf(editing ?: NovaChecklistAnswerDraft()) }
                ChecklistHeader("Uygulanamaz", "Geri", { page = RunPage.question })
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    NovaText(draft.prompt, style = NovaTypeToken.bodyStrong)
                    NovaTextField("Neden uygulanamaz? *", draft.note, { draft = draft.copy(note = it) }, identifier = "nova.checklist.na.reason", multiline = true)
                    failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
                }
                ChecklistBottomAction {
                    NovaButton(if (working) "Kaydediliyor…" else "Kaydet ve devam et", { persist(draft) }, symbol = "checkmark", enabled = draft.note.isNotBlank(),
                        loading = working)
                }
            }
            RunPage.nonconformity -> {
                var draft by remember(editing) { mutableStateOf(editing ?: NovaChecklistAnswerDraft()) }
                var description by remember(editing) { mutableStateOf(current?.note ?: draft.note) }
                var recommendation by remember(editing) { mutableStateOf("") }
                var severity by remember(editing) { mutableStateOf<NovaChecklistSeverity?>(null) }
                val companyName = run.companyName
                val canSave = description.isNotBlank() && (companyName == null || severity != null) &&
                    (!draft.photoRequired || draft.attachment != null || draft.evidenceAssetId != null)
                ChecklistHeader("Uygunsuzluk", "Geri", { page = RunPage.question })
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        NovaText("Soru", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                        NovaText(draft.prompt, style = NovaTypeToken.bodyStrong)
                    }
                    NovaTextField("Açıklama *", description, { description = it }, identifier = "nova.checklist.issue.description", multiline = true,
                        placeholder = "Tespit edilen durumu yazın…")
                    ChecklistAttachmentField(if (draft.photoRequired) "Fotoğraf ekle *" else "Fotoğraf ekle", "Görsel, PDF veya Office belgesi · en fazla 50 MB",
                        draft.attachment) { draft = draft.copy(attachment = it) }
                    if (companyName != null) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            NovaText("Önem *", style = NovaTypeToken.label)
                            NovaChecklistSeverity.entries.forEach { value ->
                                val on = severity == value
                                Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).novaRowPress { severity = value }.semantics { role = Role.RadioButton; selected = on },
                                    horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    NovaIcon(if (on) "largecircle.fill.circle" else "circle", 14.dp, tint = NovaColorToken.accentInk.color()); NovaText(value.title)
                                }
                            }
                        }
                        NovaDayField("Düzeltme tarihi", draft.dueOn, { draft = draft.copy(dueOn = it) }, "nova.checklist.issue.due", clearable = true)
                    }
                    NovaTextField("Düzeltme önerisi", recommendation, { recommendation = it }, identifier = "nova.checklist.issue.recommendation", multiline = true,
                        placeholder = "İsteğe bağlı açıklama ekleyin…")
                    NovaText(if (companyName != null) "Uygunsuzluk kaydı · $companyName"
                        else "Bağımsız kontrolde firma uygunsuzluğu açılmaz; olumsuz gözlem yalnız bu kontrolde saklanır.",
                        style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                    failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
                }
                ChecklistBottomAction {
                    NovaButton(if (working) "Kaydediliyor…" else "Kaydet ve devam et", {
                        if (canSave) {
                            val clean = description.trim(); val advice = recommendation.trim()
                            persist(draft.copy(result = NovaChecklistResult.nonconform.wire, openNonconformity = companyName != null,
                                severity = (severity ?: NovaChecklistSeverity.medium).wire,
                                note = if (advice.isEmpty()) clean else "$clean\n\nDüzeltme önerisi: $advice"))
                        }
                    }, symbol = "checkmark", enabled = canSave, loading = working)
                }
            }
            RunPage.cancel -> {
                val reasons = linkedMapOf("not_required" to "Kontrol artık gerekli değil", "wrong_scope" to "Yanlış kapsam veya liste seçildi",
                    "site_unavailable" to "Saha koşulları uygun değil", "other" to "Diğer")
                ChecklistHeader("Kontrolü iptal et", "Kontrole dön", { page = RunPage.question })
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    NovaText("Bu kontrol tamamlanmış sayılmayacak. Kaydedilmiş yanıtlar geçmişte kalacak.", color = NovaColorToken.textSecondary.color())
                    NovaChoiceField("İptal nedeni *", "İptal nedeni seçin", "xmark.circle", reasons.map { (key, label) -> NovaChoiceOption(key, label) },
                        cancellationReason, { cancellationReason = it }, "nova.checklist.cancel.reason", boxed = true)
                    failure?.let { ErrorText(it) }
                }
                ChecklistBottomAction {
                    NovaButton(if (working) "İptal ediliyor…" else "Kontrolü iptal et", {
                        coroutines.launch { working = true; failure = onCancel(); working = false; if (failure == null) page = RunPage.result }
                    }, variant = NovaButtonVariant.Danger, symbol = "xmark.circle", enabled = cancellationReason != null, loading = working)
                }
            }
        }
    }
    NovaPopup(confirmingExit, { confirmingExit = false }) {
        NovaPopupHeading("Kontrolden çıkmak istiyor musunuz?", symbol = "rectangle.portrait.and.arrow.right")
        NovaText("Cevaplarınız kaydedildi. Daha sonra kaldığınız yerden devam edebilirsiniz.")
        NovaButton("Kontrolden çık", { confirmingExit = false; onClose() }, variant = NovaButtonVariant.Surface)
        NovaButton("Kontrolde kal", { confirmingExit = false })
    }
}

@Composable
private fun ErrorText(text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        NovaIcon("exclamationmark.circle", 13.dp, tint = NovaColorToken.statusDangerInk.color())
        NovaText(text, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color())
    }
}

@Composable
private fun SummaryLine(title: String, value: Int, symbol: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 13.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 14.dp, Modifier.width(24.dp)); NovaText(title, Modifier.weight(1f)); NovaText("$value", style = NovaTypeToken.label)
    }
}

@Composable
private fun AnswerButton(result: NovaChecklistResult, selected: Boolean, working: Boolean, onClick: () -> Unit) {
    val status = result.status()
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(12.dp)).background(status.background.color(), RoundedCornerShape(12.dp))
        .then(if (selected) Modifier.border(1.5.dp, status.ink.color(), RoundedCornerShape(12.dp)) else Modifier)
        .novaRowPress(enabled = !working, onClick = onClick).padding(horizontal = 16.dp)
        .semantics { contentDescription = "Bu soruyu ${result.title.lowercase(Locale.forLanguageTag("tr-TR"))} olarak işaretle"; this.selected = selected },
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(result.symbol, 17.dp); NovaText(result.title, Modifier.weight(1f), NovaTypeToken.buttonSm)
        if (selected) NovaIcon("checkmark", 13.dp)
    }
}

/** Picks one evidence file to upload with the answer (iOS `IsgWorkspaceInlineAttachmentField`). */
@Composable
internal fun ChecklistAttachmentField(title: String, help: String, attachment: NovaChecklistAttachment?, onChange: (NovaChecklistAttachment?) -> Unit) {
    val context = LocalContext.current
    var failure by remember { mutableStateOf<String?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        failure = null
        runCatching {
            val resolver = context.contentResolver
            val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null } ?: "kanit"
            val bytes = resolver.openInputStream(uri)?.use { it.readBytes() } ?: error("empty")
            if (bytes.size > 50 * 1024 * 1024) { failure = "Dosya 50 MB sınırını aşıyor."; return@runCatching }
            onChange(NovaChecklistAttachment(name.substringBeforeLast('.'), name, bytes))
        }.onFailure { failure = "Dosya okunamadı." }
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        NovaText(title, style = NovaTypeToken.label)
        if (attachment != null) Row(Modifier.fillMaxWidth().novaControlBackground(14.dp).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically) {
            NovaIcon("doc.fill", 13.dp, tint = NovaColorToken.statusSuccessInk.color())
            NovaText(attachment.fileName, Modifier.weight(1f), NovaTypeToken.meta, maxLines = 1)
            Box(Modifier.size(36.dp).novaRowPress { onChange(null) }.semantics { contentDescription = "Dosyayı kaldır" }, contentAlignment = Alignment.Center) {
                NovaIcon("xmark.circle", 13.dp)
            }
        } else NovaButton("Dosya seç", {
            picker.launch(arrayOf("image/*", "application/pdf", "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "application/vnd.ms-excel", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
        }, variant = NovaButtonVariant.Surface, symbol = "paperclip")
        NovaText(help, style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
        failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
    }
}

/** Checklist exports (iOS `NovaChecklistExport`). */
internal object NovaChecklistExport {
    private const val notice = "Bu çıktı bir uzman çalışma kaydıdır; tek başına mevzuata uygunluk kararı değildir."

    fun name(identifier: String, extension: String) =
        "kontrol-listesi-${identifier.lowercase().map { if (it.isLetterOrDigit() || it == '-') it else '-' }.joinToString("").take(80)}.$extension"

    private fun percent(value: Double?) = value?.let { "%${Math.round(it)}" }

    private fun pdf(title: String, subtitle: String, version: Int, rows: List<List<String>>): ByteArray {
        val writer = NovaPdfWriter({ "İSGADA · $title" }) { page -> "İSGADA · Kontrol Listesi · v$version · Sayfa $page" }
        writer.paragraph(title, 18f, true, after = 8f)
        writer.paragraph(subtitle, 10f, after = 8f)
        writer.paragraph(notice, 8f, after = 8f)
        rows.forEach { (position, prompt, answer, note) ->
            writer.paragraph("$position. $prompt", 10f, true, after = 8f)
            if (answer.isNotEmpty()) writer.paragraph("Yanıt: $answer", 10f, after = 8f)
            if (note.isNotEmpty()) writer.paragraph("Açıklama: $note", 10f, after = 8f)
            if (answer.isEmpty()) writer.paragraph("☐ Uygun    ☐ Uygun Değil    ☐ Gerekli Değil    Açıklama: ____________________", 10f, after = 8f)
            writer.space(4f)
        }
        writer.ensure(80f)
        writer.paragraph("Uzman / İmza                                      Firma yetkilisi / İmza", 10f, true)
        return writer.finish()
    }

    fun pdf(run: NovaChecklistRun) = pdf(run.templateTitle ?: run.templateCode,
        listOfNotNull(run.companyName, run.workplaceName, run.startedOn, "Uygun ${run.conform}", "Uygun değil ${run.nonconform}",
            "Uygulanamaz ${run.notApplicable}", percent(run.scorePercent)?.let { "Uygunluk $it" }, percent(run.applicableCoveragePercent)?.let { "Kapsam $it" })
            .joinToString(" · "), run.templateVersion,
        run.answers.map { listOf(it.position.toString(), it.prompt, it.result?.title ?: "Yanıtsız", it.note.orEmpty()) })

    fun pdf(template: NovaChecklistTemplateDetail) = pdf(template.title, "Boş kontrol listesi · ${template.catalogTemplateCode ?: template.templateCode}",
        template.version, template.items.map { listOf(it.position.toString(), it.prompt, "", "") })

    private fun workbook(title: String, metadata: List<List<String>>, rows: List<List<String>>, sources: List<String>): ByteArray {
        val summary = listOf(listOf("Kontrol listesi", title), listOf("Uyarı", "Uzman çalışma aracıdır; tek başına mevzuata uygunluk kararı değildir.")) + metadata
        val items = listOf(listOf("Sıra", "Madde kodu", "Bölüm", "Alan / ekipman kapsamı", "Soru", "Doğrulama", "Yanıt", "Açıklama", "Kanıt referansı",
            "Uygunsuzluk referansı", "Sorumlu", "Termin")) + rows
        val sourceRows = listOf(listOf("Kaynak kimliği", "Not")) + if (sources.isEmpty()) listOf(listOf("", "Bu listeye bağlı kaynak kaydı yok."))
            else sources.sorted().map { listOf(it, "Katalog sürümünde sabitlenmiş kaynak kaydı") }
        return NovaXlsx.workbook(listOf(NovaXlsx.Sheet("Özet", summary, listOf(26, 90)),
            NovaXlsx.Sheet("Maddeler", items, listOf(8, 18, 24, 24, 85, 16, 18, 45, 38, 38, 24, 16), freeze = true, filter = true),
            NovaXlsx.Sheet("Kaynaklar", sourceRows, listOf(28, 80), freeze = true, filter = true)))
    }

    fun xlsx(run: NovaChecklistRun) = workbook(run.templateTitle ?: run.templateCode, listOf(
        listOf("Firma", run.companyName.orEmpty()), listOf("İşyeri", run.workplaceName.orEmpty()), listOf("Tarih", run.startedOn),
        listOf("Sürüm", run.templateVersion.toString()), listOf("Belge no", run.documentNumber.orEmpty()), listOf("Alan", run.areaLabel.orEmpty()),
        listOf("Ekipman", run.equipmentLabel.orEmpty()), listOf("Kaynak kayıtları", run.sourceIds.joinToString(", ")),
        listOf("İlerleme", percent(run.progressPercent).orEmpty()), listOf("Kontrol kapsamı", percent(run.applicableCoveragePercent).orEmpty()),
        listOf("Uygunluk puanı", percent(run.scorePercent).orEmpty()), listOf("Uygun", run.conform.toString()), listOf("Uygun değil", run.nonconform.toString()),
        listOf("Uygulanamaz", run.notApplicable.toString())),
        run.answers.map { listOf(it.position.toString(), it.itemCode, it.sectionTitle.orEmpty(), it.scopeKey.orEmpty(), it.prompt, it.verificationMethod.orEmpty(),
            it.result?.title ?: "Yanıtsız", it.note.orEmpty(), it.evidenceAssetId?.lowercase().orEmpty(), it.nonconformityId?.lowercase().orEmpty(), "", "") },
        run.sourceIds)

    fun xlsx(template: NovaChecklistTemplateDetail) = workbook(template.title, listOf(
        listOf("Katalog kodu", template.catalogTemplateCode ?: template.templateCode), listOf("Sürüm", template.version.toString()),
        listOf("Durum", "Boş şablon"), listOf("Kaynak kayıtları", template.sourceIds.joinToString(", "))),
        template.items.map { listOf(it.position.toString(), it.itemCode, it.sectionTitle.orEmpty(), it.scopeKey.orEmpty(), it.prompt, it.verificationMethod.orEmpty(),
            "", "", "", "", "", "") }, template.sourceIds)
}
