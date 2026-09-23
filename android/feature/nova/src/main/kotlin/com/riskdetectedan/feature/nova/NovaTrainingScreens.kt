package com.riskdetectedan.feature.nova

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlin.math.ceil

/** The module's calls bound to one identity; the design preview supplies its own. */
interface NovaTrainingClient {
    val companies: suspend () -> List<NovaCompanyOption>
    /** The signed-in expert's own name, offered as a one-tap trainer. */
    val userName: String
    suspend fun page(after: String?): NovaTrainingService.Page
    suspend fun employees(company: String): List<NovaPersonOption>
    suspend fun context(id: String?): NovaEducationContext
    fun draft(id: String?): NovaEducationDraft?
    fun preserve(draft: NovaEducationDraft)
    fun discardDraft(id: String?)
    fun pending(): NovaEducationDraft?
    suspend fun save(draft: NovaEducationDraft): NovaTrainingService.Receipt
    suspend fun certificate(request: NovaEducationCertificateRequest): NovaEducationCertificate
    suspend fun logo(path: String?): String?
}

class NovaServiceTrainingClient(private val service: NovaTrainingService, private val identity: IsgWorkspaceIdentity,
                                override val companies: suspend () -> List<NovaCompanyOption>, override val userName: String,
                                private val people: suspend (String) -> List<NovaPersonOption>) : NovaTrainingClient {
    override suspend fun page(after: String?) = service.list(identity, after = after)
    override suspend fun employees(company: String): List<NovaPersonOption> {
        service.check(identity)
        return people(company).also { service.check(identity) }
    }
    override suspend fun context(id: String?) = service.context(identity, id)
    override fun draft(id: String?) = service.draft(identity, id)
    override fun preserve(draft: NovaEducationDraft) = service.preserve(identity, draft)
    override fun discardDraft(id: String?) = service.discardDraft(identity, id)
    override fun pending() = service.pending(identity)
    override suspend fun save(draft: NovaEducationDraft) = service.save(identity, draft)
    override suspend fun certificate(request: NovaEducationCertificateRequest) = service.certificate(identity, request)
    override suspend fun logo(path: String?) = service.logo(identity, path)
}

private fun hours(minutes: Int): String {
    val value = minutes / 60.0
    return if (value == Math.rint(value)) value.toInt().toString() else String.format(java.util.Locale.forLanguageTag("tr-TR"), "%.1f", value)
}

private fun duration(minutes: Int): String {
    val hours = minutes / 60; val rest = minutes % 60
    return when { hours == 0 -> "$rest dk"; rest == 0 -> "$hours sa"; else -> "$hours sa $rest dk" }
}

private class TrainingEditorTarget(val session: NovaTrainingSession?)

/** Eğitimler (iOS `NovaTrainingHub` + `NovaTrainingRegister`): realized trainings, their people and hours. */
@Composable
fun NovaTrainingScreen(client: NovaTrainingClient, canWrite: Boolean, onBack: () -> Unit, createOnOpen: Boolean = false, initialCompany: String? = null) {
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var sessions by remember { mutableStateOf<List<NovaTrainingSession>?>(null) }
    var writable by remember { mutableStateOf<Set<String>>(emptySet()) }
    var company by remember { mutableStateOf(initialCompany) }
    var query by remember { mutableStateOf("") }
    var cycle by remember { mutableStateOf<String?>(null) }
    var dateFilter by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    var employeeTotal by remember { mutableStateOf<Int?>(null) }
    var editor by remember { mutableStateOf<TrainingEditorTarget?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    var didOpen by remember { mutableStateOf(false) }
    val open = editor
    if (open != null) {
        val allowed = canWrite && (open.session?.companies?.all { it.companyId.lowercase() in writable } ?: writable.isNotEmpty())
        NovaEducationEntry(client, companies, writable, company, open.session, allowed) { editor = null; revision++ }
        return
    }
    LaunchedEffect(revision) {
        loading = true; failure = null
        try {
            companies = client.companies()
            val rows = mutableListOf<NovaTrainingSession>(); var after: String? = null; val seen = mutableSetOf<String>()
            do {
                val page = client.page(after)
                rows += page.rows; writable = page.writableCompanies; after = page.nextId
                if (after != null && !seen.add(after)) throw NovaTrainingException("UNAVAILABLE")
            } while (after != null)
            sessions = rows
            if (createOnOpen && !didOpen && canWrite && writable.isNotEmpty()) { didOpen = true; editor = TrainingEditorTarget(null) }
        } catch (error: Exception) { failure = NovaTrainingWords.message(error) }
        loading = false
    }
    LaunchedEffect(company) {
        employeeTotal = null
        company?.let { selected -> employeeTotal = runCatching { client.employees(selected).size }.getOrNull() }
    }
    val all = sessions.orEmpty()
    val visible = all.filter { session ->
        (company == null || session.companies.any { it.companyId.sameId(company) }) &&
            (query.isBlank() || session.title.contains(query.trim(), true) || session.trainer.contains(query.trim(), true)) &&
            (dateFilter.isBlank() || session.heldOn.startsWith(dateFilter.trim())) &&
            (cycle == null || session.education?.scopes?.any { it.cycle == cycle } == true)
    }.sortedByDescending { it.heldOn }
    val completed = all.flatMap { it.companies }.filter { it.state == "completed" && (company == null || it.companyId.sameId(company)) }
    val trained = completed.flatMap { scope -> scope.participants.filter { it.attended }.map { it.id.lowercase() } }.toSet()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaListHeading("Eğitimler", onBack) {
            if (canWrite) NovaButton("Eğitim Ekle", { editor = TrainingEditorTarget(null) }, Modifier.testTag("training.add.header"), symbol = "plus",
                compact = true, enabled = !loading && failure == null && writable.isNotEmpty())
        }
        NovaFilterField("Firma", listOf(NovaChooserOption(null, "Tüm firmalar")) + companies.map { NovaChooserOption(it.id, it.name) }, company,
            "training.company") { company = it }
        NovaHelpHint("Gerçekleşen eğitimi ve katılımcılarını kaydedin. Aynı eğitimde birden fazla firmanın personelini seçebilirsiniz.")
        NovaMetricStrip(listOf(
            NovaMetricStripItem("minutes", hours(completed.sumOf { it.durationMinutes }), "Eğitim saati", "clock", NovaStatus.Neutral),
            NovaMetricStripItem("people", trained.size.toString(), "Eğitim alan", "person.2", NovaStatus.Success),
            NovaMetricStripItem("person-minutes", hours(completed.sumOf { scope -> scope.durationMinutes * scope.participants.count { it.attended } }),
                "Adam × saat", "person.badge.clock", NovaStatus.Neutral),
            NovaMetricStripItem("missing", employeeTotal?.let { maxOf(0, it - trained.size).toString() } ?: "—", "Eğitimi eksik",
                "person.crop.circle.badge.exclamationmark", NovaStatus.Warning),
        ), Modifier.testTag("training.stats"))
        NovaSearchCapsule(query, "Eğitim veya eğitmen ara…", "training.search") { query = it }
        NovaFilterField("Eğitim türü", listOf(NovaChooserOption(null, "Tüm eğitim türleri")) +
            NovaEducationScope.cycles.map { NovaChooserOption(it.first, it.second) }, cycle, "training.cycle") { cycle = it }
        NovaTextField("Tarih (YYYY-AA-GG)", dateFilter, { dateFilter = it }, identifier = "training.date", keyboardType = KeyboardType.Number)
        NovaText("${visible.size} eğitim", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        when {
            loading && sessions == null -> Box(Modifier.fillMaxWidth().padding(vertical = 30.dp), contentAlignment = Alignment.Center) {
                NovaSpinner(NovaColorToken.text.color(), size = 24.dp)
            }
            failure != null -> {
                NovaHelpHint(failure!!)
                NovaButton("Yenile", { revision++ }, variant = NovaButtonVariant.Surface, symbol = "arrow.clockwise")
            }
            visible.isEmpty() -> NovaEmptyState("Henüz eğitim kaydı yok",
                "Gerçekleşen eğitimi ekleyerek katılımcıları, süreleri ve eksik eğitim konularını personel bazında takip edebilirsiniz.")
            else -> NovaListEntrance(true) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    visible.forEachIndexed { index, session -> TrainingCard(session, Modifier.novaRowEntrance(index)) { editor = TrainingEditorTarget(session) } }
                }
            }
        }
    }
}

