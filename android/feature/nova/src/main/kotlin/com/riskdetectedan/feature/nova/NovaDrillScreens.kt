package com.riskdetectedan.feature.nova

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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.launch

/** The module's calls bound to one identity (iOS `NovaDrillClient`); the design preview supplies its own. */
interface NovaDrillClient {
    val companies: suspend () -> List<NovaCompanyOption>
    suspend fun catalogue(company: String?): NovaDrillCatalogue
    suspend fun board(query: NovaDrillQuery): NovaDrillBoard
    suspend fun detail(id: String): NovaDrill
    suspend fun plan(company: String, draft: NovaDrillPlanDraft): NovaDrill?
    suspend fun record(company: String, draft: NovaDrillResultDraft): NovaDrill?
    suspend fun cancel(company: String, drill: String, reason: String): NovaDrill?
    /** Reopens a drill for correction or removal; absent where records are not editable. */
    val manage: NovaModuleManage? get() = null
}

class NovaServiceDrillClient(private val service: NovaDrillService, private val identity: IsgWorkspaceIdentity,
                             override val companies: suspend () -> List<NovaCompanyOption>,
                             override val manage: NovaModuleManage? = null) : NovaDrillClient {
    override suspend fun catalogue(company: String?) = service.catalogue(identity, company)
    override suspend fun board(query: NovaDrillQuery) = service.board(identity, query)
    override suspend fun detail(id: String) = service.detail(identity, id)
    override suspend fun plan(company: String, draft: NovaDrillPlanDraft) = service.plan(identity, company, draft)
    override suspend fun record(company: String, draft: NovaDrillResultDraft) = service.record(identity, company, draft)
    override suspend fun cancel(company: String, drill: String, reason: String) = service.cancel(identity, company, drill, reason)
}

internal fun drillMessage(error: Throwable) = (error as? NovaDrillException)?.failure?.message ?: NovaDrillFailure.unavailable.message

private fun NovaDrillState.status() = when (this) {
    NovaDrillState.overdue -> NovaStatus.Danger; NovaDrillState.dueSoon -> NovaStatus.Info; NovaDrillState.scheduled -> NovaStatus.Warning
    NovaDrillState.performed -> NovaStatus.Success; NovaDrillState.cancelled -> NovaStatus.Neutral
}


@Composable
private fun DrillCard(drill: NovaDrill, modifier: Modifier, onClick: () -> Unit) {
    NovaCard(modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onClick).testTag("nova.drill.row.${drill.id}"), padding = 14) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(drill.planScope ?: "Acil durum planı", style = NovaTypeToken.cardTitle)
                    NovaText(listOfNotNull(drill.workplaceName, drill.companyName).joinToString(" · "), style = NovaTypeToken.meta,
                        color = NovaColorToken.textSecondary.color())
                }
                NovaStatusPill(drill.state.title, drill.state.status())
            }
            NovaText(drill.explain, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaRowFact("calendar", "Planlanan", NovaDay.label(drill.plannedOn))
                drill.performedOn?.let { NovaRowFact("checkmark.circle", "Yapılan", NovaDay.label(it)) }
                NovaRowFact("number", "Plan sürümü", "v${drill.planVersion}")
            }
            if (drill.planVersionSuperseded) NovaTag("arrow.triangle.branch", "Prova edilen plan sürümü güncellendi", NovaStatus.Info)
        }
    }
}

