package com.riskdetectedan.feature.nova

import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.launch

/** The module's calls bound to one identity (iOS `NovaPPEClient`); the design preview supplies its own. */
interface NovaPPEClient {
    val companies: suspend () -> List<NovaCompanyOption>
    suspend fun catalogue(company: String?): NovaPPECatalogue
    suspend fun board(query: NovaPPEQuery): NovaPPEBoard
    suspend fun detail(id: String): NovaPPEHandover
    suspend fun recordHandover(company: String, draft: NovaPPEHandoverDraft): NovaPPEHandover?
    suspend fun recordReturn(company: String, draft: NovaPPEReturnDraft): NovaPPEHandover?
    suspend fun removeReturn(company: String, handover: String, entry: String): NovaPPEHandover?
}

class NovaServicePPEClient(private val service: NovaPPEService, private val identity: IsgWorkspaceIdentity,
                           override val companies: suspend () -> List<NovaCompanyOption>) : NovaPPEClient {
    override suspend fun catalogue(company: String?) = service.catalogue(identity, company)
    override suspend fun board(query: NovaPPEQuery) = service.board(identity, query)
    override suspend fun detail(id: String) = service.detail(identity, id)
    override suspend fun recordHandover(company: String, draft: NovaPPEHandoverDraft) = service.recordHandover(identity, company, draft)
    override suspend fun recordReturn(company: String, draft: NovaPPEReturnDraft) = service.recordReturn(identity, company, draft)
    override suspend fun removeReturn(company: String, handover: String, entry: String) = service.removeReturn(identity, company, handover, entry)
}

internal fun ppeMessage(error: Throwable) = (error as? NovaPPEException)?.failure?.message ?: NovaPPEFailure.unavailable.message

private fun NovaPPEState.status() = when (this) {
    NovaPPEState.outstanding -> NovaStatus.Warning; NovaPPEState.partial -> NovaStatus.Info; NovaPPEState.closed -> NovaStatus.Success
}

@Composable
private fun HandoverCard(handover: NovaPPEHandover, modifier: Modifier, onClick: () -> Unit) {
    NovaCard(modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onClick).testTag("nova.ppe.row.${handover.id}"), padding = 14) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(handover.item, style = NovaTypeToken.cardTitle)
                    NovaText(listOfNotNull(handover.employeeName, handover.companyName).joinToString(" · "), style = NovaTypeToken.meta,
                        color = NovaColorToken.textSecondary.color())
                }
                NovaStatusPill(handover.state.title, handover.state.status())
            }
            NovaText(NovaPPEWords.explain(handover), style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaRowFact("shippingbox", "Zimmet", NovaPPEWords.amount(handover.quantity, handover.unit))
                NovaRowFact("calendar", "Tarih", NovaDay.label(handover.handedOn))
                handover.externalRef?.takeIf { it.isNotEmpty() }?.let { NovaRowFact("number", "Belge no", it) }
            }
            if (handover.lostQuantity > 0) NovaTag("questionmark.circle", "${NovaPPEWords.amount(handover.lostQuantity, handover.unit)} kayıp olarak kaydedildi",
                NovaStatus.Warning)
            if (handover.employeeArchived) NovaTag("person.badge.minus", "Personel kaydı arşivlendi")
        }
    }
}