@Composable
private fun TrainingCard(session: NovaTrainingSession, modifier: Modifier, onClick: () -> Unit) {
    NovaCard(modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onClick).testTag("training.row.${session.id}"), padding = 15) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("graduationcap", 15.dp)
                NovaText(session.title, Modifier.weight(1f), NovaTypeToken.cardTitle)
                NovaIcon("chevron.right", 11.dp, tint = NovaColorToken.textMuted.color())
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                NovaRowFact("calendar", "Tarih", NovaDay.label(session.heldOn.take(10)))
                NovaRowFact("person.2", "Katılımcı", session.count.toString())
                NovaRowFact("person.crop.rectangle", "Yöntem", NovaTrainingWords.method(session.method))
            }
            NovaText(session.companies.joinToString(" · ") { it.companyName }, style = NovaTypeToken.meta, maxLines = 2)
            if (session.isLegacyPlan) NovaText("Önceki plan · gerçekleştiği henüz doğrulanmadı", style = NovaTypeToken.meta,
                color = NovaColorToken.statusWarningInk.color())
            else if (session.companies.all { it.state == "cancelled" }) NovaText("Önceki iptal kaydı", style = NovaTypeToken.meta,
                color = NovaColorToken.textSecondary.color())
        }
    }
}

/** Loads the record's context, then opens the guided editor; a failure keeps its own back control. */
@Composable
private fun NovaEducationEntry(client: NovaTrainingClient, companies: List<NovaCompanyOption>, writable: Set<String>, initialCompany: String?,
                               original: NovaTrainingSession?,
                               canWrite: Boolean, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    var context by remember { mutableStateOf<NovaEducationContext?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(attempt) {
        try { context = client.context(original?.id); failure = null } catch (error: Exception) { failure = NovaTrainingWords.message(error) }
    }
    val loaded = context
    when {
        loaded != null -> NovaEducationEditor(client, companies.filter { it.id.lowercase() in writable }, initialCompany, loaded.row ?: original, loaded, canWrite, onClose)
        failure != null -> Column(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            NovaBackButton(onClick = onClose)
            NovaText(failure!!)
            NovaButton("Yeniden dene", { attempt++ }, variant = NovaButtonVariant.Surface, symbol = "arrow.clockwise")
        }
        else -> NovaLoadingView("Eğitim açılıyor…")
    }
}

private val basicCycles = setOf("initial", "periodic_repeat")

/**
 * The editor's state (iOS `NovaEducationEditor`). One training is one curriculum shared by every
 * company attending it: [template] carries the curriculum, method, schedule and location and is
 * mirrored into every scope; participants are the one thing that stays per company.
 */
@Stable
private class EducationEditorModel(val context: NovaEducationContext, val companies: List<NovaCompanyOption>, val original: NovaTrainingSession?,
                                   private val client: NovaTrainingClient, private val coroutines: CoroutineScope) {
    var draft by mutableStateOf(NovaEducationDraft())
    var template by mutableStateOf(NovaEducationScope(companyId = "", workplaceId = ""))
    var days by mutableStateOf<List<NovaEducationDay>>(emptyList())
    var saved by mutableStateOf(original)
    var certificates by mutableStateOf(context.certificates)
    var error by mutableStateOf<String?>(null)
    var notice by mutableStateOf<String?>(null)
    var expanded by mutableStateOf<String?>(null)
    var ready by mutableStateOf(false)
    var restored by mutableStateOf(false)
    val people = mutableStateMapOf<String, List<NovaPersonOption>>()
    private val requested = mutableSetOf<String>()

    val basic get() = template.cycle in basicCycles
    val changed: Boolean get() {
        val row = saved; val education = row?.education ?: return true
        return draft.title != row.title || draft.notes != row.notes || draft.providerName != education.providerName ||
            draft.trainers != education.trainers || draft.scopes != education.scopes
    }

    fun scope(company: String) = draft.scopes.firstOrNull { it.companyId.sameId(company) }

    /**
     * Whether a step lets the expert move on. Companies are added in the participants step, so before any
     * exist the schedule counts as done once the shared curriculum has lessons; otherwise a record opened
     * without a company could never get past the schedule.
     */
    fun complete(step: NovaEducationStep) = draft.isComplete(step) ||
        (step == NovaEducationStep.schedule && draft.scopes.isEmpty() && template.lessons.isNotEmpty())

    /** Edits to the shared curriculum land on every scope once the editor is ready; loading never rewrites a saved record. */
    fun applyTemplate(value: NovaEducationScope) {
        template = value
        if (ready) draft = draft.copy(scopes = draft.scopes.map {
            it.copy(cycle = value.cycle, topics = value.topics, contextNote = value.contextNote, lessons = value.lessons, draftDays = value.draftDays,
                location = value.location)
        })
    }

    /** Trainers do not vary per topic: every topic is credited to whoever is listed. */
    fun setTrainers(value: List<NovaEducationTrainer>) {
        draft = draft.copy(trainers = value)
        val ids = value.map { it.id }
        applyTemplate(template.copy(topics = template.topics.map { it.copy(trainerIds = ids) }))
    }

    fun applyDays(value: List<NovaEducationDay>) { days = value; recompute() }

    private val units get() = if (basic) maxOf(1, ceil(template.net / 45.0).toInt()) else 1

    /** More than eight lesson units (about eight hours) cannot fit in one working day. */
    val neededDays get() = if (template.net <= 0) 1 else maxOf(1, (units + 7) / 8)

    /** Splits the topic minutes evenly across the listed days and lets the clock place the 45 + 15 blocks. */
    fun recompute() {
        if (template.net <= 0) { applyTemplate(template.copy(lessons = emptyList())); return }
        var list = days.ifEmpty { listOf(NovaEducationDay.of(Instant.now(), 1)) }
        while (list.size < neededDays) list = list + NovaEducationDay.of(list.last().instant.plus(1, ChronoUnit.DAYS), 1)
        days = list
        val count = units
        val shares = list.mapIndexed { index, day -> day.copy(lessonCount = maxOf(1, count / list.size + if (index < count % list.size) 1 else 0)) }
        applyTemplate(template.copy(lessons = NovaEducationClock.distribute(template.topics, shares, basic), draftDays = list))
    }

    fun refreshDefaults() {
        val hazard = template.hazardClass ?: "low"
        val curriculum = draft.scopes.firstOrNull()?.let { context.curriculum(it, template.cycle, hazard) }
        applyTemplate(template.copy(topics = curriculum?.education?.topics ?: context.`package`.topics(template.cycle, hazard),
            contextNote = curriculum?.education?.contextNote ?: ""))
        recompute()
    }

    /** Once the record has a hazard class, only same-class workplaces are offered. */
    fun eligible(company: String) = context.workplaces.filter {
        it.companyId.sameId(company) && (draft.scopes.isEmpty() || it.hazardClass == template.hazardClass)
    }

    fun loadPeople(company: String) {
        val key = company.lowercase()
        if (!requested.add(key)) return
        coroutines.launch {
            try { people[key] = client.employees(company) } catch (failure: Exception) { requested.remove(key); error = NovaTrainingWords.message(failure) }
        }
    }

    /**
     * One training carries one hazard class. The first real workplace replaces the preview class and refreshes
     * official topics; a legacy migration ([seed] false) replays history and never loses a company over this.
     */
    fun add(company: String, workplace: String, seed: Boolean = true) {
        val place = context.workplaces.firstOrNull { it.id.sameId(workplace) } ?: return
        if (seed && draft.scopes.isNotEmpty() && template.hazardClass != place.hazardClass) {
            error = "Bu eğitimin diğer kapsamları ${NovaTrainingWords.hazard(template.hazardClass)} sınıfında; ${NovaTrainingWords.hazard(place.hazardClass)} " +
                "sınıfındaki bir işyeri aynı eğitime eklenemez — tek eğitimde tek tehlike sınıfı olur. Ayrı bir eğitim kaydı açın."
            return
        }
        if (seed && draft.scopes.isEmpty() && template.hazardClass != place.hazardClass) {
            val topics = if (template.cycle != "custom") context.`package`.topics(template.cycle, place.hazardClass) else template.topics
            val ids = draft.trainers.map { it.id }
            applyTemplate(template.copy(hazardClass = place.hazardClass, topics = topics.map { it.copy(trainerIds = ids) }))
            recompute()
        }
        var scope = NovaEducationScope(companyId = company, workplaceId = place.id, companyName = companies.firstOrNull { it.id.sameId(company) }?.name,
            workplaceName = place.name, hazardClass = place.hazardClass)
        // The signer lives on the company record; the workplace name and a plain placeholder stand in until a printout needs more.
        if (seed) scope = scope.copy(cycle = template.cycle, topics = template.topics, contextNote = template.contextNote, lessons = template.lessons,
            draftDays = template.draftDays, location = template.location, legalName = place.name, employerName = "İşveren vekili")
        draft = draft.copy(scopes = draft.scopes + scope)
        loadPeople(company)
        if (seed) expanded = company
    }

    /** Assigns a workplace to a company already in the record, or adds the company. */
    fun pick(company: String, workplace: String) {
        val place = context.workplaces.firstOrNull { it.id.sameId(workplace) } ?: return
        val index = draft.scopes.indexOfFirst { it.companyId.sameId(company) }
        if (index < 0) { add(company, workplace); return }
        draft = draft.copy(scopes = draft.scopes.toMutableList().also {
            it[index] = it[index].copy(workplaceId = place.id, workplaceName = place.name, hazardClass = place.hazardClass, legalName = place.name)
        })
    }

    fun addCompany(company: String) {
        expanded = company
        loadPeople(company)
        eligible(company).firstOrNull()?.let { pick(company, it.id) }
    }

    fun removeCompany(company: String) {
        draft = draft.copy(scopes = draft.scopes.filterNot { it.companyId.sameId(company) })
        if (expanded?.sameId(company) == true) expanded = null
    }

    fun toggle(company: String, person: NovaPersonOption) {
        val index = draft.scopes.indexOfFirst { it.companyId.sameId(company) }.takeIf { it >= 0 } ?: return
        val scope = draft.scopes[index]
        val participants = if (scope.participants.any { it.id.sameId(person.id) }) scope.participants.filterNot { it.id.sameId(person.id) }
            else scope.participants + NovaEducationPerson(person.id, person.name)
        draft = draft.copy(scopes = draft.scopes.toMutableList().also { it[index] = scope.copy(participants = participants) })
    }

    /** A brand-new record starts with no trainers: "Kendimi ekle" keeps the choice one tap away but deliberate. */
    fun seedFresh(initialCompany: String?) {
        val row = original
        val education = row?.education
        when {
            row != null && education != null -> draft = NovaEducationDraft.of(row, education)
            row != null -> {
                draft = draft.copy(trainers = listOf(NovaEducationTrainer(name = row.trainer)), id = row.id, expectedVersion = row.version,
                    title = row.title, notes = row.notes)
                notice = "Eski kayıt için konuları ve gerçekleşen saatleri uzman bilgisiyle tamamlayın. Katalog geçmiş kaydı kendiliğinden değiştirmez."
                row.companies.forEach { company ->
                    val place = context.workplaces.firstOrNull { it.companyId.sameId(company.companyId) } ?: return@forEach
                    add(company.companyId, place.id, seed = false)
                    val last = draft.scopes.last()
                    draft = draft.copy(scopes = draft.scopes.dropLast(1) + last.copy(participants = company.participants.map { NovaEducationPerson(it.id, it.name) }))
                }
            }
            else -> {
                draft = draft.copy(title = template.cycleName)
                initialCompany?.let { company -> context.workplaces.firstOrNull { it.companyId.sameId(company) }?.let { add(company, it.id) } }
            }
        }
    }

    /** Mirrors the record's own curriculum, or gives a new one an editable preview straight away. */
    fun syncTemplate() {
        val first = draft.scopes.firstOrNull()
        template = when {
            first != null -> template.copy(cycle = first.cycle, topics = first.topics, contextNote = first.contextNote, lessons = first.lessons,
                draftDays = first.draftDays, location = first.location, hazardClass = first.hazardClass)
            template.topics.isEmpty() -> template.copy(hazardClass = "low", topics = context.`package`.topics(template.cycle, "low"))
            else -> template
        }
        days = template.draftDays ?: NovaEducationClock.days(template.lessons)
        if (days.isEmpty()) days = listOf(NovaEducationDay.of(Instant.now(), 1))
        recompute()
    }

    fun initialize(initialCompany: String?) {
        try {
            val pendingDraft = client.pending()
            val preserved = client.draft(original?.id)
            when {
                pendingDraft != null -> draft = preserved ?: pendingDraft
                preserved != null -> {
                    draft = preserved; restored = true
                    notice = if (original != null && preserved.expectedVersion != original.version)
                        "Korunan taslak eski bir sürüme ait. Güncel kaydı değiştirmeden önce içeriğini karşılaştırın."
                    else "Önceki taslağınız geri yüklendi. Baştan başlamak isterseniz aşağıdan taslağı temizleyebilirsiniz."
                }
                else -> seedFresh(initialCompany)
            }
            syncTemplate()
            ready = true
            draft.scopes.map { it.companyId }.distinctBy { it.lowercase() }.forEach(::loadPeople)
        } catch (failure: Exception) { error = NovaTrainingWords.message(failure) }
    }

    fun discard(initialCompany: String?) {
        runCatching { client.discardDraft(original?.id) }
        ready = false
        draft = NovaEducationDraft(); template = NovaEducationScope(companyId = "", workplaceId = "")
        restored = false; notice = null
        seedFresh(initialCompany); syncTemplate()
        ready = true
        draft.scopes.map { it.companyId }.distinctBy { it.lowercase() }.forEach(::loadPeople)
    }

    /** Re-reads the record after a certificate closes, so issued numbers and revisions show up. */
    suspend fun refresh() {
        val row = saved ?: return
        try {
            val latest = client.context(row.id)
            certificates = latest.certificates
            val fresh = latest.row
            val education = fresh?.education ?: return
            ready = false
            saved = fresh; draft = NovaEducationDraft.of(fresh, education)
            syncTemplate()
            ready = true
        } catch (failure: Exception) { error = NovaTrainingWords.message(failure) }
    }
}

private class CertificateTarget(val scope: String, val person: String, val document: String?, val revision: Int?)

/** The guided five-step form (iOS `NovaEducationEditor`); only the current step is on screen. */
@Composable
private fun NovaEducationEditor(client: NovaTrainingClient, companies: List<NovaCompanyOption>, initialCompany: String?, original: NovaTrainingSession?,
                                context: NovaEducationContext, canWrite: Boolean, onClose: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val model = remember { EducationEditorModel(context, companies, original, client, coroutines) }
    var step by remember { mutableStateOf(NovaEducationStep.info) }
    var busy by remember { mutableStateOf(false) }
    var pending by remember { mutableStateOf(false) }
    var topicsOpen by remember { mutableStateOf(false) }
    var cycleBefore by remember { mutableStateOf<String?>(null) }
    var certificate by remember { mutableStateOf<CertificateTarget?>(null) }
    LaunchedEffect(Unit) {
        pending = runCatching { client.pending() != null }.getOrDefault(false)
        model.initialize(initialCompany)
    }
    // Autosave: only an edit worth keeping, debounced so typing does not write on every key.
    LaunchedEffect(model.draft) {
        if (!model.ready || !model.changed) return@LaunchedEffect
        delay(300)
        runCatching { client.preserve(model.draft) }.onFailure { model.error = NovaTrainingWords.message(it) }
    }
    suspend fun save() {
        busy = true; model.error = null
        try {
            val row = client.save(model.draft).row
            val education = row?.education ?: throw NovaTrainingException("UNAVAILABLE")
            model.saved = row
            model.draft = model.draft.copy(id = row.id, expectedVersion = row.version, scopes = education.scopes, trainers = education.trainers)
            model.notice = "Gerçekleşen eğitim kaydedildi. Kişisel belgeleri aşağıdan hazırlayabilirsiniz."
        } catch (failure: Exception) {
            model.error = NovaTrainingWords.message(failure); pending = runCatching { client.pending() != null }.getOrDefault(false)
        }
        busy = false
    }
    suspend fun retry() {
        try {
            val waiting = client.pending() ?: return
            if (waiting.action == "curriculum") {
                busy = true
                try { client.save(waiting); pending = false; model.notice = "Firma müfredatı kaydedildi." } finally { busy = false }
            } else { model.draft = waiting; pending = false; save() }
        } catch (failure: Exception) { model.error = NovaTrainingWords.message(failure) }
    }
    suspend fun saveCurriculum(scope: NovaEducationScope) {
        busy = true
        try {
            client.save(model.draft.copy(action = "curriculum", id = null, expectedVersion = 0, scopes = listOf(scope)))
            model.notice = "Yalnız bu firma, işyeri ve görev kapsamının müfredatı kaydedildi."
        } catch (failure: Exception) {
            model.error = NovaTrainingWords.message(failure); pending = runCatching { client.pending() != null }.getOrDefault(false)
        }
        busy = false
    }
    val selected = certificate
    val row = model.saved
    if (selected != null && row != null) {
        NovaEducationCertificateScreen(client, row, selected.scope, selected.person, context.certificateEnabled && canWrite, selected.document, selected.revision) {
            certificate = null
            coroutines.launch { model.refresh() }
        }
        return
    }
    BackHandler(enabled = !busy, onBack = onClose)
    val draft = model.draft
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPageHeading(if (original == null) "Eğitim Ekle" else "Eğitim Ayrıntısı", "Gerçekleşen eğitim · kişi bazlı belge", backEnabled = !busy, onBack = onClose)
        if (!model.ready) {
            model.error?.let { NovaText(it, color = NovaColorToken.statusDangerInk.color()) }
                ?: Box(Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) { NovaSpinner(NovaColorToken.text.color(), size = 24.dp) }
            return@Column
        }
        EducationProgress(draft)
        NovaCard(Modifier.fillMaxWidth().testTag("education.current-step.${step.name}"), padding = 16) {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon(step.symbol, 17.dp, Modifier.width(24.dp))
                    NovaText(step.title, Modifier.weight(1f), NovaTypeToken.cardTitle)
                    NovaStatusPill("${step.ordinal + 1}/${NovaEducationStep.entries.size}", if (model.complete(step)) NovaStatus.Success else NovaStatus.Warning)
                }
                NovaDivider()
                when (step) {
                    NovaEducationStep.info -> InfoStep(model, canWrite, onCycle = { old -> cycleBefore = old }, onTopics = { topicsOpen = true })
                    NovaEducationStep.schedule -> ScheduleStep(model, canWrite)
                    NovaEducationStep.trainers -> TrainersStep(model, client.userName, canWrite)
                    NovaEducationStep.participants -> ParticipantsStep(model, canWrite)
                    NovaEducationStep.review -> ReviewStep(model)
                }
            }
        }
        model.error?.let { NovaCard(Modifier.fillMaxWidth(), padding = 14) { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) } }
        model.notice?.let { text ->
            NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    NovaText(text, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color())
                    // Only a plain autosave is safe to drop; a pending save may already be on the server and keeps its own retry.
                    if (model.restored && !pending) NovaButton("Taslağı temizle, baştan başla", { model.discard(initialCompany) },
                        Modifier.testTag("education.draft.discard"), variant = NovaButtonVariant.Surface, symbol = "arrow.counterclockwise")
                }
            }
        }
        if (pending) NovaButton("Bekleyen kaydı aynı işlemle tamamla", { coroutines.launch { retry() } }, variant = NovaButtonVariant.Surface,
            enabled = !busy, symbol = "arrow.clockwise")
        if (step == NovaEducationStep.review) {
            NovaButton("Gerçekleşen eğitimi kaydet", { coroutines.launch { save() } }, Modifier.fillMaxWidth().testTag("education.save"),
                enabled = canWrite && !busy && !pending && draft.scopes.isNotEmpty(), loading = busy, symbol = "checkmark")
            // The draft already autosaves; this makes that explicit so the expert can leave knowing it.
            NovaButton("Taslak olarak kaydet", { runCatching { client.preserve(model.draft) }; onClose() }, Modifier.fillMaxWidth().testTag("education.savedraft"),
                variant = NovaButtonVariant.Surface, enabled = canWrite && !busy, symbol = "tray.and.arrow.down")
        } else Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (step.ordinal > 0) NovaButton("Geri", { step = NovaEducationStep.entries[step.ordinal - 1] }, Modifier.weight(1f),
                variant = NovaButtonVariant.Surface, symbol = "chevron.left")
            else Spacer(Modifier.weight(1f))
            NovaButton("Devam", { step = NovaEducationStep.entries[step.ordinal + 1] }, Modifier.weight(1f).testTag("education.next.${step.name}"),
                enabled = model.complete(step), symbol = "chevron.right")
        }
        Certificates(model, canWrite) { certificate = it }
    }
    NovaPopup(topicsOpen, { topicsOpen = false; model.recompute() }, identifier = "education.topics") {
        EducationTopics(model, saveCurriculum = model.draft.scopes.firstOrNull()?.let { first -> { coroutines.launch { saveCurriculum(first) } } })
    }
    NovaPopup(cycleBefore != null, { cycleBefore = null }, identifier = "education.cycle.changed") {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaPopupHeading("Eğitim türü değişti", symbol = "arrow.triangle.2.circlepath",
                subtitle = "Mevcut dakikaları değiştirmek isteğe bağlıdır; saatleri değişiklikten sonra yeniden dağıtın.")
            NovaPopupOption("Yeni türün varsayılan konularını getir", "arrow.down.doc") { model.refreshDefaults(); cycleBefore = null }
            NovaPopupOption("Mevcut konuları koru", "checkmark") { cycleBefore = null }
            NovaPopupOption("Vazgeç", "xmark") {
                cycleBefore?.let { old -> model.applyTemplate(model.template.copy(cycle = old)); model.draft = model.draft.copy(title = NovaEducationScope.cycleName(old)) }
                cycleBefore = null
            }
        }
    }
}