/** Tatbikatlar (iOS `NovaDrillScreen`). */
@Composable
fun NovaDrillScreen(client: NovaDrillClient, canWrite: Boolean, onBack: () -> Unit, initialCompany: String? = null, headingOverride: String? = null) {
    val coroutines = rememberCoroutineScope()
    var board by remember { mutableStateOf<NovaDrillBoard?>(null) }
    var catalogue by remember { mutableStateOf<NovaDrillCatalogue?>(null) }
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var query by remember { mutableStateOf(NovaDrillQuery(company = initialCompany)) }
    var loading by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    var chooser by remember { mutableStateOf<String?>(null) }
    var detail by remember { mutableStateOf<NovaDrill?>(null) }
    var planning by remember { mutableStateOf<NovaDrillPlanDraft?>(null) }
    var recording by remember { mutableStateOf<NovaDrillResultDraft?>(null) }
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
        } catch (error: Exception) { failure = drillMessage(error) }
        loading = false
    }
    fun reload() = coroutines.launch { load(true) }
    suspend fun save(work: suspend (String) -> Unit): String? {
        val company = draftCompany ?: query.company ?: return NovaDrillFailure.validation.message
        return try { work(company); load(true); null } catch (error: Exception) { drillMessage(error) }
    }
    val plan = planning
    if (plan != null) {
        NovaCompanyCreateFlow("Tatbikat planla", client.companies, { company -> client.catalogue(company) }, initialCompany, { planning = null }) { selected, company ->
            LaunchedEffect(company) { draftCompany = company }
            DrillPlanSheet(plan, selected, onSave = { draft -> save { client.plan(it, draft) } }, onClose = { planning = null })
        }
        return
    }
    val result = recording
    if (result != null) {
        DrillResultSheet(result, catalogue, onSave = { draft -> save { client.record(it, draft) } }, onClose = { recording = null })
        return
    }
    LaunchedEffect(Unit) { load(true) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaListHeading(headingOverride ?: NovaDestination.drills.title, onBack) {
            if (canWrite) NovaButton("Tatbikat Ekle", { draftCompany = null; planning = NovaDrillPlanDraft(plannedOn = NovaDay.today()) }, symbol = "plus", compact = true)
        }
        NovaHelpHint("Firmanın tatbikat kayıtlarını ve gerçekleşme sonuçlarını inceleyin. ${NovaDrillWords.planningIsNotPerforming} ${NovaDrillWords.noPlan}")
        board?.let { shown ->
            val columns = if (novaFontScaleIsAccessibility()) 2 else 4
            NovaDrillGroup.entries.chunked(columns).forEach { chunk ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    chunk.forEach { group ->
                        NovaListStat(group.title, group.symbol, shown.count(group), Modifier.weight(1f).testTag("nova.drill.stat.${group.wire}"),
                            selected = query.state == group.wire) {
                            query = query.copy(state = if (query.state == group.wire) null else group.wire); reload()
                        }
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaChooserButton("Firma", companies.firstOrNull { it.id == query.company }?.name ?: "Tüm firmalar", "nova.drill.chooser.company",
                Modifier.weight(1f), open = chooser == "company") { chooser = if (chooser == "company") null else "company" }
            val stateTitle = query.state?.let { value -> NovaDrillGroup.ofWire(value)?.title ?: NovaDrillState.of(value)?.title } ?: "Tüm durumlar"
            NovaChooserButton("Durum", stateTitle, "nova.drill.chooser.state", Modifier.weight(1f), open = chooser == "state") {
                chooser = if (chooser == "state") null else "state"
            }
        }
        if (chooser == "company") NovaChooserPanel((if (initialCompany == null) listOf(NovaChooserOption(null, "Tüm firmalar")) else emptyList()) +
            companies.filter { initialCompany == null || it.id == initialCompany }.map { NovaChooserOption(it.id, it.name) },
            query.company, "nova.drill.panel.company") { query = query.copy(company = it); chooser = null; reload() }
        if (chooser == "state") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm durumlar")) +
            NovaDrillGroup.entries.map { NovaChooserOption(it.wire, it.title, board?.count(it), it.symbol) } +
            NovaDrillState.entries.filter { state -> NovaDrillGroup.entries.none { it.wire == state.wire } }
                .map { NovaChooserOption(it.wire, it.title, board?.counts?.get(it.wire)) }, query.state, "nova.drill.panel.state") {
            query = query.copy(state = it); chooser = null; reload()
        }
        NovaSearchCapsule(query.search, "Plan, işyeri veya firma ara", "nova.drill.search") { query = query.copy(search = it) }
        LaunchedEffect(query.search) { if (board != null) { kotlinx.coroutines.delay(350); load(true) } }
        val shown = board
        when {
            loading && shown == null -> Box(Modifier.fillMaxWidth().padding(vertical = 30.dp), contentAlignment = Alignment.Center) {
                NovaSpinner(NovaColorToken.text.color(), size = 24.dp)
            }
            failure != null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText(failure!!, color = NovaColorToken.statusDangerInk.color()) }
            shown != null && shown.rows.isEmpty() -> NovaEmptyState("Henüz tatbikat kaydı yok",
                "Gerçekleşen tatbikatı fotoğraf, dosya, süre ve senaryo bilgileriyle kaydedip takip edebilirsiniz.")
            shown != null -> NovaListEntrance(true) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    shown.rows.forEachIndexed { index, drill ->
                        DrillCard(drill, Modifier.novaRowEntrance(index)) {
                            coroutines.launch {
                                draftCompany = drill.companyId
                                try { catalogue = client.catalogue(drill.companyId); detail = client.detail(drill.id) }
                                catch (_: Exception) { failure = "Kayıt açılamadı. Yeniden deneyin." }
                            }
                        }
                    }
                    NovaText("${shown.rows.size} / ${shown.total} tatbikat", style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
                    if (shown.hasMore) NovaButton("Daha fazla göster", { coroutines.launch { load(false) } }, variant = NovaButtonVariant.Surface,
                        symbol = "chevron.down")
                }
            }
        }
    }
    val open = detail
    NovaPopup(open != null, { detail = null }, identifier = "nova.drill.detail") {
        if (open != null) {
            DrillDetail(open, canWrite, onRecord = {
                detail = null
                recording = NovaDrillResultDraft(open.id, open.planScope.orEmpty(), NovaDay.today())
            }) { reason ->
                val company = open.companyId ?: query.company ?: return@DrillDetail NovaDrillFailure.validation.message
                try { client.cancel(company, open.id, reason)?.let { detail = it }; load(true); null } catch (error: Exception) { drillMessage(error) }
            }
            val manage = client.manage
            val company = open.companyId
            if (canWrite && manage != null && company != null) Box(Modifier.padding(horizontal = 12.dp, vertical = 12.dp)) {
                NovaModuleManageAction(manage, "drill", company, open.id) { detail = null; coroutines.launch { load(true) } }
            }
        }
    }
}

