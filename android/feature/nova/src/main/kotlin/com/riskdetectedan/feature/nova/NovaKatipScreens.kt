package com.riskdetectedan.feature.nova

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.launch

/** A filed document ready to share: its bytes and the name it opens under. */
data class NovaOpenedDocument(val bytes: ByteArray, val fileName: String, val mime: String)

/** The module's calls bound to one identity (iOS `NovaKatipClient`); the design preview supplies its own. */
interface NovaKatipClient {
    val companies: suspend () -> List<NovaCompanyOption>
    suspend fun catalogue(company: String?): NovaKatipCatalogue
    suspend fun board(query: NovaKatipQuery): NovaKatipBoard
    suspend fun detail(id: String): NovaKatipContract
    suspend fun record(company: String, draft: NovaKatipDraft): NovaKatipContract?
    suspend fun end(company: String, draft: NovaKatipEndDraft): NovaKatipContract?
    suspend fun archive(company: String, contract: String): NovaKatipContract?
    suspend fun openDocument(contract: String): NovaOpenedDocument
    suspend fun documents(company: String, offset: Int): List<NovaFileEntry>
    suspend fun linkDocument(contract: NovaKatipContract, file: String?): NovaKatipContract?
    fun hasPending(): Boolean
    suspend fun resume(): NovaKatipContract?
}

class NovaServiceKatipClient(private val service: NovaKatipService, private val files: NovaFileLibraryService, private val identity: IsgWorkspaceIdentity,
                             override val companies: suspend () -> List<NovaCompanyOption>) : NovaKatipClient {
    override suspend fun catalogue(company: String?) = service.catalogue(identity, company)
    override suspend fun board(query: NovaKatipQuery) = service.board(identity, query)
    override suspend fun detail(id: String) = service.detail(identity, id)
    override suspend fun record(company: String, draft: NovaKatipDraft) = service.record(identity, company, draft)
    override suspend fun end(company: String, draft: NovaKatipEndDraft) = service.end(identity, company, draft)
    override suspend fun archive(company: String, contract: String) = service.archive(identity, company, contract)
    /** Only a stored contract of the same company opens; the file is read through the archive, never a second path. */
    override suspend fun openDocument(contract: String): NovaOpenedDocument {
        val record = service.detail(identity, contract)
        val fileId = record.fileEntryId
        if (!record.contractStored || fileId == null) throw NovaKatipException(NovaKatipFailure.validation)
        val file = files.detail(identity, fileId)
        if (file.companyId != record.companyId) throw NovaKatipException(NovaKatipFailure.denied)
        val extension = file.fileExtension.filter { it.isLetterOrDigit() && it.code < 128 }
        return NovaOpenedDocument(files.contents(identity, file), "Sozlesme.$extension",
            android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension.lowercase()) ?: "application/octet-stream")
    }
    override suspend fun documents(company: String, offset: Int) =
        files.library(identity, NovaFileQuery(state = "promoted", company = company, limit = 20, offset = offset)).rows
    override suspend fun linkDocument(contract: NovaKatipContract, file: String?) = service.linkDocument(identity, contract, file)
    override fun hasPending() = runCatching { service.hasPending(identity) }.getOrDefault(false)
    override suspend fun resume() = service.resume(identity)
}

internal fun katipMessage(error: Throwable) = (error as? NovaKatipException)?.failure?.message ?: NovaKatipFailure.unavailable.message

private fun NovaKatipState.status() = when (this) {
    NovaKatipState.expired -> NovaStatus.Danger; NovaKatipState.expiring -> NovaStatus.Warning
    NovaKatipState.active, NovaKatipState.upcoming -> NovaStatus.Success; NovaKatipState.archived -> NovaStatus.Neutral
}

@Composable
private fun ContractCard(entry: NovaKatipContract, modifier: Modifier, onClick: () -> Unit) {
    NovaCard(modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onClick).testTag("nova.katip.row.${entry.id}"), padding = 14) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(entry.counterparty, style = NovaTypeToken.cardTitle)
                    NovaText(listOfNotNull(entry.scope, entry.workplaceName, entry.companyName).joinToString(" · "), style = NovaTypeToken.meta,
                        color = NovaColorToken.textSecondary.color())
                }
                NovaStatusPill(entry.state.title, entry.state.status())
            }
            NovaText(NovaKatipWords.explain(entry), style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaRowFact("calendar", "Başlangıç", NovaDay.label(entry.startsOn))
                NovaRowFact("doc.text", "Tür", entry.term.title)
                NovaRowFact("person", "Uzman", entry.expertContact)
            }
            entry.declaredMonthlyMinutes?.let { NovaTag("clock", "Beyan: ${NovaKatipWords.service(it)}", NovaStatus.Info) }
        }
    }
}