@Composable
private fun EducationProgress(draft: NovaEducationDraft) {
    NovaCard(Modifier.fillMaxWidth().testTag("education.progress"), padding = 12) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                NovaText("${draft.completedCount}/${NovaEducationStep.entries.size} başlık tamamlandı", Modifier.weight(1f), NovaTypeToken.label)
                if (draft.scopes.isNotEmpty()) NovaStatusPill("Kaydedilebilir", NovaStatus.Success) else NovaStatusPill("Kapsam eksik", NovaStatus.Warning)
            }
            Box(Modifier.fillMaxWidth().height(6.dp).background(NovaColorToken.borderMuted.color(), CircleShape)) {
                Box(Modifier.fillMaxWidth(draft.progress).fillMaxHeight().background(NovaColorToken.accent.color(), CircleShape))
            }
        }
    }
}

@Composable
private fun InfoStep(model: EducationEditorModel, canWrite: Boolean, onCycle: (String) -> Unit, onTopics: () -> Unit) {
    val template = model.template
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        // The record's title is its cycle's own name: the cycle is the one choice that drives topics, minutes and rules.
        NovaFilterField("Eğitim:", NovaEducationScope.cycles.map { NovaChooserOption(it.first, it.second) }, template.cycle, "education.cycle") { picked ->
            if (!canWrite || picked == null || picked == template.cycle) return@NovaFilterField
            val old = template.cycle
            model.applyTemplate(template.copy(cycle = picked))
            model.draft = model.draft.copy(title = NovaEducationScope.cycleName(picked))
            onCycle(old)
        }
        NovaText("Eğitim yöntemi", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
        val online = template.topics.firstOrNull()?.method == "online"
        NovaSegmentedControl(listOf("Yüz yüze", "Online"), if (online) 1 else 0, Modifier.testTag("education.method")) { index ->
            if (canWrite) model.applyTemplate(template.copy(topics = template.topics.map { it.copy(method = if (index == 1) "online" else "face_to_face") }))
        }
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(12.dp))
            .novaRowPress(onClick = onTopics).testTag("education.topics.link").padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon("list.bullet.clipboard", 13.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                NovaText("Konuları ve Süre", style = NovaTypeToken.bodyStrong)
                // Breaks included: a training that needs eight hours must not read as six.
                NovaText("${template.cycleName} · ${duration(template.net + template.breakTotal)}", style = NovaTypeToken.meta,
                    color = NovaColorToken.textSecondary.color())
            }
            NovaIcon("chevron.right", 12.dp)
        }
        NovaTextField("Düzenleyici kişi / kurum", model.draft.providerName, { model.draft = model.draft.copy(providerName = it) },
            identifier = "education.provider", enabled = canWrite)
        NovaTextField("Notlar", model.draft.notes, { model.draft = model.draft.copy(notes = it) }, identifier = "education.notes", multiline = true, enabled = canWrite)
    }
}