/** One drill: what it rehearsed, when, who was there and what came out of it. */
@Composable
private fun DrillDetail(drill: NovaDrill, canWrite: Boolean, onRecord: () -> Unit, onCancel: suspend (String) -> String?) {
    val coroutines = rememberCoroutineScope()
    var reason by remember { mutableStateOf("") }
    var askingCancel by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    var working by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            NovaPopupHeading(drill.planScope ?: "Acil durum planı", symbol = "figure.walk")
            NovaText(listOfNotNull(drill.workplaceName, drill.companyName).joinToString(" · "), style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            NovaText(drill.explain, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    NovaFactCell("calendar", "Planlanan", NovaDay.label(drill.plannedOn), Modifier.weight(1f))
                    NovaFactCell("checkmark.circle", "Yapılan", drill.performedOn?.let(NovaDay::label) ?: "Yapılmadı", Modifier.weight(1f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    NovaFactCell("doc.text", "Plan sürümü", "v${drill.planVersion}", Modifier.weight(1f),
                        if (drill.planVersionSuperseded) "sonradan güncellendi" else "")
                    NovaFactCell("person.2", "Katılımcı", "${drill.participantCount}", Modifier.weight(1f))
                }
                NovaHelpHint(NovaDrillWords.pinnedNote)
            }
        }
        if (drill.performed) {
            drill.observation?.takeIf { it.isNotEmpty() }?.let {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) { NovaText("Gözlem", style = NovaTypeToken.label); NovaText(it) }
            }
            drill.improvement?.takeIf { it.isNotEmpty() }?.let {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) { NovaText("İyileştirme", style = NovaTypeToken.label); NovaText(it) }
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                NovaText("Katılımcı", style = NovaTypeToken.cardTitle)
                drill.participants.forEach { person ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon("person", 11.dp, tint = NovaColorToken.textMuted.color()); NovaText(person.fullName)
                    }
                }
                if (drill.participantsSnapshotted) NovaText(NovaDrillWords.snapshotNote, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            }
        }
        failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
        if (canWrite && !drill.performed && drill.state != NovaDrillState.cancelled) Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaButton("Tatbikat kaydı gir", onRecord, symbol = "square.and.pencil")
            if (askingCancel) {
                NovaTextField("İptal gerekçesi", reason, { reason = it }, identifier = "nova.drill.detail.reason")
                NovaButton("İptali onayla", {
                    val trimmed = reason.trim()
                    if (trimmed.isNotEmpty()) coroutines.launch { working = true; failure = onCancel(trimmed); working = false }
                }, variant = NovaButtonVariant.Surface, symbol = "xmark.circle", enabled = !working, loading = working)
            } else NovaButton("Tatbikatı iptal et", { askingCancel = true }, variant = NovaButtonVariant.Surface, symbol = "xmark.circle")
        }
    }
}