/** İSG-KATİP Sözleşmeleri (iOS `NovaKatipScreen`). */
@Composable
fun NovaKatipScreen(client: NovaKatipClient, canWrite: Boolean, onBack: () -> Unit, initialCompany: String? = null, headingOverride: String? = null) {
    val coroutines = rememberCoroutineScope()
    var board by remember { mutableStateOf<NovaKatipBoard?>(null) }
    var catalogue by remember { mutableStateOf<NovaKatipCatalogue?>(null) }
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var query by remember { mutableStateOf(NovaKatipQuery(company = initialCompany)) }
    var pending by remember { mutableStateOf(client.hasPending()) }
    var resuming by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    var chooser by remember { mutableStateOf<String?>(null) }
    var detail by remember { mutableStateOf<NovaKatipContract?>(null) }
    var drafting by remember { mutableStateOf<NovaKatipDraft?>(null) }
    var ending by remember { mutableStateOf<NovaKatipEndDraft?>(null) }
    suspend fun load(reset: Boolean) {
        query = if (reset) query.copy(offset = 0) else query.copy(offset = query.offset + query.limit)
        loading = true; failure = null; pending = client.hasPending()
        try {
            if (companies.isEmpty()) companies = client.companies()
            catalogue = client.catalogue(query.company)
            val answer = client.board(query)
            val existing = board
            board = if (reset || existing == null) answer else answer.copy(rows = existing.rows + answer.rows)
        } catch (error: Exception) { failure = katipMessage(error) }
        loading = false
    }
    fun reload() = coroutines.launch { load(true) }
    val draft = drafting
    if (draft != null) {
        KatipContractSheet(draft, catalogue, onClose = { drafting = null; pending = client.hasPending() }) { edited ->
            val company = query.company ?: return@KatipContractSheet NovaKatipFailure.validation.message
            try { client.record(company, edited); load(true); null } catch (error: Exception) { pending = client.hasPending(); katipMessage(error) }
        }
        return
    }
    LaunchedEffect(Unit) { load(true) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaListHeading(headingOverride ?: NovaDestination.katipContracts.title, onBack, actionBelow = true) {
            // A contract belongs to one company, so adding waits for one to be chosen.
            if (canWrite && query.company != null) NovaListActionButton("Sözleşme Ekle", "plus", identifier = "nova.katip.add") {
                drafting = NovaKatipDraft(startsOn = NovaDay.today())
            }
        }
        NovaListHint("Firmanın sözleşmesini kaydedin; hizmet süresini ve belgesini takip edin.")
        board?.let { shown ->
            val columns = if (novaFontScaleIsAccessibility()) 2 else 4
            NovaKatipGroup.entries.chunked(columns).forEach { chunk ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    chunk.forEach { group ->
                        NovaListStat(group.title, group.symbol, shown.count(group), Modifier.weight(1f).testTag("nova.katip.stat.${group.wire}"),
                            selected = query.state == group.wire, status = when (group.wire) {
                                "expired" -> NovaStatus.Danger
                                "expiring" -> NovaStatus.Warning
                                "current" -> NovaStatus.Success
                                else -> NovaStatus.Neutral
                            }) {
                            query = query.copy(state = if (query.state == group.wire) null else group.wire); reload()
                        }
                    }
                }
            }
        }
        NovaSearchCapsule(query.search, "Kurum, kapsam veya firma ara", "nova.katip.search") { query = query.copy(search = it) }
        LaunchedEffect(query.search) { if (board != null) { kotlinx.coroutines.delay(350); load(true) } }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaChooserButton("Firma", companies.firstOrNull { it.id == query.company }?.name ?: "Tüm firmalar", "nova.katip.chooser.company",
                Modifier.weight(1f), open = chooser == "company") { chooser = if (chooser == "company") null else "company" }
            val stateTitle = query.state?.let { value -> NovaKatipGroup.ofWire(value)?.title ?: NovaKatipState.of(value)?.title } ?: "Tüm durumlar"
            NovaChooserButton("Durum", stateTitle, "nova.katip.chooser.state", Modifier.weight(1f), open = chooser == "state") {
                chooser = if (chooser == "state") null else "state"
            }
        }
        if (chooser == "company") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm firmalar")) + companies.map { NovaChooserOption(it.id, it.name) },
            query.company, "nova.katip.panel.company") { query = query.copy(company = it); chooser = null; reload() }
        if (chooser == "state") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm durumlar")) +
            NovaKatipGroup.entries.map { NovaChooserOption(it.wire, it.title, board?.count(it), it.symbol) } +
            NovaKatipState.entries.filter { state -> NovaKatipGroup.entries.none { it.wire == state.wire } }
                .map { NovaChooserOption(it.wire, it.title, board?.counts?.get(it.wire)) }, query.state, "nova.katip.panel.state") {
            query = query.copy(state = it); chooser = null; reload()
        }
        if (pending && canWrite) NovaCard(Modifier.fillMaxWidth(), padding = 16) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaText("Gönderimi tamamlanmamış bir sözleşme işlemi var.")
                NovaButton(if (resuming) "Tamamlanıyor…" else "Bekleyen işlemi tamamla", {
                    if (!resuming) coroutines.launch {
                        resuming = true
                        try { client.resume(); load(true) } catch (error: Exception) { failure = katipMessage(error) }
                        pending = client.hasPending(); resuming = false
                    }
                }, variant = NovaButtonVariant.Surface, symbol = "arrow.clockwise", enabled = !resuming)
            }
        }
        val shown = board
        shown?.let { NovaListSectionHeading("İSG-KATİP Sözleşmeleri", "${it.rows.size} / ${it.total} sözleşme") }
        when {
            loading && shown == null -> Box(Modifier.fillMaxWidth().padding(vertical = 30.dp), contentAlignment = Alignment.Center) {
                NovaSpinner(NovaColorToken.text.color(), size = 24.dp)
            }
            failure != null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText(failure!!, color = NovaColorToken.statusDangerInk.color()) }
            shown != null && shown.rows.isEmpty() -> NovaEmptyState("Henüz sözleşme kaydı yok",
                "İSG hizmeti sözleşmesini ekleyerek başlangıç, bitiş ve bağlı dosya bilgilerini takip edebilirsiniz.")
            shown != null -> NovaListEntrance(true) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    shown.rows.forEachIndexed { index, row ->
                        ContractCard(row, Modifier.novaRowEntrance(index)) {
                            coroutines.launch { detail = runCatching { client.detail(row.id) }.getOrDefault(row) }
                        }
                    }
                    if (shown.hasMore) NovaButton("Daha fazla göster", { coroutines.launch { load(false) } }, variant = NovaButtonVariant.Surface,
                        symbol = "chevron.down")
                }
            }
        }
    }
    val open = detail
    NovaPopup(open != null, { detail = null }, identifier = "nova.katip.detail") {
        if (open != null) KatipDetail(open, canWrite, client,
            onEnd = {
                detail = null
                ending = NovaKatipEndDraft(open.id, open.counterparty, open.startsOn, open.endsBefore ?: NovaDay.today(), open.endsBefore != null)
            },
            onArchive = {
                val company = open.companyId ?: query.company ?: return@KatipDetail NovaKatipFailure.validation.message
                try { client.archive(company, open.id)?.let { detail = it }; load(true); null } catch (error: Exception) { katipMessage(error) }
            },
            onLinked = { detail = it },
            onClose = { detail = null })
    }
    val end = ending
    NovaPopup(end != null, { ending = null; pending = client.hasPending() }, identifier = "nova.katip.end") {
        if (end != null) KatipEndSheet(end, onClose = { ending = null }) { edited ->
            val company = query.company ?: return@KatipEndSheet NovaKatipFailure.validation.message
            try { client.end(company, edited); ending = null; load(true); null } catch (error: Exception) { pending = client.hasPending(); katipMessage(error) }
        }
    }
}