/** The start–end of one day, from the lessons already placed on it. */
private fun dayRange(model: EducationEditorModel, day: NovaEducationDay): String? {
    val key = NovaEducationClock.day(day.instant)
    val lessons = model.template.lessons.filter { lesson -> NovaEducationClock.date(lesson.startsAt)?.let(NovaEducationClock::day) == key }.sortedBy { it.startsAt }
    val start = lessons.firstOrNull()?.let { NovaEducationClock.date(it.startsAt) } ?: return null
    val last = lessons.last()
    val end = NovaEducationClock.date(last.startsAt)?.plusSeconds(last.instructionMinutes * 60L) ?: return null
    val format = DateTimeFormatter.ofPattern("HH:mm").withZone(NovaEducationClock.zone)
    return "${format.format(start)} – ${format.format(end)}"
}

/** A date and start time per day; lesson blocks, breaks and the end time are computed from the topic minutes. */
@Composable
private fun ScheduleStep(model: EducationEditorModel, canWrite: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        NovaTextField("Eğitim yeri / online bağlantı açıklaması", model.template.location, { model.applyTemplate(model.template.copy(location = it)) },
            identifier = "education.location", enabled = canWrite)
        model.days.forEachIndexed { index, day ->
            val local = day.instant.atZone(NovaEducationClock.zone)
            fun update(value: Instant) { if (canWrite) model.applyDays(model.days.map { if (it.id == day.id) it.at(value) else it }) }
            NovaCard(Modifier.fillMaxWidth(), padding = 10) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        NovaText("${index + 1}. gün", Modifier.weight(1f), NovaTypeToken.label)
                        dayRange(model, day)?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color()) }
                        if (canWrite && model.days.size > model.neededDays) Box(Modifier.size(36.dp).clip(CircleShape)
                            .novaRowPress { model.applyDays(model.days.filterNot { it.id == day.id }) }
                            .semantics { contentDescription = "Günü kaldır" }, contentAlignment = Alignment.Center) {
                            NovaIcon("xmark.circle.fill", 16.dp, tint = NovaColorToken.textTertiary.color())
                        }
                    }
                    NovaDayField("Tarih", local.toLocalDate().toString(), { picked ->
                        NovaDay.parse(picked)?.takeIf { !it.isAfter(java.time.LocalDate.now(NovaEducationClock.zone)) }?.let {
                            update(it.atTime(local.toLocalTime()).atZone(NovaEducationClock.zone).toInstant())
                        }
                    }, "education.day.$index.date")
                    NovaTimeField("Başlangıç", local.toLocalTime().withSecond(0).withNano(0), "education.day.$index.time") { time: LocalTime ->
                        update(local.toLocalDate().atTime(time).atZone(NovaEducationClock.zone).toInstant())
                    }
                }
            }
        }
        if (canWrite) NovaButton("Gün ekle", {
            val last = model.days.lastOrNull()?.instant ?: Instant.now()
            model.applyDays(model.days + NovaEducationDay.of(last.plus(1, ChronoUnit.DAYS), 1))
        }, variant = NovaButtonVariant.Surface, symbol = "calendar.badge.plus", compact = true)
        NovaText("Toplam: ${duration(model.template.net + model.template.breakTotal)} (mola dahil)", style = NovaTypeToken.meta,
            color = NovaColorToken.textSecondary.color())
    }
}

