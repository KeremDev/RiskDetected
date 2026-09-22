package com.riskdetectedan.feature.nova

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.launch

/** The module's calls bound to one identity (iOS `NovaAppointmentClient`); the design preview supplies its own. */
interface NovaAppointmentClient {
    val companies: suspend () -> List<NovaCompanyOption>
    val files: NovaFileClient
    suspend fun catalogue(company: String?): NovaAppointmentCatalogue
    suspend fun board(query: NovaAppointmentQuery): NovaAppointmentBoard
    suspend fun detail(id: String): NovaAppointment
    suspend fun record(company: String, draft: NovaAppointmentDraft): NovaAppointment?
    suspend fun end(company: String, draft: NovaAppointmentEndDraft): NovaAppointment?
}

class NovaServiceAppointmentClient(private val service: NovaAppointmentService, private val identity: IsgWorkspaceIdentity,
                                   override val companies: suspend () -> List<NovaCompanyOption>, override val files: NovaFileClient) : NovaAppointmentClient {
    override suspend fun catalogue(company: String?) = service.catalogue(identity, company)
    override suspend fun board(query: NovaAppointmentQuery) = service.board(identity, query)
    override suspend fun detail(id: String) = service.detail(identity, id)
    override suspend fun record(company: String, draft: NovaAppointmentDraft) = service.record(identity, company, draft)
    override suspend fun end(company: String, draft: NovaAppointmentEndDraft) = service.end(identity, company, draft)
}

internal fun appointmentMessage(error: Throwable) = (error as? NovaAppointmentException)?.failure?.message ?: NovaAppointmentFailure.unavailable.message

private fun NovaAppointmentState.status() = when (this) {
    NovaAppointmentState.active -> NovaStatus.Success; NovaAppointmentState.upcoming -> NovaStatus.Info; NovaAppointmentState.ended -> NovaStatus.Neutral
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AppointmentCard(entry: NovaAppointment, modifier: Modifier, onClick: () -> Unit) {
    NovaCard(modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onClick).testTag("nova.appointment.row.${entry.id}"), padding = 14) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(entry.employeeName ?: "Personel", style = NovaTypeToken.cardTitle)
                    NovaText(listOfNotNull(entry.kind.title, entry.workplaceName, entry.companyName).joinToString(" · "), style = NovaTypeToken.meta,
                        color = NovaColorToken.textSecondary.color())
                }
                NovaStatusPill(entry.state.title, entry.state.status())
            }
            NovaText(NovaAppointmentWords.explain(entry), style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaRowFact("calendar", "Başlangıç", NovaDay.label(entry.startsOn))
                entry.endsBefore?.let { NovaRowFact("calendar.badge.minus", "Bitiş", NovaDay.label(it)) }
            }
            if (entry.basis != null || entry.employeeArchived) FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                entry.basis?.let { NovaTag(it.symbol, it.title, NovaStatus.Info) }
                if (entry.employeeArchived) NovaTag("person.badge.minus", "Personel kaydı arşivlendi")
            }
        }
    }
}