/** Planning a drill; the plan is chosen and the server pins its version. */
@Composable
private fun DrillPlanSheet(initial: NovaDrillPlanDraft, catalogue: NovaDrillCatalogue?, onSave: suspend (NovaDrillPlanDraft) -> String?, onClose: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    var draft by remember { mutableStateOf(initial) }
    var failure by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    var choosing by remember { mutableStateOf(false) }
    var step by remember { mutableIntStateOf(0) }
    var saved by remember { mutableStateOf(false) }
    val plans = catalogue?.plans.orEmpty()
    val chosen = plans.firstOrNull { it.planId == draft.planId }
    if (saved) {
        NovaTaskSuccessView("Tatbikat planlandı", "Plan tarihi ve prova edilecek acil durum planı firma kaydına eklendi.", "Tatbikatlara dön", onClose)
        return
    }
    val goBack: () -> Unit = { failure = null; if (step > 0) step-- else onClose() }
    NovaModuleTask("Tatbikat planla", step + 1, 3, listOf("Plan seçimi", "Tarih", "Kontrol")[step], if (step == 2) "Tatbikatı planla" else "Devam",
        if (step == 2) "checkmark" else "arrow.right", saving, goBack, {
            failure = null
            when {
                step == 0 && draft.planId == null -> failure = "Prova edilecek planı seçin."
                step < 2 -> step++
                else -> coroutines.launch { saving = true; val result = onSave(draft); saving = false; if (result != null) failure = result else saved = true }
            }
        }, failure) {
        when (step) {
            0 -> {
                NovaHelpHint("Prova edilecek planı seçin. Plan sürümü arka planda sabitlenir ve sonraki adımlara taşınır.")
                if (plans.isEmpty()) NovaHelpHint(NovaDrillWords.noPlan)
                else {
                    NovaChooserButton("Prova edilecek plan", chosen?.let { "${it.scope} · ${it.workplaceName}" } ?: "Plan seçin", "nova.drill.form.plan",
                        open = choosing) { choosing = !choosing }
                    if (choosing) NovaChooserPanel(plans.map { NovaChooserOption(it.planId, "${it.scope} · ${it.workplaceName}") }, draft.planId,
                        "nova.drill.form.plan.panel") { draft = draft.copy(planId = it); choosing = false }
                    chosen?.let { NovaWhyDisclosure { NovaText("Planın yürürlükteki ${it.version}. sürümü prova edilecek.", style = NovaTypeToken.metaQuiet) } }
                }
            }
            1 -> {
                NovaDayField("Planlanan", draft.plannedOn, { draft = draft.copy(plannedOn = it) }, "nova.drill.form.planned")
                NovaText(NovaDrillWords.planningIsNotPerforming, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            }
            else -> NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                NovaText("Tatbikat özeti", style = NovaTypeToken.bodyStrong)
                NovaText(chosen?.let { "${it.scope} · ${it.workplaceName}" } ?: "Plan seçilmedi")
                NovaText(NovaDay.label(draft.plannedOn), style = NovaTypeToken.metaQuiet)
            }
        }
    }
}