@Composable
private fun TrainersStep(model: EducationEditorModel, userName: String, canWrite: Boolean) {
    val trainers = model.draft.trainers
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        trainers.forEachIndexed { index, trainer ->
            fun update(value: NovaEducationTrainer) = model.setTrainers(trainers.toMutableList().also { it[index] = value })
            NovaCard(Modifier.fillMaxWidth(), padding = 10) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    NovaTextField("Eğitici adı soyadı", trainer.name, { update(trainer.copy(name = it)) }, identifier = "education.trainer.name.$index", enabled = canWrite)
                    NovaTextField("Unvan / belge bilgisi", trainer.title, { update(trainer.copy(title = it)) }, identifier = "education.trainer.title.$index",
                        enabled = canWrite)
                    if (canWrite && trainers.size > 1) NovaButton("Eğiticiyi kaldır", { model.setTrainers(trainers.filterNot { it.id == trainer.id }) },
                        variant = NovaButtonVariant.Danger, compact = true)
                }
            }
        }
        if (canWrite) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaButton("Eğitici ekle", { model.setTrainers(trainers + NovaEducationTrainer()) }, variant = NovaButtonVariant.Surface, symbol = "plus", compact = true)
            if (userName.isNotBlank() && trainers.none { it.name == userName }) NovaButton("Kendimi ekle", {
                model.setTrainers(trainers + NovaEducationTrainer(name = userName))
            }, variant = NovaButtonVariant.Surface, symbol = "person.fill.checkmark", compact = true)
        }
    }
}