/** One contract; the app never files anything with the official system. */
@Composable
private fun KatipDetail(entry: NovaKatipContract, canWrite: Boolean, client: NovaKatipClient, onEnd: () -> Unit, onArchive: suspend () -> String?,
                        onLinked: (NovaKatipContract) -> Unit, onClose: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val context = LocalContext.current
    var failure by remember { mutableStateOf<String?>(null) }
    var working by remember { mutableStateOf(false) }
    var choosingDocument by remember { mutableStateOf(false) }
    var documents by remember { mutableStateOf<List<NovaFileEntry>>(emptyList()) }
    var moreDocuments by remember { mutableStateOf(true) }
    val unset = "Belirtilmedi"
    fun loadDocuments(reset: Boolean) {
        val company = entry.companyId ?: return
        if (working) return
        coroutines.launch {
            working = true; failure = null
            try {
                val offset = if (reset) 0 else documents.size
                val page = client.documents(company, offset)
                documents = if (reset) page else documents + page
                moreDocuments = page.size == 20
            } catch (_: Exception) { failure = "Dosyalar alınamadı. Yeniden deneyin." }
            working = false
        }
    }
    fun link(file: String?) {
        if (working) return
        coroutines.launch {
            working = true; failure = null
            try {
                val updated = client.linkDocument(entry, file) ?: throw NovaKatipException(NovaKatipFailure.unavailable)
                choosingDocument = false; onLinked(updated)
            } catch (error: Exception) {
                failure = (error as? NovaKatipException)?.failure?.message ?: "Dosya bağlantısı kaydedilemedi. Yeniden deneyin."
            }
            working = false
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            NovaPopupHeading(entry.counterparty, symbol = "doc.text")
            NovaText(listOfNotNull(entry.scope, entry.workplaceName, entry.companyName).joinToString(" · "), style = NovaTypeToken.meta,
                color = NovaColorToken.textSecondary.color())
            NovaText(NovaKatipWords.explain(entry), style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaFactGrid(listOf(
                    { m -> NovaFactCell("calendar", "Başlangıç", NovaDay.label(entry.startsOn), m) },
                    { m -> NovaFactCell("calendar.badge.minus", "Bitiş",
                        if (entry.term == NovaKatipTerm.openEnded) "Süresiz" else entry.endsBefore?.let(NovaDay::label) ?: unset, m) },
                    { m -> NovaFactCell("doc.text", "Tür", entry.term.title, m) },
                    { m -> NovaFactCell("person", "Uzman", entry.expertContact, m) }))
                NovaHelpHint(NovaKatipWords.noIntegrationNote)
                if (!entry.officialSubmissionMade) NovaTag("nosign", "Resmî sisteme hiçbir bildirim yapılmadı")
            }
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                NovaText("Beyan edilen hizmet süresi", style = NovaTypeToken.cardTitle)
                entry.declaredMonthlyMinutes?.let { NovaText(NovaKatipWords.service(it)) } ?: NovaText(unset, color = NovaColorToken.textSecondary.color())
                entry.declaredNote?.takeIf { it.isNotEmpty() }?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color()) }
                NovaText(NovaKatipWords.declaredNote, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                if (!entry.requiredServiceTimeKnown) NovaTag("questionmark.circle", "Gereken süre bilinmiyor")
            }
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                NovaText("Sözleşme aslı", style = NovaTypeToken.cardTitle)
                NovaText(entry.contractLocation ?: unset, color = if (entry.contractLocation == null) NovaColorToken.textSecondary.color() else NovaColorToken.text.color())
                entry.documentTitle?.let { title ->
                    NovaText(title)
                    if (!entry.contractStored) NovaText("Bağlı dosya artık kullanılamıyor.", style = NovaTypeToken.meta)
                }
                if (entry.contractStored) NovaButton("Dosyayı aç / paylaş", {
                    coroutines.launch {
                        working = true; failure = null
                        try { val document = client.openDocument(entry.id); novaShareFile(context, document.bytes, document.fileName, document.mime) }
                        catch (_: Exception) { failure = "Dosya açılamadı. Yetkinizi ve bağlantınızı kontrol edin." }
                        working = false
                    }
                }, variant = NovaButtonVariant.Surface, symbol = "square.and.arrow.up", enabled = !working)
                if (canWrite && entry.state != NovaKatipState.archived) {
                    NovaButton(if (entry.fileEntryId == null) "Evraktan dosya bağla" else "Bağlı dosyayı değiştir", {
                        choosingDocument = !choosingDocument; if (choosingDocument) loadDocuments(true)
                    }, variant = NovaButtonVariant.Surface, symbol = "paperclip", enabled = !working)
                    if (entry.fileEntryId != null) NovaButton("Dosya bağlantısını kaldır", { link(null) }, variant = NovaButtonVariant.Muted,
                        symbol = "link", enabled = !working)
                }
                if (choosingDocument) {
                    documents.forEach { file -> NovaButton(file.title, { link(file.id) }, variant = NovaButtonVariant.Surface, symbol = "doc", enabled = !working) }
                    if (moreDocuments) NovaButton("Daha fazla dosya", { loadDocuments(false) }, variant = NovaButtonVariant.Muted, symbol = "chevron.down", enabled = !working)
                    if (documents.isEmpty() && !working) NovaText("Bu firmaya ait hazır dosya bulunamadı. Evraklar bölümünden dosya yükleyebilirsiniz.",
                        style = NovaTypeToken.meta)
                }
            }
        }
        if (canWrite && entry.state != NovaKatipState.archived) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaButton(if (entry.endsBefore == null) "Sözleşmeyi bitir" else "Bitiş tarihini düzelt", onEnd, Modifier.weight(1f), symbol = "calendar.badge.minus")
            NovaButton("Arşivle", { coroutines.launch { working = true; failure = onArchive(); working = false } }, Modifier.weight(1f),
                variant = NovaButtonVariant.Muted, symbol = "archivebox", enabled = !working)
        }
        failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
        NovaButton("Kapat", onClose, variant = NovaButtonVariant.Surface, symbol = "xmark")
    }
}