/** KKD Zimmetleri (iOS `NovaPPEScreen`). */
@Composable
fun NovaPPEScreen(client: NovaPPEClient, canWrite: Boolean, onBack: () -> Unit, initialCompany: String? = null, headingOverride: String? = null,
                  startInAddMode: Boolean = false) {
    NovaPPEExampleScreen(onBack)
    return
    val coroutines = rememberCoroutineScope()
    var board by remember { mutableStateOf<NovaPPEBoard?>(null) }
    var catalogue by remember { mutableStateOf<NovaPPECatalogue?>(null) }
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var query by remember { mutableStateOf(NovaPPEQuery(company = initialCompany)) }
    var loading by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    var chooser by remember { mutableStateOf<String?>(null) }
    var detail by remember { mutableStateOf<NovaPPEHandover?>(null) }
    var handing by remember { mutableStateOf<NovaPPEHandoverDraft?>(null) }
    var returning by remember { mutableStateOf<NovaPPEReturnDraft?>(null) }
    var draftCompany by remember { mutableStateOf<String?>(null) }
    // Asking for a handover with no company chosen opens the company chooser first.
    var pendingCreate by remember { mutableStateOf(false) }
    fun startCreate() {
        draftCompany = query.company
        if (query.company == null) { pendingCreate = true; chooser = "company" } else handing = NovaPPEHandoverDraft(handedOn = NovaDay.today())
    }
    suspend fun load(reset: Boolean) {
        query = if (reset) query.copy(offset = 0) else query.copy(offset = query.offset + query.limit)
        loading = true; failure = null
        try {
            if (companies.isEmpty()) companies = client.companies()
            catalogue = client.catalogue(query.company)
            if (pendingCreate && query.company != null) { pendingCreate = false; draftCompany = query.company; handing = NovaPPEHandoverDraft(handedOn = NovaDay.today()) }
            val answer = client.board(query)
            val existing = board
            board = if (reset || existing == null) answer else answer.copy(rows = existing.rows + answer.rows)
        } catch (error: Exception) { failure = ppeMessage(error) }
        loading = false
    }
    fun reload() = coroutines.launch { load(true) }
    LaunchedEffect(Unit) { load(true); if (startInAddMode && query.company != null) startCreate() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaListHeading(headingOverride ?: NovaDestination.ppeHandovers.title, onBack, actionBelow = true) {
            if (canWrite) NovaListActionButton("Zimmet Ekle", "plus", identifier = "nova.ppe.add") { startCreate() }
        }
        NovaListHint(NovaPPEWords.signedCopyNote)
        board?.let { shown ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaPPEState.entries.forEach { state ->
                    NovaListStat(state.title, state.symbol, shown.count(state), Modifier.weight(1f).testTag("nova.ppe.stat.${state.wire}"),
                        selected = query.state == state.wire, status = when (state) {
                            NovaPPEState.outstanding -> NovaStatus.Warning
                            NovaPPEState.partial -> NovaStatus.Info
                            NovaPPEState.closed -> NovaStatus.Success
                        }) {
                        query = query.copy(state = if (query.state == state.wire) null else state.wire); reload()
                    }
                }
            }
        }
        NovaSearchCapsule(query.search, "Ekipman, kişi veya firma ara", "nova.ppe.search") { query = query.copy(search = it) }
        LaunchedEffect(query.search) { if (board != null) { kotlinx.coroutines.delay(350); load(true) } }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaChooserButton("Firma", companies.firstOrNull { it.id == query.company }?.name ?: "Tüm firmalar", "nova.ppe.chooser.company",
                Modifier.weight(1f), open = chooser == "company") { chooser = if (chooser == "company") null else "company" }
            NovaChooserButton("Durum", NovaPPEState.of(query.state)?.title ?: "Tüm durumlar", "nova.ppe.chooser.state", Modifier.weight(1f),
                open = chooser == "state") { chooser = if (chooser == "state") null else "state" }
        }
        if (chooser == "company") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm firmalar")) + companies.map { NovaChooserOption(it.id, it.name) },
            query.company, "nova.ppe.panel.company") { query = query.copy(company = it); chooser = null; reload() }
        if (chooser == "state") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm durumlar")) +
            NovaPPEState.entries.map { NovaChooserOption(it.wire, it.title, board?.count(it), it.symbol) }, query.state, "nova.ppe.panel.state") {
            query = query.copy(state = it); chooser = null; reload()
        }
        val shown = board
        shown?.let { NovaListSectionHeading("KKD Zimmetleri", "${it.total} zimmet") }
        when {
            loading && shown == null -> Box(Modifier.fillMaxWidth().padding(vertical = 30.dp), contentAlignment = Alignment.Center) {
                NovaSpinner(NovaColorToken.text.color(), size = 24.dp)
            }
            failure != null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText(failure!!, color = NovaColorToken.statusDangerInk.color()) }
            shown != null && shown.rows.isEmpty() -> NovaEmptyState("Henüz zimmet kaydı yok",
                "Firma personeline verilen kişisel koruyucu donanımı kaydedebilir ve zimmet formunu oluşturabilirsiniz.")
            shown != null -> NovaListEntrance(true) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    shown.rows.forEachIndexed { index, row ->
                        HandoverCard(row, Modifier.novaRowEntrance(index)) {
                            coroutines.launch {
                                draftCompany = row.companyId
                                try { catalogue = client.catalogue(row.companyId); detail = client.detail(row.id) }
                                catch (_: Exception) { failure = "Kayıt açılamadı. Yeniden deneyin." }
                            }
                        }
                    }
                    NovaText("${shown.rows.size} / ${shown.total} zimmet", style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
                    if (shown.hasMore) NovaButton("Daha fazla göster", { coroutines.launch { load(false) } }, variant = NovaButtonVariant.Surface,
                        symbol = "chevron.down")
                }
            }
        }
    }
    val open = detail
    NovaPopup(open != null, { detail = null }, identifier = "nova.ppe.detail") {
        if (open != null) PPEDetail(open, canWrite, onReturn = {
            detail = null
            returning = NovaPPEReturnDraft(open.id, open.item, open.outstanding, open.unit, returnedOn = NovaDay.today())
        }) { entry ->
            val company = open.companyId ?: query.company ?: return@PPEDetail NovaPPEFailure.validation.message
            try { client.removeReturn(company, open.id, entry)?.let { detail = it }; load(true); null } catch (error: Exception) { ppeMessage(error) }
        }
    }
    val hand = handing
    NovaPopup(hand != null, { handing = null }, identifier = "nova.ppe.form") {
        if (hand != null) HandoverSheet(hand, catalogue, onClose = { handing = null }) { draft ->
            val company = draftCompany ?: query.company ?: return@HandoverSheet NovaPPEFailure.validation.message
            try { client.recordHandover(company, draft); handing = null; load(true); null } catch (error: Exception) { ppeMessage(error) }
        }
    }
    val back = returning
    NovaPopup(back != null, { returning = null }, identifier = "nova.ppe.return") {
        if (back != null) ReturnSheet(back, catalogue, onClose = { returning = null }) { draft ->
            val company = draftCompany ?: query.company ?: return@ReturnSheet NovaPPEFailure.validation.message
            try { client.recordReturn(company, draft); returning = null; load(true); null } catch (error: Exception) { ppeMessage(error) }
        }
    }
}