/**
 * Company → workplace → people. An account can hold a hundred companies, so search adds a company
 * and only added companies stay listed.
 */
@Composable
private fun ParticipantsStep(model: EducationEditorModel, canWrite: Boolean) {
    var companySearch by remember { mutableStateOf("") }
    val added = model.companies.filter { model.scope(it.id) != null }
    val matches = if (companySearch.isBlank()) emptyList() else model.companies.filter { model.scope(it.id) == null && it.name.contains(companySearch.trim(), true) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        NovaText("Firma arayıp ekleyin; her firmanın altında personelini arayıp tikleyerek katılımcı olarak ekleyebilirsiniz. " +
            "Aynı eğitime yalnız aynı tehlike sınıfındaki firmaları ekleyebilirsiniz.", style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color())
        if (canWrite) NovaSearchCapsule(companySearch, "Firma ara ve ekle", "education.participants.companysearch") { companySearch = it }
        if (companySearch.isNotBlank()) {
            if (matches.isEmpty()) NovaText("Eşleşen firma yok.", style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color())
            matches.forEach { company ->
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(10.dp))
                    .novaRowPress { companySearch = ""; model.addCompany(company.id) }.testTag("education.participants.add.${company.id}").padding(10.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    NovaText(company.name, Modifier.weight(1f))
                    NovaIcon("plus.circle", 16.dp)
                }
            }
        }
        added.forEach { company -> CompanySection(model, company, canWrite) }
    }
}