private enum class KatipStep(val title: String) { scope("Taraflar ve kapsam"), period("Dönem ve hizmet"), review("Kontrol ve kaydet") }

/** Recording a contract as a three-step task (iOS `NovaKatipContractSheet`). */
@Composable
private fun KatipContractSheet(initial: NovaKatipDraft, catalogue: NovaKatipCatalogue?, onClose: () -> Unit, onSave: suspend (NovaKatipDraft) -> String?) {
    val coroutines = rememberCoroutineScope()
    val workplaces = catalogue?.workplaces.orEmpty()
    var draft by remember { mutableStateOf(if (initial.workplaceId == null && workplaces.size == 1) initial.copy(workplaceId = workplaces[0].id) else initial) }
    var failure by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    var step by remember { mutableStateOf(KatipStep.scope) }
    var didSave by remember { mutableStateOf(false) }
    var confirmingExit by remember { mutableStateOf(false) }
    val placeTitle = workplaces.firstOrNull { it.id == draft.workplaceId }?.name ?: "İşyeri seçin"
    val canSave = (workplaces.isEmpty() || draft.workplaceId != null) && draft.counterparty.isNotBlank() && draft.expertContact.isNotBlank() && draft.scope.isNotBlank()
    if (didSave) {
        NovaTaskSuccessView("Sözleşme kaydedildi", "Sözleşme kaydı seçili firmanın İSG-KATİP arşivine eklendi.", "Sözleşmelere dön", onClose)
        return
    }
    NovaModuleTask("Sözleşme ekle", step.ordinal + 1, KatipStep.entries.size, step.title, if (step == KatipStep.review) "Sözleşmeyi kaydet" else "Devam",
        if (step == KatipStep.review) "checkmark" else "arrow.right", saving,
        onBack = { if (step.ordinal > 0) step = KatipStep.entries[step.ordinal - 1] else confirmingExit = true },
        onPrimary = {
            when {
                step == KatipStep.review && !canSave -> failure = NovaKatipFailure.validation.message
                step == KatipStep.review -> coroutines.launch { saving = true; failure = onSave(draft); saving = false; if (failure == null) didSave = true }
                step == KatipStep.scope && !canSave -> failure = NovaKatipFailure.validation.message
                else -> { failure = null; step = KatipStep.entries[step.ordinal + 1] }
            }
        }, failure = failure, canGoBack = step != KatipStep.scope) {
        NovaHelpHint(NovaKatipWords.noIntegrationNote)
        when (step) {
            KatipStep.scope -> {
                NovaText("Firma bağlamı akış boyunca korunur.")
                if (workplaces.size == 1) NovaCard(Modifier.fillMaxWidth(), padding = 13) {
                    NovaText("İşyeri", style = NovaTypeToken.label)
                    NovaText(placeTitle, style = NovaTypeToken.bodyStrong)
                } else if (workplaces.size > 1) {
                    NovaChoiceField("İşyeri", "İşyeri seçin", "building.2", workplaces.map { NovaChoiceOption(it.id, it.name) }, draft.workplaceId,
                        { draft = draft.copy(workplaceId = it) }, "nova.katip.form.workplace", searchable = true, boxed = true)
                }
                NovaTextField("Karşı taraf (OSGB veya işveren)", draft.counterparty, { draft = draft.copy(counterparty = it) }, identifier = "nova.katip.form.counterparty")
                NovaTextField("Uzman / hekim", draft.expertContact, { draft = draft.copy(expertContact = it) }, identifier = "nova.katip.form.expert")
                NovaTextField("Kapsam", draft.scope, { draft = draft.copy(scope = it) }, identifier = "nova.katip.form.scope")
            }
            KatipStep.period -> {
                NovaDayField("Başlangıç", draft.startsOn, { draft = draft.copy(startsOn = it) }, "nova.katip.form.starts")
                NovaDayField("Bitiş", draft.endsBefore, { draft = draft.copy(endsBefore = it) }, "nova.katip.form.ends", clearable = true)
                NovaText("Bitiş tarihi boş bırakılırsa sözleşme süresiz kaydedilir.", style = NovaTypeToken.metaQuiet)
                NovaTextField("Beyan edilen aylık süre (dakika)", draft.declaredMonthlyMinutes, { value -> draft = draft.copy(declaredMonthlyMinutes = value.filter(Char::isDigit)) },
                    identifier = "nova.katip.form.minutes", placeholder = "Dakika", keyboardType = KeyboardType.Number)
                NovaTextField("Süreye dair not (isteğe bağlı)", draft.declaredNote, { draft = draft.copy(declaredNote = it) }, identifier = "nova.katip.form.declarednote")
                NovaText(NovaKatipWords.declaredNote, style = NovaTypeToken.metaQuiet)
            }
            KatipStep.review -> {
                NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                    NovaText(draft.counterparty.ifEmpty { "Karşı taraf belirtilmedi" }, style = NovaTypeToken.cardTitle)
                    NovaText(listOf(placeTitle, draft.scope).filter { it.isNotEmpty() }.joinToString(" · "), style = NovaTypeToken.meta)
                    NovaText("${NovaDay.label(draft.startsOn)} → ${if (draft.endsBefore.isEmpty()) "Süresiz" else NovaDay.label(draft.endsBefore)}")
                }
                NovaTextField("Sözleşme aslı nerede?", draft.contractLocation, { draft = draft.copy(contractLocation = it) }, identifier = "nova.katip.form.location",
                    placeholder = "Örn. şirket arşivi / klasör")
                NovaText(NovaKatipWords.documentNote, style = NovaTypeToken.metaQuiet)
            }
        }
    }
    NovaPopup(confirmingExit, { confirmingExit = false }) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            NovaPopupHeading("Sözleşme akışından çıkılsın mı?", symbol = "exclamationmark.triangle")
            NovaText("Henüz kaydedilmemiş bilgiler silinir.")
            NovaButton("Çık", { confirmingExit = false; onClose() }, variant = NovaButtonVariant.Danger)
            NovaButton("Devam et", { confirmingExit = false }, variant = NovaButtonVariant.Surface)
        }
    }
}