/** One handover with every return against it; what is still out is the server's count. */
@Composable
private fun PPEDetail(handover: NovaPPEHandover, canWrite: Boolean, onReturn: () -> Unit, onRemoveReturn: suspend (String) -> String?) {
    val coroutines = rememberCoroutineScope()
    var failure by remember { mutableStateOf<String?>(null) }
    var working by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            NovaText(handover.item, style = NovaTypeToken.screenTitle)
            NovaText(listOfNotNull(handover.employeeName, handover.companyName).joinToString(" · "), style = NovaTypeToken.meta,
                color = NovaColorToken.textSecondary.color())
            NovaText(NovaPPEWords.explain(handover), style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaFactGrid(listOf(
                    { m -> NovaFactCell("shippingbox", "Zimmet", NovaPPEWords.amount(handover.quantity, handover.unit), m) },
                    { m -> NovaFactCell("arrow.uturn.backward", "İade edilen", NovaPPEWords.amount(handover.returnedQuantity, handover.unit), m) },
                    { m -> NovaFactCell("person.badge.shield.checkmark", "Hâlâ zimmette", NovaPPEWords.amount(handover.outstanding, handover.unit), m) },
                    { m -> NovaFactCell("calendar", "Tarih", NovaDay.label(handover.handedOn), m) }))
                handover.signedCopyLocation?.takeIf { it.isNotEmpty() }?.let { NovaHelpHint("İmzalı form: $it") }
                NovaText(NovaPPEWords.signedCopyNote, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            }
        }
        failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
        if (canWrite && handover.outstanding > 0) NovaButton("İade kaydet", onReturn, symbol = "arrow.uturn.backward")
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaText("İadeler", style = NovaTypeToken.cardTitle)
            if (handover.returns.isEmpty()) NovaText("Henüz iade kaydı yok.", style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
            handover.returns.forEach { entry ->
                NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            NovaIcon(entry.condition.symbol, 12.dp, tint = NovaColorToken.textMuted.color())
                            NovaText("${NovaPPEWords.amount(entry.quantity, handover.unit)} · ${entry.condition.title}", Modifier.weight(1f))
                            NovaSizedText(NovaDay.label(entry.returnedOn), 10.5f, FontWeight.Medium, NovaColorToken.textSecondary.color())
                        }
                        entry.note?.takeIf { it.isNotEmpty() }?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color()) }
                        // A correction, not a rewrite: the outstanding amount is recounted rather than patched.
                        if (canWrite) NovaButton("Bu iadeyi geri al", {
                            coroutines.launch { working = true; failure = onRemoveReturn(entry.id); working = false }
                        }, variant = NovaButtonVariant.Surface, symbol = "arrow.uturn.left", enabled = !working)
                    }
                }
            }
        }
    }
}

/** An outlined choice chip used for units and return conditions. */
@Composable
private fun OutlineChip(title: String, on: Boolean, identifier: String, symbol: String? = null, onClick: () -> Unit) {
    val ink = if (on) NovaColorToken.accentInk.color() else NovaColorToken.textSecondary.color()
    Row(Modifier.clip(RoundedCornerShape(9.dp)).border(1.dp, NovaColorToken.hairline.color(), RoundedCornerShape(9.dp)).novaRowPress(onClick = onClick)
        .padding(vertical = 6.dp, horizontal = 8.dp).testTag(identifier).semantics { selected = on },
        horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        symbol?.let { NovaIcon(it, 10.dp, tint = ink) }
        NovaSizedText(title, 10f, if (on) FontWeight.Bold else FontWeight.Medium, ink)
    }
}