@Composable
private fun CompanySection(model: EducationEditorModel, company: NovaCompanyOption, canWrite: Boolean) {
    val open = model.expanded?.sameId(company.id) == true
    val scope = model.scope(company.id)
    var personSearch by remember(open) { mutableStateOf("") }
    var choosing by remember { mutableStateOf(false) }
    NovaCard(Modifier.fillMaxWidth(), padding = 12) {
        Column(verticalArrangement = Arrangement.spacedBy(if (open) 10.dp else 0.dp)) {
            Row(Modifier.fillMaxWidth().novaRowPress {
                model.expanded = if (open) null else company.id
                if (!open) model.loadPeople(company.id)
            }.testTag("education.company.${company.id}"), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(company.name, style = NovaTypeToken.cardTitle)
                    NovaText("${scope?.participants?.size ?: 0} katılımcı", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                }
                NovaIcon(if (open) "chevron.up" else "chevron.down", 12.dp)
            }
            if (!open) return@Column
            val places = model.eligible(company.id)
            if (places.isEmpty()) {
                NovaText("Bu firmada bu eğitimin tehlike sınıfına uygun işyeri yok.", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                return@Column
            }
            if (places.size > 1 || scope == null) {
                NovaChooserButton("İşyeri", scope?.workplaceName ?: places.first().name, "education.company.${company.id}.workplace", open = choosing) {
                    if (canWrite) choosing = !choosing
                }
                if (choosing) NovaChooserPanel(places.map { NovaChooserOption(it.id, it.name) }, scope?.workplaceId, "education.company.${company.id}.workplace.panel") {
                    picked -> picked?.let { model.pick(company.id, it) }; choosing = false
                }
            }
            if (scope == null) {
                // One eligible workplace is picked automatically: a choice with one answer is not a choice.
                if (places.size == 1) LaunchedEffect(company.id) { model.pick(company.id, places[0].id) }
                else NovaText("İşyeri seçince personel listesi burada görünür.", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                return@Column
            }
            NovaSearchCapsule(personSearch, "Personel ara", "education.company.${company.id}.people") { personSearch = it }
            val list = model.people[company.id.lowercase()].orEmpty()
            if (list.isEmpty()) NovaText("Bu firmada aktif personel yok.", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            list.filter { personSearch.isBlank() || it.name.contains(personSearch.trim(), true) }.forEach { person ->
                val on = scope.participants.any { it.id.sameId(person.id) }
                Row(Modifier.fillMaxWidth().heightIn(min = 40.dp).novaRowPress(enabled = canWrite) { model.toggle(company.id, person) }
                    .testTag("education.person.${person.id}").semantics { role = Role.Checkbox; selected = on },
                    horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon(if (on) "checkmark.square.fill" else "square", 16.dp, tint = if (on) NovaColorToken.accentInk.color() else NovaColorToken.textMuted.color())
                    NovaText(person.name)
                }
            }
            if (canWrite) NovaButton("Firmayı kaldır", { model.removeCompany(company.id) }, variant = NovaButtonVariant.Danger, compact = true)
        }
    }
}

/** The explicit last checkpoint: what will be written, with the save action in the same place for new and edited records. */
@Composable
private fun ReviewStep(model: EducationEditorModel) {
    val draft = model.draft
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        NovaText("Kaydetmeden önce kontrol edin", style = NovaTypeToken.sectionTitle)
        NovaCard(Modifier.fillMaxWidth(), padding = 12) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(
                    "Eğitim" to draft.title.ifEmpty { model.template.cycleName },
                    "Toplam süre" to duration(model.template.net + model.template.breakTotal),
                    "Gün sayısı" to "${model.days.size} gün",
                    "Eğiticiler" to "${draft.trainers.count { it.name.isNotBlank() }} kişi",
                    "Katılımcılar" to "${draft.scopes.sumOf { it.participants.size }} kişi",
                    "Firma / işyeri" to draft.scopes.joinToString(", ") { listOfNotNull(it.companyName, it.workplaceName).joinToString(" · ") },
                ).forEach { (label, value) ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        NovaText(label, style = NovaTypeToken.metaQuiet)
                        Spacer(Modifier.weight(1f))
                        NovaText(value.ifEmpty { "Belirtilmedi" }, style = NovaTypeToken.bodyStrong, textAlign = androidx.compose.ui.text.style.TextAlign.End)
                    }
                }
            }
        }
        NovaText("Bu özet onaylandığında eğitim kaydı ve kişi bazlı katılım bilgisi oluşturulur.", style = NovaTypeToken.metaQuiet)
    }
}