/** Atama ve Temsilciler (iOS `NovaAppointmentScreen`). */
@Composable
fun NovaAppointmentScreen(client: NovaAppointmentClient, canWrite: Boolean, onBack: () -> Unit, initialCompany: String? = null,
                          headingOverride: String? = null, startInAddMode: Boolean = false) {
    val coroutines = rememberCoroutineScope()
    var board by remember { mutableStateOf<NovaAppointmentBoard?>(null) }
    var catalogue by remember { mutableStateOf<NovaAppointmentCatalogue?>(null) }
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var query by remember { mutableStateOf(NovaAppointmentQuery(company = initialCompany)) }
    var loading by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    var chooser by remember { mutableStateOf<String?>(null) }
    var detail by remember { mutableStateOf<NovaAppointment?>(null) }
    var drafting by remember { mutableStateOf<NovaAppointmentDraft?>(null) }
    var ending by remember { mutableStateOf<NovaAppointmentEndDraft?>(null) }
    var draftCompany by remember { mutableStateOf<String?>(null) }
    suspend fun load(reset: Boolean) {
        query = if (reset) query.copy(offset = 0) else query.copy(offset = query.offset + query.limit)
        loading = true; failure = null
        try {
            if (companies.isEmpty()) companies = client.companies()
            catalogue = client.catalogue(query.company)
            val answer = client.board(query)
            val existing = board
            board = if (reset || existing == null) answer else answer.copy(rows = existing.rows + answer.rows)
        } catch (error: Exception) { failure = appointmentMessage(error) }
        loading = false
    }
    fun reload() = coroutines.launch { load(true) }
    val closeAdd: () -> Unit = { if (startInAddMode) onBack() else drafting = null }
    val current = drafting
    if (startInAddMode || current != null) {
        val draft = current ?: NovaAppointmentDraft(startsOn = NovaDay.today())
        NovaCompanyCreateFlow("Görev ver", client.companies, { company -> client.catalogue(company) }, initialCompany, closeAdd) { selected, company ->
            AppointmentSheet(draft, selected, client.files, company, onSave = { edited ->
                try { client.record(company, edited); load(true); null } catch (error: Exception) { appointmentMessage(error) }
            }, onClose = closeAdd)
        }
        return
    }
    LaunchedEffect(Unit) { load(true) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaListHeading(headingOverride ?: NovaDestination.appointments.title, onBack) {
            if (canWrite) NovaButton("Atama Ekle", { draftCompany = null; drafting = NovaAppointmentDraft(startsOn = NovaDay.today()) }, symbol = "plus", compact = true)
        }
        NovaHelpHint("Firmayı ve personeli seçerek görevlendirme kaydı oluşturun; belgesini aynı kayda ekleyin. ${NovaAppointmentWords.noQualificationNote} ${NovaAppointmentWords.noRequiredCountNote}")
        board?.let { shown ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaAppointmentState.entries.forEach { state ->
                    NovaListStat(state.title, state.symbol, shown.count(state), Modifier.weight(1f).testTag("nova.appointment.stat.${state.wire}"),
                        selected = query.state == state.wire) {
                        query = query.copy(state = if (query.state == state.wire) null else state.wire); reload()
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaChooserButton("Firma", companies.firstOrNull { it.id == query.company }?.name ?: "Tüm firmalar", "nova.appointment.chooser.company",
                Modifier.weight(1f), open = chooser == "company") { chooser = if (chooser == "company") null else "company" }
            NovaChooserButton("Görev", NovaAppointmentKind.of(query.role)?.title ?: "Tüm görevler", "nova.appointment.chooser.role", Modifier.weight(1f),
                open = chooser == "role") { chooser = if (chooser == "role") null else "role" }
        }
        if (chooser == "company") NovaChooserPanel((if (initialCompany == null) listOf(NovaChooserOption(null, "Tüm firmalar")) else emptyList()) +
            companies.filter { initialCompany == null || it.id == initialCompany }.map { NovaChooserOption(it.id, it.name) },
            query.company, "nova.appointment.panel.company") { query = query.copy(company = it); chooser = null; reload() }
        if (chooser == "role") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm görevler")) +
            (catalogue?.roles?.map { it.kind } ?: NovaAppointmentKind.entries).map { NovaChooserOption(it.wire, it.title) }, query.role,
            "nova.appointment.panel.role") { query = query.copy(role = it); chooser = null; reload() }
        NovaSearchCapsule(query.search, "Kişi, işyeri veya firma ara", "nova.appointment.search") { query = query.copy(search = it) }
        LaunchedEffect(query.search) { if (board != null) { kotlinx.coroutines.delay(350); load(true) } }
        val shown = board
        when {
            loading && shown == null -> Box(Modifier.fillMaxWidth().padding(vertical = 30.dp), contentAlignment = Alignment.Center) {
                NovaSpinner(NovaColorToken.text.color(), size = 24.dp)
            }
            failure != null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText(failure!!, color = NovaColorToken.statusDangerInk.color()) }
            shown != null && shown.rows.isEmpty() -> NovaEmptyState("Henüz atama kaydı yok",
                "Firma personelinden temsilci, destek elemanı veya ekip üyesi seçerek görev süresini takip edebilirsiniz.")
            shown != null -> NovaListEntrance(true) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    shown.rows.forEachIndexed { index, entry ->
                        AppointmentCard(entry, Modifier.novaRowEntrance(index)) {
                            coroutines.launch {
                                draftCompany = entry.companyId
                                try { catalogue = client.catalogue(entry.companyId); detail = client.detail(entry.id) }
                                catch (_: Exception) { failure = "Kayıt açılamadı. Yeniden deneyin." }
                            }
                        }
                    }
                    NovaText("${shown.rows.size} / ${shown.total} görev", style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
                    if (shown.hasMore) NovaButton("Daha fazla göster", { coroutines.launch { load(false) } }, variant = NovaButtonVariant.Surface,
                        symbol = "chevron.down")
                }
            }
        }
    }
    val open = detail
    NovaPopup(open != null, { detail = null }, identifier = "nova.appointment.detail") {
        if (open != null) AppointmentDetail(open, canWrite, { bucket, path -> client.files.download(bucket, path) }) {
            detail = null
            ending = NovaAppointmentEndDraft(open.id, open.employeeName.orEmpty(), open.startsOn, open.endsBefore ?: NovaDay.today(), open.endsBefore != null)
        }
    }
    val end = ending
    NovaPopup(end != null, { ending = null }, identifier = "nova.appointment.end") {
        if (end != null) AppointmentEndSheet(end, onClose = { ending = null }) { edited ->
            val company = draftCompany ?: query.company ?: return@AppointmentEndSheet NovaAppointmentFailure.validation.message
            try { client.end(company, edited); ending = null; load(true); null } catch (error: Exception) { appointmentMessage(error) }
        }
    }
}