/** Recording a handover; there is no field for a signed copy, only a note of where the form is. */
@Composable
private fun HandoverSheet(initial: NovaPPEHandoverDraft, catalogue: NovaPPECatalogue?, onClose: () -> Unit, onSave: suspend (NovaPPEHandoverDraft) -> String?) {
    val coroutines = rememberCoroutineScope()
    val busy = LocalNovaPopupBusy.current
    var draft by remember { mutableStateOf(initial) }
    var failure by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    val people = catalogue?.employees.orEmpty()
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaText("Zimmet ver", style = NovaTypeToken.screenTitle)
        NovaChoiceField("Personel", "Personel seçin", "person", people.map { NovaChoiceOption(it.id, it.fullName) }, draft.employeeId,
            { draft = draft.copy(employeeId = it) }, "nova.ppe.form.person", searchable = true, boxed = true)
        if (people.isEmpty()) NovaHelpHint("Bu firmada aktif personel kaydı yok.")
        NovaTextField("Ekipman", draft.item, { draft = draft.copy(item = it) }, identifier = "nova.ppe.form.item")
        NovaText(NovaPPEWords.noCatalogueNote, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        NovaTextField("Miktar", draft.quantity, { draft = draft.copy(quantity = it) }, identifier = "nova.ppe.form.quantity", keyboardType = KeyboardType.Decimal)
        NovaText("Birim", style = NovaTypeToken.label)
        // Only the units the server accepts.
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            (catalogue?.units?.ifEmpty { null } ?: NovaPPEUnit.entries).forEach { unit ->
                OutlineChip(unit.title, draft.unit == unit, "nova.ppe.form.unit.${unit.wire}") { draft = draft.copy(unit = unit) }
            }
        }
        NovaDayField("Tarih", draft.handedOn, { draft = draft.copy(handedOn = it) }, "nova.ppe.form.date")
        NovaTextField("Belge no", draft.externalRef, { draft = draft.copy(externalRef = it) }, identifier = "nova.ppe.form.ref")
        NovaTextField("İmzalı form nerede", draft.signedCopyLocation, { draft = draft.copy(signedCopyLocation = it) }, identifier = "nova.ppe.form.location")
        NovaText(NovaPPEWords.signedCopyNote, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaButton("Vazgeç", onClose, Modifier.weight(1f), variant = NovaButtonVariant.Surface, symbol = "xmark")
            NovaButton("Kaydet", { coroutines.launch { saving = true; busy(true); failure = onSave(draft); saving = false; busy(false) } },
                Modifier.weight(1f), symbol = "checkmark", enabled = !saving && draft.employeeId != null && draft.item.isNotBlank(), loading = saving)
        }
    }
}

/** Recording a return; the form says what is still out and the server refuses anything above it. */
@Composable
private fun ReturnSheet(initial: NovaPPEReturnDraft, catalogue: NovaPPECatalogue?, onClose: () -> Unit, onSave: suspend (NovaPPEReturnDraft) -> String?) {
    val coroutines = rememberCoroutineScope()
    val busy = LocalNovaPopupBusy.current
    var draft by remember { mutableStateOf(initial) }
    var failure by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaText("İade kaydet", style = NovaTypeToken.screenTitle)
        if (draft.item.isNotEmpty()) NovaText(draft.item, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        NovaHelpHint("Hâlâ zimmette olan: ${NovaPPEWords.amount(draft.outstanding, draft.unit)}. Bundan fazlası kaydedilemez.")
        NovaTextField("Miktar", draft.quantity, { draft = draft.copy(quantity = it) }, identifier = "nova.ppe.return.quantity", keyboardType = KeyboardType.Decimal)
        NovaDayField("İade tarihi", draft.returnedOn, { draft = draft.copy(returnedOn = it) }, "nova.ppe.return.date")
        NovaText("Durum", style = NovaTypeToken.label)
        // Only the conditions the server accepts.
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            (catalogue?.conditions?.ifEmpty { null } ?: NovaPPECondition.entries).forEach { condition ->
                OutlineChip(condition.title, draft.condition == condition, "nova.ppe.return.condition.${condition.wire}", condition.symbol) {
                    draft = draft.copy(condition = condition)
                }
            }
        }
        NovaTextField("Not", draft.note, { draft = draft.copy(note = it) }, identifier = "nova.ppe.return.note", multiline = true)
        failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaButton("Vazgeç", onClose, Modifier.weight(1f), variant = NovaButtonVariant.Surface, symbol = "xmark")
            NovaButton("İadeyi kaydet", { coroutines.launch { saving = true; busy(true); failure = onSave(draft); saving = false; busy(false) } },
                Modifier.weight(1f), symbol = "checkmark", enabled = !saving && draft.quantity.isNotBlank(), loading = saving)
        }
    }
}