/** Personal certificates, offered only for a record whose on-screen state is exactly what the server holds. */
@Composable
private fun Certificates(model: EducationEditorModel, canWrite: Boolean, open: (CertificateTarget) -> Unit) {
    val row = model.saved ?: return
    if (model.changed) {
        NovaText("Sertifika için değişiklikleri kaydedin.", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        return
    }
    NovaCard(Modifier.fillMaxWidth(), padding = 12) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaText("Kişisel belgeler", style = NovaTypeToken.cardTitle)
            row.education?.scopes.orEmpty().forEach { scope ->
                scope.participants.forEach { person ->
                    val versions = model.certificates.filter { it.scopeId.sameId(scope.id) && it.personId.sameId(person.id) }
                    val known = versions.firstOrNull { it.sourceSessionRevision == row.version }
                    val action = when {
                        known != null -> "Sertifikayı aç"
                        !scope.issues.isNullOrEmpty() || person.jobTitle.isEmpty() -> "Belge bilgileri eksik"
                        else -> "Sertifika hazırla"
                    }
                    Row(Modifier.fillMaxWidth().novaRowPress(enabled = canWrite || known != null) {
                        open(CertificateTarget(scope.id, person.id, known?.documentId, known?.revision))
                    }.testTag("education.certificate.${person.id}").padding(vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            NovaText(person.name ?: "Personel")
                            NovaText(scope.companyName.orEmpty(), style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                        }
                        NovaText(action, style = NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
                    }
                    if (versions.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        versions.forEach { version ->
                            NovaChoiceChip("Revizyon ${version.revision}", false) {
                                open(CertificateTarget(scope.id, person.id, version.documentId, version.revision))
                            }
                        }
                    }
                }
            }
        }
    }
}

/** Topics and minutes (iOS `NovaEducationTopicsPopup`). */
@Composable
private fun EducationTopics(model: EducationEditorModel, saveCurriculum: (() -> Unit)?) {
    val template = model.template
    val basic = template.cycle in basicCycles
    val hazardLocked = model.draft.scopes.isNotEmpty()
    var openGroups by remember { mutableStateOf(setOf<String>()) }
    fun defaults(hazard: String? = template.hazardClass) {
        val value = model.template.copy(hazardClass = hazard)
        val curriculum = model.draft.scopes.firstOrNull()?.let { model.context.curriculum(it, value.cycle, value.hazardClass, value.groupName) }
        model.applyTemplate(value.copy(topics = curriculum?.education?.topics ?: model.context.`package`.topics(value.cycle, value.hazardClass ?: "low"),
            contextNote = curriculum?.education?.contextNote ?: ""))
    }
    fun defaultMinutes(topic: NovaEducationTopic) =
        model.context.`package`.topics(template.cycle, template.hazardClass ?: "low").firstOrNull { it.code == topic.code }?.instructionMinutes ?: 30
    fun update(topic: NovaEducationTopic, value: NovaEducationTopic) =
        model.applyTemplate(model.template.copy(topics = model.template.topics.map { if (it.code == topic.code) value else it }))
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaPopupHeading("Konuları ve Süre", symbol = "list.bullet.clipboard")
        if (hazardLocked) NovaText("Tehlike sınıfı: ${NovaTrainingWords.hazard(template.hazardClass)} (eklenen işyerinden)", style = NovaTypeToken.meta,
            color = NovaColorToken.textSecondary.color())
        else Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            NovaText("Tehlike sınıfı (önizleme)", style = NovaTypeToken.bodyStrong)
            val hazards = listOf("low", "medium", "high")
            NovaSegmentedControl(hazards.map(NovaTrainingWords::hazard), hazards.indexOf(template.hazardClass ?: "low").coerceAtLeast(0)) { defaults(hazards[it]) }
            NovaText("Firma eklendiğinde gerçek tehlike sınıfına göre otomatik güncellenir.", style = NovaTypeToken.micro, color = NovaColorToken.textSecondary.color())
        }
        NovaText("Profil: ${model.context.`package`.preset(template.cycle, template.hazardClass.orEmpty())?.label ?: template.cycleName}", style = NovaTypeToken.meta)
        NovaText("Eğitim konuları ve dakikalar", style = NovaTypeToken.bodyStrong)
        val names = mapOf("G1" to "Genel", "G2" to "Sağlık", "G3" to "Teknik", "G4" to "İşyerine Özgü Riskler")
        names.forEach { (group, name) ->
            val topics = template.topics.filter { it.group == group }
            val open = group in openGroups
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(10.dp)).padding(10.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(Modifier.fillMaxWidth().novaRowPress { openGroups = if (open) openGroups - group else openGroups + group }.testTag("education.topics.$group"),
                    verticalAlignment = Alignment.CenterVertically) {
                    NovaText("$group · $name · ${topics.sumOf { it.instructionMinutes }} dk", Modifier.weight(1f), NovaTypeToken.bodyStrong)
                    NovaIcon(if (open) "chevron.up" else "chevron.down", 12.dp)
                }
                if (open) topics.forEach { topic ->
                    TopicRow(topic, removable = topic.group == "G4" || !basic || topic.parentCode != null, defaultMinutes = defaultMinutes(topic),
                        onChange = { update(topic, it) }, onRemove = { model.applyTemplate(model.template.copy(topics = model.template.topics.filterNot { it.code == topic.code })) })
                }
            }
        }
        NovaButton("İşyerine özgü konu ekle", {
            model.applyTemplate(template.copy(topics = template.topics + NovaEducationTopic("G4-" + java.util.UUID.randomUUID().toString().uppercase(), "G4", "", 0)))
            openGroups = openGroups + "G4"
        }, variant = NovaButtonVariant.Surface, symbol = "plus", compact = true)
        NovaTextField("İşyeri, görev ve risk dayanağı açıklaması", template.contextNote, { model.applyTemplate(model.template.copy(contextNote = it)) },
            identifier = "education.topics.context", multiline = true)
        NovaWhyDisclosure {
            NovaText(if (basic && template.cycle == "initial") "Dakikalar Bakanlık rehberindeki örnek dağılımdan gelir; düzenlenebilir."
                else "Tekrar eğitimi dağılımı düzenlenebilir ürün önerisidir.", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaButton("Varsayılanlara dön", { defaults() }, variant = NovaButtonVariant.Surface, compact = true)
            if (saveCurriculum != null) NovaButton("Firma varsayılanı olarak kaydet", saveCurriculum, variant = NovaButtonVariant.Surface, compact = true)
        }
    }
}

@Composable
private fun TopicRow(topic: NovaEducationTopic, removable: Boolean, defaultMinutes: Int, onChange: (NovaEducationTopic) -> Unit, onRemove: () -> Unit) {
    val included = topic.instructionMinutes > 0
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(32.dp).clip(RoundedCornerShape(8.dp)).novaRowPress {
            onChange(topic.copy(instructionMinutes = if (included) 0 else if (defaultMinutes > 0) defaultMinutes else 30))
        }.semantics { contentDescription = "Bu konu bu eğitimde işlendi"; role = Role.Checkbox; selected = included }, contentAlignment = Alignment.Center) {
            NovaIcon(if (included) "checkmark.square.fill" else "square", 18.dp,
                tint = if (included) NovaColorToken.accentInk.color() else NovaColorToken.textSecondary.color())
        }
        if (topic.group == "G4" || topic.parentCode != null || topic.code.startsWith("CUSTOM"))
            NovaTextField("Konu başlığı", topic.title, { onChange(topic.copy(title = it)) }, Modifier.weight(1f))
        else NovaText(topic.title, Modifier.weight(1f))
        val ink = NovaColorToken.text.color()
        Row(Modifier.clip(RoundedCornerShape(8.dp)).background(NovaColorToken.surface.color(), RoundedCornerShape(8.dp))
            .border(1.dp, NovaColorToken.borderMuted.color(), RoundedCornerShape(8.dp)).padding(horizontal = 8.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
            BasicTextField(if (topic.instructionMinutes == 0) "" else topic.instructionMinutes.toString(), { text ->
                onChange(topic.copy(instructionMinutes = text.filter(Char::isDigit).take(4).toIntOrNull() ?: 0))
            }, Modifier.width(34.dp).semantics { contentDescription = "Dakika" }, singleLine = true,
                textStyle = novaTextStyle(NovaTypeToken.body).copy(color = ink, textAlign = androidx.compose.ui.text.style.TextAlign.End),
                cursorBrush = SolidColor(ink), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
            NovaText("dk", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        }
        if (removable) Box(Modifier.size(32.dp).clip(CircleShape).novaRowPress(onClick = onRemove).semantics { contentDescription = "Kaldır" },
            contentAlignment = Alignment.Center) { NovaIcon("trash", 13.dp, tint = NovaColorToken.statusDangerInk.color()) }
    }
}