/** One appointment; nothing here says the person is qualified, because nothing anywhere does. */
@Composable
private fun AppointmentDetail(entry: NovaAppointment, canWrite: Boolean, download: suspend (String, String) -> ByteArray, onEnd: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            NovaPopupHeading(entry.employeeName ?: "Personel", symbol = "person.badge.plus")
            NovaText(listOfNotNull(entry.kind.title, entry.workplaceName, entry.companyName).joinToString(" · "), style = NovaTypeToken.meta,
                color = NovaColorToken.textSecondary.color())
            NovaText(NovaAppointmentWords.explain(entry), style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaFactGrid(listOf(
                    { m -> NovaFactCell("calendar", "Başlangıç", NovaDay.label(entry.startsOn), m) },
                    { m -> NovaFactCell("calendar.badge.minus", "Bitiş", entry.endsBefore?.let(NovaDay::label) ?: "Belirtilmedi", m) },
                    { m -> NovaFactCell(entry.basis?.symbol ?: "questionmark", "Dayanak", entry.basis?.title ?: "Belirtilmedi", m, entry.basisNote.orEmpty()) }))
                // Said on the record itself, not only at the top of the board.
                NovaHelpHint(NovaAppointmentWords.noQualificationNote)
                entry.assetDownload?.let { NovaAttachedFileRow("Atama yazısı", it.bucket, it.path, download, "nova.appointment.detail.file.open") }
            }
        }
        if (canWrite) NovaButton(if (entry.endsBefore == null) "Görevi sonlandır" else "Bitiş tarihini düzelt", onEnd, symbol = "calendar.badge.minus")
    }
}

/** A compact tinted icon chip in front of one field group (iOS `fieldCard`). */
@Composable
private fun FieldCard(symbol: String, content: @Composable ColumnScope.() -> Unit) {
    NovaCard(Modifier.fillMaxWidth(), padding = 12) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(26.dp).background(NovaColorToken.statusSuccessBg.color(), RoundedCornerShape(8.dp)), contentAlignment = Alignment.Center) {
                NovaIcon(symbol, 13.dp, tint = NovaColorToken.accentInk.color())
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp), content = content)
        }
    }
}