/** Ending a contract, or correcting the date it ended; nothing changes in the official system. */
@Composable
private fun KatipEndSheet(initial: NovaKatipEndDraft, onClose: () -> Unit, onSave: suspend (NovaKatipEndDraft) -> String?) {
    val coroutines = rememberCoroutineScope()
    val busy = LocalNovaPopupBusy.current
    var draft by remember { mutableStateOf(initial) }
    var failure by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPopupHeading(if (draft.isCorrection) "Bitiş tarihini düzelt" else "Sözleşmeyi bitir", symbol = "doc.text")
        if (draft.counterparty.isNotEmpty()) NovaText(draft.counterparty, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        NovaHelpHint("Sözleşme ${NovaDay.label(draft.startsOn)} tarihinde başladı; bitiş bundan önce olamaz.")
        NovaDayField("Bitiş", draft.endsBefore, { draft = draft.copy(endsBefore = it) }, "nova.katip.end.date")
        NovaText("Bu işlem yalnız sizin kaydınızı kapatır; resmî sistemde hiçbir şey değişmez.", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaButton("Vazgeç", onClose, Modifier.weight(1f), variant = NovaButtonVariant.Surface, symbol = "xmark")
            NovaButton("Kaydet", { coroutines.launch { saving = true; busy(true); failure = onSave(draft); saving = false; busy(false) } },
                Modifier.weight(1f), symbol = "checkmark", enabled = !saving, loading = saving)
        }
    }
}