/** Recording what happened; participants come from the company's own register and freeze as named now. */
@Composable
private fun DrillResultSheet(initial: NovaDrillResultDraft, catalogue: NovaDrillCatalogue?, onSave: suspend (NovaDrillResultDraft) -> String?, onClose: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    var draft by remember { mutableStateOf(initial) }
    var failure by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    var step by remember { mutableIntStateOf(0) }
    var saved by remember { mutableStateOf(false) }
    if (saved) {
        NovaTaskSuccessView("Tatbikat kaydedildi", "Tarih, katılımcılar, gözlem ve iyileştirme bilgileri firma kaydına eklendi.", "Tatbikatlara dön", onClose)
        return
    }
    val goBack: () -> Unit = { failure = null; if (step > 0) step-- else onClose() }
    NovaModuleTask("Tatbikat kaydı", step + 1, 4, listOf("Tarih", "Katılımcılar", "Sonuçlar", "Kontrol")[step],
        if (step == 3) "Tatbikatı kaydet" else "Devam", if (step == 3) "checkmark" else "arrow.right", saving, goBack, {
            failure = null
            when {
                step == 1 && draft.participants.isEmpty() -> failure = "En az bir katılımcı seçin."
                step < 3 -> step++
                else -> coroutines.launch { saving = true; val result = onSave(draft); saving = false; if (result != null) failure = result else saved = true }
            }
        }, failure) {
        when (step) {
            0 -> {
                if (draft.planScope.isNotEmpty()) NovaText(draft.planScope, style = NovaTypeToken.bodyStrong)
                NovaDayField("Yapılan", draft.performedOn, { draft = draft.copy(performedOn = it) }, "nova.drill.result.performed")
            }
            1 -> {
                NovaText("Katılımcı", style = NovaTypeToken.label)
                val people = catalogue?.employees.orEmpty()
                if (people.isEmpty()) NovaText("Bu firmada aktif personel kaydı yok.", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                // Only this company's own people are offered; the server refuses anyone else anyway.
                people.forEach { person ->
                    val on = person.id in draft.participants
                    Row(Modifier.fillMaxWidth().heightIn(min = 40.dp).novaRowPress {
                        draft = draft.copy(participants = if (on) draft.participants - person.id else draft.participants + person.id)
                    }.testTag("nova.drill.result.person.${person.id}").semantics { role = Role.Checkbox; selected = on },
                        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon(if (on) "checkmark.square.fill" else "square", 14.dp,
                            tint = if (on) NovaColorToken.accentInk.color() else NovaColorToken.textMuted.color())
                        NovaText(person.fullName)
                    }
                }
                NovaText(NovaDrillWords.snapshotNote, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            }
            2 -> {
                NovaTextField("Gözlem", draft.observation, { draft = draft.copy(observation = it) }, identifier = "nova.drill.result.observation", multiline = true)
                NovaTextField("İyileştirme", draft.improvement, { draft = draft.copy(improvement = it) }, identifier = "nova.drill.result.improvement", multiline = true)
            }
            else -> NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                NovaText("Tatbikat özeti", style = NovaTypeToken.bodyStrong)
                NovaText(draft.planScope)
                NovaText("${NovaDay.label(draft.performedOn)} · ${draft.participants.size} katılımcı", style = NovaTypeToken.metaQuiet)
            }
        }
    }
}