@Composable
private fun ChoiceRow(title: String, on: Boolean, onSymbol: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 42.dp).novaRowPress(onClick = onClick).semantics { role = Role.RadioButton; selected = on },
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(if (on) onSymbol else "circle", 15.dp, tint = if (on) NovaColorToken.accentInk.color() else NovaColorToken.textMuted.color())
        NovaText(title)
    }
}

/** Recording an appointment as a four-step task; the basis is asked for because it is the point of the field. */
@Composable
private fun AppointmentSheet(initial: NovaAppointmentDraft, catalogue: NovaAppointmentCatalogue?, files: NovaFileClient, company: String,
                             onSave: suspend (NovaAppointmentDraft) -> String?, onClose: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val workplaces = catalogue?.workplaces.orEmpty()
    // One workplace is not a choice.
    var draft by remember { mutableStateOf(if (initial.workplaceId == null && workplaces.size == 1) initial.copy(workplaceId = workplaces[0].id) else initial) }
    var failure by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    var chooser by remember { mutableStateOf<String?>(null) }
    var personSearch by remember { mutableStateOf("") }
    var step by remember { mutableIntStateOf(0) }
    var saved by remember { mutableStateOf(false) }
    val personTitle = catalogue?.employees?.firstOrNull { it.id == draft.employeeId }?.fullName ?: "Personel seçin"
    val placeTitle = workplaces.firstOrNull { it.id == draft.workplaceId }?.name ?: "İşyeri seçin"
    if (saved) {
        NovaTaskSuccessView("Atama kaydedildi", "Görev, süre ve varsa atama yazısı personel kaydına eklendi.", "Atamalara dön", onClose)
        return
    }
    val goBack: () -> Unit = { failure = null; if (step > 0) step-- else onClose() }
    NovaModuleTask("Görev ver", step + 1, 4, listOf("Personel ve işyeri", "Görev ve dayanak", "Tarih", "Dosya ve kontrol")[step],
        if (step == 3) "Atamayı kaydet" else "Devam", if (step == 3) "checkmark" else "arrow.right", saving, goBack, {
            failure = null
            when {
                step == 0 && (draft.employeeId == null || draft.workplaceId == null) -> failure = "Personel ve işyeri seçimini tamamlayın."
                step < 3 -> step++
                else -> coroutines.launch { saving = true; val result = onSave(draft); saving = false; if (result != null) failure = result else saved = true }
            }
        }, failure) {
        when (step) {
            0 -> {
                NovaHelpHint("Personel ve işyeri seçimi sonraki adımlara otomatik taşınır.")
                FieldCard("person.2") {
                    NovaChooserButton("Personel", personTitle, "nova.appointment.form.person", open = chooser == "person") {
                        chooser = if (chooser == "person") null else "person"
                    }
                    if (chooser == "person") {
                        NovaSearchCapsule(personSearch, "Personel ara", "nova.appointment.form.person.search") { personSearch = it }
                        // Large registers never render in full: wait for a search term, then filter locally.
                        val needle = personSearch.trim()
                        val matches = if (needle.isEmpty()) emptyList() else catalogue?.employees.orEmpty().filter { it.fullName.contains(needle, ignoreCase = true) }
                        if (matches.isEmpty()) NovaText(if (needle.isEmpty()) "Personel adını yazarak arayın." else "Aramanızla eşleşen personel bulunamadı.",
                            Modifier.padding(vertical = 8.dp), NovaTypeToken.metaQuiet)
                        else NovaChooserPanel(matches.map { NovaChooserOption(it.id, it.fullName) }, draft.employeeId, "nova.appointment.form.person.panel") {
                            draft = draft.copy(employeeId = it); chooser = null; personSearch = ""
                        }
                    }
                }
                FieldCard("building.2") {
                    if (workplaces.size <= 1) NovaText(if (workplaces.size == 1) placeTitle else "Bu firmada kayıt açılacak bir işyeri yok.", style = NovaTypeToken.cardTitle)
                    else {
                        NovaChooserButton("İşyeri", placeTitle, "nova.appointment.form.workplace", open = chooser == "place") {
                            chooser = if (chooser == "place") null else "place"
                        }
                        if (chooser == "place") NovaChooserPanel(workplaces.map { NovaChooserOption(it.id, it.name) }, draft.workplaceId,
                            "nova.appointment.form.workplace.panel") { draft = draft.copy(workplaceId = it); chooser = null }
                    }
                }
            }
            1 -> {
                FieldCard("person.badge.shield.checkmark") {
                    NovaText("Görev", style = NovaTypeToken.label)
                    (catalogue?.roles ?: NovaAppointmentKind.entries.map { NovaAppointmentCatalogue.Role(it, NovaAppointmentBasis.appointed) }).forEach { role ->
                        ChoiceRow(role.kind.title, draft.kind == role.kind, "largecircle.fill.circle") { draft = draft.copy(kind = role.kind, basis = role.usualBasis) }
                    }
                }
                FieldCard("checkmark.seal") {
                    NovaText("Dayanak", style = NovaTypeToken.label)
                    (catalogue?.bases ?: NovaAppointmentBasis.entries).forEach { basis ->
                        ChoiceRow(basis.title, draft.basis == basis, "checkmark.circle.fill") { draft = draft.copy(basis = basis) }
                    }
                    NovaTextField("Tutanak veya karar no", draft.basisNote, { draft = draft.copy(basisNote = it) }, identifier = "nova.appointment.form.note")
                }
                NovaWhyDisclosure { NovaText("${NovaAppointmentWords.noQualificationNote} ${NovaAppointmentWords.noRequiredCountNote}", style = NovaTypeToken.metaQuiet) }
            }
            2 -> FieldCard("calendar") {
                NovaDayField("Başlangıç", draft.startsOn, { draft = draft.copy(startsOn = it) }, "nova.appointment.form.starts")
                NovaDayField("Bitiş", draft.endsBefore, { draft = draft.copy(endsBefore = it) }, "nova.appointment.form.ends", clearable = true)
            }
            else -> {
                NovaHelpHint("Atama yazısı isteğe bağlıdır; belgeyi daha sonra da ekleyebilirsiniz. ${NovaAppointmentWords.letterNote}")
                FieldCard("paperclip") {
                    NovaInlineFileField("personnel_document", company, files, draft.letterLocation, { draft = draft.copy(letterLocation = it) })
                }
                NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                    NovaText("Atama özeti", style = NovaTypeToken.bodyStrong)
                    NovaText(personTitle)
                    NovaText("$placeTitle · ${draft.kind.title} · ${NovaDay.label(draft.startsOn)}", style = NovaTypeToken.metaQuiet)
                }
            }
        }
    }
}

/** Ending an appointment, or correcting the date it ended. */
@Composable
private fun AppointmentEndSheet(initial: NovaAppointmentEndDraft, onClose: () -> Unit, onSave: suspend (NovaAppointmentEndDraft) -> String?) {
    val coroutines = rememberCoroutineScope()
    val busy = LocalNovaPopupBusy.current
    var draft by remember { mutableStateOf(initial) }
    var failure by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPopupHeading(if (draft.isCorrection) "Bitiş tarihini düzelt" else "Görevi sonlandır", symbol = "person.badge.plus")
        if (draft.employeeName.isNotEmpty()) NovaText(draft.employeeName, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        NovaHelpHint("Görev ${NovaDay.label(draft.startsOn)} tarihinde başladı; bitiş bundan sonrası olmalı.")
        NovaDayField("Bitiş", draft.endsBefore, { draft = draft.copy(endsBefore = it) }, "nova.appointment.end.date")
        failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaButton("Vazgeç", onClose, Modifier.weight(1f), variant = NovaButtonVariant.Surface, symbol = "xmark", enabled = !saving)
            NovaButton("Kaydet", { coroutines.launch { saving = true; busy(true); failure = onSave(draft); saving = false; busy(false) } },
                Modifier.weight(1f), symbol = "checkmark", enabled = !saving, loading = saving)
        }
    }
}
