package com.riskdetectedan.feature.nova

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
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
    var createPending by remember { mutableStateOf(false) }
    var createMessage by remember { mutableStateOf<String?>(null) }
    /** Opens a requested editor once the list has loaded, or says why it cannot. */
    fun presentRequestedCreate() {
        if (!createPending || loading) return
        failure?.let { createMessage = "Eğitim ekranı açılamadı: $it Yenile ile tekrar deneyin."; return }
        createMessage = when {
            !canWrite -> "Bu hesapta eğitim kaydı oluşturma yetkisi yok."
            writable.isEmpty() -> "Eğitim ekleyebileceğiniz firma bulunamadı. Firma erişiminizi kontrol edin."
            else -> null
        }
        createPending = false
        if (createMessage == null) editor = TrainingEditorTarget(null)
    }
    fun requestCreate() {
        createPending = true
        when {
            loading -> createMessage = "Eğitim bilgileri hazırlanıyor…"
            // A newly granted company may not be in this screen's loaded page.
            failure != null || writable.isEmpty() -> { createMessage = "Eğitim bilgileri güncelleniyor…"; revision++ }
            else -> presentRequestedCreate()
        }
    }
    var certificatesPage by remember { mutableStateOf<CertificatesPage?>(null) }
    certificatesPage?.let { page ->
        NovaEducationCertificatesPage(client, page.session, canWrite, page.celebrate, page.created) { certificatesPage = null; revision++ }
        return
    }
    fun editable(session: NovaTrainingSession) = canWrite && session.companies.all { it.companyId.lowercase() in writable }
    val open = editor
    if (open != null) {
        val allowed = open.session?.let(::editable) ?: (canWrite && writable.isNotEmpty())
        NovaEducationEntry(client, companies, writable, company, open.session, allowed, onSaved = { session ->
            // A saved training leaves the editor for its certificates, like iOS.
            editor = null; certificatesPage = CertificatesPage(session, celebrate = true, created = open.session == null)
        }) { editor = null; revision++ }
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
        } catch (error: Exception) { failure = NovaTrainingWords.message(error) }
        loading = false
        if (createOnOpen && !didOpen) { didOpen = true; createPending = true }
        presentRequestedCreate()
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
        NovaListHeading("Eğitimler", onBack, actionBelow = true) {
            if (canWrite) NovaListActionButton("Eğitim Ekle", "plus", identifier = "training.add.header") { requestCreate() }
        }
        NovaListHint("Gerçekleşen eğitimi ve katılımcılarını kaydedin. Aynı eğitimde birden fazla firmanın personelini seçebilirsiniz.")
        createMessage?.let { NovaHelpHint(it) }
        val trainingStats = listOf(
            Triple("Eğitim saati", hours(completed.sumOf { it.durationMinutes }), NovaStatus.Neutral),
            Triple("Eğitim alan", trained.size.toString(), NovaStatus.Success),
            Triple("Adam × saat", hours(completed.sumOf { scope -> scope.durationMinutes * scope.participants.count { it.attended } }), NovaStatus.Neutral),
            Triple("Eğitimi eksik", employeeTotal?.let { maxOf(0, it - trained.size).toString() } ?: "—", NovaStatus.Warning),
        )
        val statColumns = if (novaFontScaleIsAccessibility()) 2 else 4
        val statSymbols = listOf("clock", "person.2", "person.badge.clock", "person.crop.circle.badge.exclamationmark")
        trainingStats.chunked(statColumns).forEachIndexed { chunkIndex, chunk ->
            Row(Modifier.testTag("training.stats"), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                chunk.forEachIndexed { index, metric ->
                    NovaListStat(metric.first, statSymbols[chunkIndex * statColumns + index],
                        metric.second, Modifier.weight(1f), status = metric.third)
                }
                repeat(statColumns - chunk.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        NovaSearchCapsule(query, "Eğitim veya eğitmen ara…", "training.search") { query = it }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaFilterField("Firma", listOf(NovaChooserOption(null, "Tüm firmalar")) + companies.map { NovaChooserOption(it.id, it.name) }, company,
                "training.company", Modifier.weight(1f)) { company = it }
            NovaFilterField("Eğitim türü", listOf(NovaChooserOption(null, "Tüm eğitim türleri")) +
                NovaEducationScope.cycles.map { NovaChooserOption(it.first, it.second) }, cycle, "training.cycle", Modifier.weight(1f)) { cycle = it }
        }
        NovaTextField("Tarih (YYYY-AA-GG)", dateFilter, { dateFilter = it }, identifier = "training.date", keyboardType = KeyboardType.Number)
        NovaListSectionHeading("Eğitimler", "${visible.size} eğitim")
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
                    visible.forEachIndexed { index, session ->
                        TrainingCard(session, editable(session), Modifier.novaRowEntrance(index)) { editor = TrainingEditorTarget(session) }
                    }
                }
            }
        }
    }
}

@Composable
private fun TrainingCard(session: NovaTrainingSession, editable: Boolean, modifier: Modifier, onClick: () -> Unit) {
    NovaCard(modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onClick).testTag("training.row.${session.id}"), padding = 15) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("graduationcap", 15.dp)
                NovaText(session.title, Modifier.weight(1f), NovaTypeToken.cardTitle)
                // A record the expert may change says so; one they can only read opens as before.
                NovaText(if (editable) "Düzenle" else "Aç", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                NovaIcon(if (editable) "pencil" else "chevron.right", 11.dp, tint = NovaColorToken.textMuted.color())
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
                               canWrite: Boolean, onSaved: ((NovaTrainingSession) -> Unit)? = null, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    var context by remember { mutableStateOf<NovaEducationContext?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(attempt) {
        try { context = client.context(original?.id); failure = null } catch (error: Exception) { failure = NovaTrainingWords.message(error) }
    }
    val loaded = context
    when {
        loaded != null -> NovaEducationEditor(client, companies, writable, initialCompany, loaded.row ?: original, loaded, canWrite, onSaved, onClose)
        failure != null -> Column(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            NovaBackButton(onClick = onClose)
            NovaText(failure!!)
            NovaButton("Yeniden dene", { attempt++ }, variant = NovaButtonVariant.Surface, symbol = "arrow.clockwise")
        }
        else -> NovaLoadingView("Eğitim açılıyor…")
    }
}

/** One training opened from a followup row or a filed document (iOS `NovaFollowupEducation`). */
@Composable
fun NovaTrainingRecordScreen(client: NovaTrainingClient, session: String?, company: String, canWrite: Boolean, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    var loaded by remember { mutableStateOf<Triple<List<NovaCompanyOption>, Set<String>, NovaEducationContext>?>(null) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(session) {
        try {
            val id = session ?: throw NovaTrainingException("ACCESS_DENIED")
            loaded = Triple(client.companies(), client.page(null).writableCompanies, client.context(id))
        } catch (_: Exception) { failed = true }
    }
    val value = loaded
    when {
        value != null -> {
            val (companies, writable, context) = value
            NovaEducationEditor(client, companies, writable, company, context.row, context,
                canWrite && context.row?.companies?.all { it.companyId.lowercase() in writable } == true, null, onBack)
        }
        failed -> Column(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            NovaBackButton(onClick = onBack)
            NovaText("Eğitim açılamadı. Eğitimler listesinden yeniden deneyin.")
        }
        else -> NovaLoadingView("Eğitim yükleniyor…")
    }
}

private val basicCycles = setOf("initial", "periodic_repeat")

private val cycleDescriptions = mapOf(
    "initial" to "Temel İSG eğitimini ilk kez alan çalışanlar", "periodic_repeat" to "Periyodik temel İSG eğitimi",
    "onboarding" to "İşe başlamadan önce verilen eğitim", "knowledge_refresh" to "Bilgileri güncelleme eğitimi",
    "additional" to "Ek ihtiyaçlara yönelik eğitim", "workplace_specific" to "Yeni işyerinin risklerine özel eğitim",
    "custom" to "Özel içerikli eğitim",
)

private val topicGroups = listOf("G1" to "Genel", "G2" to "Sağlık", "G3" to "Teknik", "G4" to "İşyerine özgü")

/**
 * The editor's state (iOS `NovaEducationEditor`). One training is one curriculum shared by every
 * company attending it: [template] carries the curriculum, method, schedule and location and is
 * mirrored into every scope; participants are the one thing that stays per company.
 */
@Stable
private class EducationEditorModel(val context: NovaEducationContext, val companies: List<NovaCompanyOption>, val original: NovaTrainingSession?,
                                   private val client: NovaTrainingClient, private val coroutines: CoroutineScope) {
    var draft by mutableStateOf(NovaEducationDraft())
    var template by mutableStateOf(NovaEducationScope(companyId = ""))
    var days by mutableStateOf<List<NovaEducationDay>>(emptyList())
    var saved by mutableStateOf(original)
    var error by mutableStateOf<String?>(null)
    var notice by mutableStateOf<String?>(null)
    var ready by mutableStateOf(false)
    var restored by mutableStateOf(false)
    var pending by mutableStateOf(false)
    /** Empty until the expert picks a cycle, so a new record never reads as already chosen. */
    var selectedCycle by mutableStateOf("")
    var step by mutableStateOf(NovaEducationStep.companies)
    var returningToReview by mutableStateOf(false)
    var validationStep by mutableStateOf<NovaEducationStep?>(null)
    var validationMessage by mutableStateOf<String?>(null)
    val people = mutableStateMapOf<String, List<NovaPersonOption>>()
    private val requested = mutableSetOf<String>()

    val basic get() = template.cycle in basicCycles
    val method get() = template.topics.firstOrNull()?.method ?: "face_to_face"
    val changed: Boolean get() {
        val row = saved; val education = row?.education ?: return true
        return draft.title != row.title || draft.notes != row.notes || draft.providerName != education.providerName ||
            draft.trainers != education.trainers || draft.scopes != education.scopes
    }

    /** Edits to the shared curriculum land on every scope once the editor is ready; loading never rewrites a saved record. */
    fun applyTemplate(value: NovaEducationScope) {
        template = value
        if (ready) draft = draft.copy(scopes = draft.scopes.map {
            it.copy(cycle = value.cycle, topics = value.topics, contextNote = value.contextNote, lessons = value.lessons, draftDays = value.draftDays,
                location = value.location)
        })
    }

    /** A change in minutes redistributes the days; any other topic edit only re-places the lessons. */
    fun setTopics(value: List<NovaEducationTopic>) {
        val before = template.net
        applyTemplate(template.copy(topics = value))
        if (template.net != before) rebalance() else recompute()
    }

    /** Trainers do not vary per topic: every topic is credited to whoever is listed. */
    fun setTrainers(value: List<NovaEducationTrainer>) {
        draft = draft.copy(trainers = value)
        val ids = value.map { it.id }
        applyTemplate(template.copy(topics = template.topics.map { it.copy(trainerIds = ids) }))
    }

    /** Workplace-specific topics stay face to face wherever the regulation asks for it. */
    fun applyMethod(value: String) {
        val inPerson = template.hazardClass != "low" || template.cycle == "onboarding"
        applyTemplate(template.copy(topics = template.topics.map { it.copy(method = if (it.group == "G4" && inPerson) "face_to_face" else value) }))
    }

    fun changeDays(value: List<NovaEducationDay>) { days = value; recompute() }

    val units get() = NovaEducationClock.units(template.net, basic)

    /** More than eight lesson units (about eight hours) cannot fit in one working day. */
    val neededDays get() = if (template.net <= 0) 1 else maxOf(1, (units + 7) / 8)

    val distributionValid: Boolean get() {
        val limit = if (basic) 8 else 1
        return days.isNotEmpty() && days.sumOf { it.lessonCount } == units && days.all { it.lessonCount in 1..limit } &&
            days.map { NovaEducationClock.day(it.instant) }.toSet().size == days.size
    }

    /** A realized training: every lesson, breaks included, has already ended. */
    val endsInPast: Boolean get() = distributionValid && template.lessons.isNotEmpty() && template.lessons.all { lesson ->
        NovaEducationClock.date(lesson.startsAt)?.plusSeconds((lesson.instructionMinutes + lesson.breakMinutes) * 60L)?.let { !it.isAfter(Instant.now()) } ?: false
    }

    /** Adds the days the minutes need and shares the lesson units evenly across them. */
    fun rebalance() {
        if (days.isEmpty()) return
        var list = days
        while (list.size < neededDays) list = list + NovaEducationDay.of(list.last().instant.plus(1, ChronoUnit.DAYS), 1)
        val count = units
        days = list.mapIndexed { index, day -> day.copy(lessonCount = count / list.size + if (index < count % list.size) 1 else 0) }
        recompute()
    }

    fun resetRecommendedDays() {
        val first = days.firstOrNull()?.instant ?: NovaEducationClock.initialDays(template.net, basic).first().instant
        days = (0 until neededDays).map { NovaEducationDay.of(first.plus(it.toLong(), ChronoUnit.DAYS), 1) }
        rebalance()
    }

    /** The one place lessons are placed: only a valid day distribution produces them. */
    fun recompute() {
        if (template.net <= 0) { applyTemplate(template.copy(lessons = emptyList())); return }
        if (days.isEmpty()) days = NovaEducationClock.initialDays(template.net, basic)
        applyTemplate(template.copy(lessons = if (distributionValid) NovaEducationClock.distribute(template.topics, days, basic) else emptyList(),
            draftDays = days))
    }

    /** The company's saved curriculum or the official profile, keeping the chosen method and trainers. */
    fun refreshDefaults() {
        val method = method
        val ids = draft.trainers.map { it.id }
        val hazard = template.hazardClass ?: "low"
        val curriculum = draft.scopes.firstOrNull()?.let { context.curriculum(it, template.cycle, hazard) }
        val topics = curriculum?.education?.topics ?: context.`package`.topics(template.cycle, hazard)
        applyTemplate(template.copy(topics = topics.map { it.copy(trainerIds = ids) }, contextNote = curriculum?.education?.contextNote ?: ""))
        applyMethod(method)
        days = NovaEducationClock.initialDays(template.net, basic)
        recompute()
    }

    fun chooseCycle(cycle: String) {
        selectedCycle = cycle
        applyTemplate(template.copy(cycle = cycle))
        draft = draft.copy(title = template.cycleName)
        refreshDefaults()
    }

    fun removeParticipant(scopeIndex: Int, person: String) {
        val scope = draft.scopes.getOrNull(scopeIndex) ?: return
        draft = draft.copy(scopes = draft.scopes.toMutableList().also {
            it[scopeIndex] = scope.copy(participants = scope.participants.filterNot { p -> p.id == person })
        })
        validationStep = null; validationMessage = null
    }

    fun loadPeople(company: String) {
        val key = company.lowercase()
        if (!requested.add(key)) return
        coroutines.launch {
            try { people[key] = client.employees(company) } catch (failure: Exception) { requested.remove(key); error = NovaTrainingWords.message(failure) }
        }
    }

    /**
     * A scope targets a workplace when the company has one, otherwise the company itself. One training
     * carries one hazard class; a legacy migration ([seed] false) replays history and never loses a company over this.
     */
    fun add(company: String, workplace: String?, seed: Boolean = true) {
        val row = companies.firstOrNull { it.id.sameId(company) } ?: return
        val place = workplace?.let { id -> context.workplaces.firstOrNull { it.id.sameId(id) && it.companyId.sameId(company) } }
        if (workplace != null && place == null) return
        if (workplace == null && context.workplaces.any { it.companyId.sameId(company) }) return
        val hazard = place?.hazardClass ?: row.hazardClass.orEmpty()
        if (seed && draft.scopes.isNotEmpty() && template.hazardClass != hazard) {
            error = "${NovaTrainingWords.hazard(template.hazardClass)} ve ${NovaTrainingWords.hazard(hazard)} sınıfındaki firmalar aynı eğitim " +
                "dosyasında yer alamaz. Ayrı bir eğitim kaydı açın."
            return
        }
        if (seed && draft.scopes.isEmpty() && template.hazardClass != hazard) {
            // The first company sets the hazard class. Curriculum and schedule are prepared only once an
            // education type is chosen; a custom cycle has no hazard dependency and stays as defined.
            if (selectedCycle.isEmpty()) {
                applyTemplate(template.copy(hazardClass = hazard))
            } else {
                val method = method
                val topics = if (template.cycle != "custom") context.`package`.topics(template.cycle, hazard) else template.topics
                val ids = draft.trainers.map { it.id }
                applyTemplate(template.copy(hazardClass = hazard, topics = topics.map { it.copy(trainerIds = ids) }))
                applyMethod(method)
                days = NovaEducationClock.initialDays(template.net, basic)
                recompute()
            }
        }
        var scope = NovaEducationScope(companyId = company, workplaceId = place?.id, companyName = row.name, workplaceName = place?.name, hazardClass = hazard)
        // The signer lives on the company record; the certificate prints a blank line until it is known.
        if (seed) scope = scope.copy(cycle = template.cycle, topics = template.topics, contextNote = template.contextNote, lessons = template.lessons,
            draftDays = template.draftDays, location = template.location, legalName = place?.name ?: row.name, employerName = "")
        draft = draft.copy(scopes = draft.scopes + scope)
        error = null
        loadPeople(company)
    }

    fun isPicked(company: String, workplace: String?) = draft.scopes.any { it.companyId.sameId(company) && samePlace(it.workplaceId, workplace) }

    fun toggle(company: String, workplace: String?) {
        val picked = draft.scopes.firstOrNull { it.companyId.sameId(company) && samePlace(it.workplaceId, workplace) }
        if (picked != null) removeScope(picked.id) else add(company, workplace)
    }

    fun removeScope(id: String) {
        draft = draft.copy(scopes = draft.scopes.filterNot { it.id == id })
        validationStep = null; validationMessage = null
    }

    /** Topics are credited to whoever is still listed. */
    fun removeTrainer(id: String) {
        setTrainers(draft.trainers.filterNot { it.id == id })
        validationStep = null; validationMessage = null
    }

    /**
     * An official profile's certificate back names where the training applied: the chosen companies or
     * workplaces and the workplace-specific topics, unless the expert wrote their own note.
     */
    fun fillContextFromSelectedTraining() {
        if (context.`package`.preset(template.cycle, template.hazardClass.orEmpty()) == null) return
        if (template.contextNote.isNotBlank() && !template.contextNote.startsWith("Eğitim kapsamı: ")) return
        val places = draft.scopes.map { it.workplaceName ?: it.companyName.orEmpty() }.filter { it.isNotEmpty() }
        val topics = template.topics.filter { it.group == "G4" }.map { it.title }.filter { it.isNotEmpty() }
        if (places.isEmpty() || topics.isEmpty()) return
        val note = "Eğitim kapsamı: ${places.joinToString(", ")}. İşlenen işyerine özgü konular: ${topics.joinToString(", ")}.".take(4000)
        applyTemplate(template.copy(contextNote = note))
    }

    private fun samePlace(a: String?, b: String?) = if (a == null) b == null else a.sameId(b)

    fun isSelected(index: Int, person: NovaPersonOption) = draft.scopes.getOrNull(index)?.participants?.any { it.id.sameId(person.id) } == true

    /** A person attends once: someone already in another scope is not added again. */
    fun setSelected(index: Int, person: NovaPersonOption, on: Boolean) {
        val scopes = draft.scopes.toMutableList()
        val scope = scopes.getOrNull(index) ?: return
        if (on) {
            if (scopes.any { s -> s.participants.any { it.id.sameId(person.id) } }) return
            scopes[index] = scope.copy(participants = scope.participants + NovaEducationPerson(person.id, person.name, person.jobTitle.orEmpty(), person.department))
        } else scopes[index] = scope.copy(participants = scope.participants.filterNot { it.id.sameId(person.id) })
        draft = draft.copy(scopes = scopes)
    }

    /** The same inputs the certificate needs, checked before the record is written. */
    fun firstMissing(): Pair<NovaEducationStep, String>? {
        val companies = NovaEducationStep.companies
        if (!draft.isComplete(companies)) return companies to "Eğitim için en az bir firma/işyeri seçin. Tehlike sınıfları aynı olmalı."
        if (draft.scopes.size > 100 || draft.scopes.map { it.companyId.lowercase() }.toSet().size > 30)
            return companies to "Tek eğitim için firma/işyeri seçim sayısı sınırı aşıldı."
        val scopeKeys = draft.scopes.map { "${it.companyId.lowercase()}:${it.workplaceId?.lowercase() ?: "firma"}" }
        if (scopeKeys.toSet().size != scopeKeys.size) return companies to "Aynı firma/işyerini eğitimde bir kez seçin."
        if (draft.title.isBlank() || draft.providerName.isBlank()) return NovaEducationStep.info to "Eğitim türünü ve düzenleyici kişi veya kurumu tamamlayın."
        if (draft.title.length > 200 || draft.providerName.length > 300 || draft.notes.length > 2000)
            return NovaEducationStep.info to "Eğitim başlığı, düzenleyici veya notlar için metin uzunluğunu kısaltın."
        val topics = NovaEducationStep.topics
        if (template.topics.isEmpty() || template.topics.any { it.instructionMinutes <= 0 || it.title.isBlank() })
            return topics to "Eğitim konularının dakikalarını tamamlayın."
        if (template.topics.size > 150 || template.topics.any { it.instructionMinutes > 1440 || it.title.length > 1000 })
            return topics to "Konu sayısını, başlık uzunluğunu ve dakikaları kontrol edin."
        context.`package`.preset(template.cycle, template.hazardClass.orEmpty())?.let { preset ->
            val selected = template.topics.filter { it.instructionMinutes > 0 }.map { it.parentCode ?: it.code }.toSet()
            if (context.`package`.topics.any { it.code !in selected }) return topics to "Zorunlu eğitim konularını tamamlayın."
            if (template.net < preset.defaultInstructionMinutes || template.group4 < preset.group4.budgetInstructionMinutes)
                return topics to "Eğitim süresi ve işyerine özgü konu dakikaları seçilen eğitim için yeterli olmalı."
            val common = template.topics.filter { it.group != "G4" }.sumOf { it.instructionMinutes }
            val minimum = preset.commonGroupsReviewGuard?.referenceInstructionMinutes
            if (template.cycle == "initial" && minimum != null && common < minimum)
                return topics to "Genel, sağlık ve teknik konuların toplam süresini tamamlayın."
        }
        if (!draft.isComplete(NovaEducationStep.trainers)) return NovaEducationStep.trainers to "Her eğiticinin adını tamamlayın; boş ek satırları kaldırın."
        if (template.topics.any { it.trainerIds.isEmpty() }) return topics to "Konulara en az bir eğitici atayın."
        if (template.topics.any { (template.cycle == "onboarding" || (it.group == "G4" && template.hazardClass != "low")) && it.method == "online" })
            return NovaEducationStep.info to "Bu eğitimde işyerine özgü konular için yüz yüze yöntemi seçin."
        if (!draft.isComplete(NovaEducationStep.schedule) || template.lessons.size > 200 || !endsInPast)
            return NovaEducationStep.schedule to "Eğitim gün ve saatlerini kontrol edin. Dersler çakışmamalı ve tamamı geçmişte olmalı."
        val participants = NovaEducationStep.participants
        if (!draft.isComplete(participants)) return participants to "Her seçilen firma/işyeri için en az bir katılımcı seçin."
        if (draft.scopes.any { it.participants.size > 500 }) return participants to "Bir firma/işyeri için katılımcı sayısı sınırı aşıldı."
        val ids = draft.scopes.flatMap { scope -> scope.participants.map { it.id.lowercase() } }
        if (ids.toSet().size != ids.size) return participants to "Aynı personeli eğitimde bir kez seçin."
        return null
    }

    fun flagged(step: NovaEducationStep) = validationStep == step && firstMissing()?.first == step

    val next get() = NovaEducationStep.entries.getOrNull(step.ordinal + 1)

    fun advanceIfComplete(from: NovaEducationStep) {
        val target = next ?: return
        if (step != from || !draft.isComplete(from)) return
        step = if (returningToReview) NovaEducationStep.review else target
        returningToReview = false
    }

    /** A brand-new record starts with no trainers: "Ben eğiticiyim" keeps the choice one tap away but deliberate. */
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
                    val before = draft.scopes.size
                    add(company.companyId, context.workplaces.firstOrNull { it.companyId.sameId(company.companyId) }?.id, seed = false)
                    if (draft.scopes.size == before) return@forEach
                    val last = draft.scopes.last()
                    draft = draft.copy(scopes = draft.scopes.dropLast(1) + last.copy(participants = company.participants.map { NovaEducationPerson(it.id, it.name) }))
                }
            }
            initialCompany != null && context.workplaces.none { it.companyId.sameId(initialCompany) } -> add(initialCompany, null)
        }
    }

    /** An existing record restores its curriculum; a new one stays empty until the expert picks an education type. */
    fun syncTemplate() {
        val first = draft.scopes.firstOrNull()
        template = when {
            first != null -> template.copy(cycle = first.cycle, topics = first.topics, contextNote = first.contextNote, lessons = first.lessons,
                draftDays = first.draftDays, location = first.location, hazardClass = first.hazardClass)
            selectedCycle.isNotEmpty() && template.topics.isEmpty() -> template.copy(hazardClass = "low", topics = context.`package`.topics(template.cycle, "low"))
            else -> template
        }
        if (selectedCycle.isEmpty()) {
            template = template.copy(topics = emptyList(), lessons = emptyList(), draftDays = null)
            days = emptyList()
            return
        }
        days = template.draftDays ?: NovaEducationClock.days(template.lessons)
        if (days.isEmpty()) days = NovaEducationClock.initialDays(template.net, basic)
        if (!distributionValid) {
            val lessonDays = NovaEducationClock.days(template.lessons)
            if (lessonDays.size == days.size) days = days.map { day ->
                lessonDays.firstOrNull { NovaEducationClock.day(it.instant) == NovaEducationClock.day(day.instant) }?.let { day.copy(lessonCount = it.lessonCount) } ?: day
            }
            if (!distributionValid) rebalance()
        }
        recompute()
    }

    /** Returns whether the company picker should open straight away. */
    fun initialize(initialCompany: String?): Boolean {
        try {
            val pendingDraft = client.pending()
            val preserved = client.draft(original?.id)
            when {
                pendingDraft != null -> { draft = preserved ?: pendingDraft; pending = true }
                preserved != null -> {
                    draft = preserved; restored = true
                    notice = if (original != null && preserved.expectedVersion != original.version)
                        "Korunan taslak eski bir sürüme ait. Güncel kaydı değiştirmeden önce içeriğini karşılaştırın."
                    else "Önceki taslağınız geri yüklendi. Baştan başlamak isterseniz aşağıdan taslağı temizleyebilirsiniz."
                }
                else -> seedFresh(initialCompany)
            }
            // A draft may already hold a company whose scope carries the model's default cycle even though
            // no type was chosen yet; only a chosen title (or a saved record) counts as a choice.
            val hasChosenType = draft.title.isNotBlank()
            val titleCycle = NovaEducationScope.cycles.firstOrNull { it.second == draft.title }?.first
            selectedCycle = if (original != null || hasChosenType) draft.scopes.firstOrNull()?.cycle ?: titleCycle ?: template.cycle else ""
            if (selectedCycle.isNotEmpty()) template = template.copy(cycle = selectedCycle)
            syncTemplate()
            ready = true
            draft.scopes.map { it.companyId }.distinctBy { it.lowercase() }.forEach(::loadPeople)
            return original == null && !restored && !pending && draft.scopes.isEmpty() && initialCompany != null &&
                context.workplaces.any { it.companyId.sameId(initialCompany) }
        } catch (failure: Exception) { error = NovaTrainingWords.message(failure) }
        return false
    }

    fun discard(initialCompany: String?) {
        runCatching { client.discardDraft(original?.id) }
        ready = false
        draft = NovaEducationDraft(); template = NovaEducationScope(companyId = "")
        restored = false; notice = null
        seedFresh(initialCompany)
        selectedCycle = if (original == null) "" else draft.scopes.firstOrNull()?.cycle ?: template.cycle
        syncTemplate()
        ready = true
        draft.scopes.map { it.companyId }.distinctBy { it.lowercase() }.forEach(::loadPeople)
    }

}

/** The certificates page a save opens; [celebrate] shows the success card once. */
private class CertificatesPage(val session: NovaTrainingSession, val celebrate: Boolean, val created: Boolean)

private enum class EducationSheet { companies, cycle, participants }

/** The guided seven-step form (iOS `NovaEducationEditor`): one expanded section, the rest as summaries. */
@Composable
private fun NovaEducationEditor(client: NovaTrainingClient, companies: List<NovaCompanyOption>, writable: Set<String>, initialCompany: String?,
                                original: NovaTrainingSession?, context: NovaEducationContext, canWrite: Boolean,
                                onSaved: ((NovaTrainingSession) -> Unit)?, onClose: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val model = remember { EducationEditorModel(context, companies, original, client, coroutines) }
    var busy by remember { mutableStateOf(false) }
    var saveProgress by remember { mutableStateOf<String?>(null) }
    var sheet by remember { mutableStateOf<EducationSheet?>(null) }
    var certificatesPage by remember { mutableStateOf<CertificatesPage?>(null) }
    var banner by remember { mutableStateOf(false) }
    var options by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    var confirmingDelete by remember { mutableStateOf(false) }
    val scroll = rememberScrollState()
    val positions = remember { mutableStateMapOf<String, Int>() }
    LaunchedEffect(Unit) {
        if (model.initialize(initialCompany)) sheet = EducationSheet.companies
        // A saved training opens on its summary, where every section is one tap away.
        if (original != null) model.step = NovaEducationStep.review
        if (model.restored) { banner = true; delay(5_000); banner = false }
    }
    // Autosave: only an edit worth keeping, debounced so typing does not write on every key.
    LaunchedEffect(model.draft) {
        if (!model.ready || !model.changed) return@LaunchedEffect
        delay(300)
        runCatching { client.preserve(model.draft) }.onFailure { model.error = NovaTrainingWords.message(it) }
    }
    LaunchedEffect(model.step) { positions[model.step.name]?.let { scroll.animateScrollTo(it) } }
    /** Writes the record; a refusal that names a section reopens it instead of showing a generic error. */
    suspend fun save() {
        busy = true; model.error = null
        try {
            val current = model.saved
            val row = if (current != null && !model.changed) current else {
                saveProgress = "Eğitim kaydediliyor…"
                val committed = client.save(model.draft).row
                val education = committed?.education ?: throw NovaTrainingException("UNAVAILABLE")
                model.saved = committed
                model.draft = model.draft.copy(id = committed.id, expectedVersion = committed.version, scopes = education.scopes, trainers = education.trainers)
                committed
            }
            if (row.education == null) throw NovaTrainingException("UNAVAILABLE")
            saveProgress = null
            // The saved training opens its certificates; a list that owns the editor shows them after closing it.
            if (onSaved != null) onSaved(row) else certificatesPage = CertificatesPage(row, celebrate = true, created = original == null)
        } catch (failure: Exception) {
            saveProgress = null
            val correction = NovaTrainingWords.correction(failure)
            if (correction != null) {
                model.validationStep = correction.first; model.validationMessage = correction.second; model.step = correction.first
            } else model.error = NovaTrainingWords.message(failure)
            model.pending = runCatching { client.pending() != null }.getOrDefault(false)
        }
        busy = false
    }
    fun submit() {
        model.error = null
        model.draft = model.draft.preparedForSave()
        model.setTrainers(model.draft.trainers)
        model.fillContextFromSelectedTraining()
        val missing = model.firstMissing()
        if (missing != null) {
            model.validationStep = missing.first; model.validationMessage = missing.second
            model.returningToReview = true; model.step = missing.first
            return
        }
        model.validationStep = null; model.validationMessage = null
        coroutines.launch { save() }
    }
    /** Removes the training from every company and participant; a queued removal is replayed as it was sent. */
    suspend fun deleteTraining(waiting: NovaEducationDraft? = null) {
        val saved = model.saved ?: return
        if (!canWrite || busy) return
        busy = true; deleting = true; model.error = null
        try {
            client.save(waiting ?: NovaEducationDraft(action = "delete", id = saved.id, expectedVersion = saved.version))
            model.pending = false
            onClose()
        } catch (failure: Exception) {
            model.error = NovaTrainingWords.message(failure)
            model.pending = runCatching { client.pending() != null }.getOrDefault(false)
        } finally { busy = false; deleting = false }
    }
    suspend fun retry() {
        try {
            val waiting = client.pending() ?: return
            if (waiting.action == "curriculum") {
                busy = true
                try { client.save(waiting); model.pending = false; model.notice = "Firma müfredatı kaydedildi." } finally { busy = false }
            } else if (waiting.action == "delete") {
                deleteTraining(waiting)
            } else { model.draft = waiting; model.pending = false; save() }
        } catch (failure: Exception) { model.error = NovaTrainingWords.message(failure) }
    }
    certificatesPage?.let { page ->
        NovaEducationCertificatesPage(client, page.session, context.certificateEnabled && canWrite, page.celebrate, page.created) { certificatesPage = null }
        return
    }
    when (sheet) {
        EducationSheet.companies -> { CompanyPicker(model, writable) { sheet = null; model.advanceIfComplete(NovaEducationStep.companies) }; return }
        EducationSheet.cycle -> {
            CyclePicker(model.selectedCycle, onClose = { sheet = null }) { cycle ->
                model.chooseCycle(cycle); sheet = null; model.advanceIfComplete(NovaEducationStep.info)
            }
            return
        }
        EducationSheet.participants -> { ParticipantsPicker(model) { sheet = null; model.advanceIfComplete(NovaEducationStep.participants) }; return }
        null -> Unit
    }
    BackHandler(enabled = !busy, onBack = onClose)
    Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            NovaPageHeading(if (original == null) "Eğitim Ekle" else if (canWrite) "Eğitimi Düzenle" else "Eğitim Ayrıntısı",
                "Gerçekleşen eğitim · kişi bazlı belge", backEnabled = !busy,
                modifier = Modifier.weight(1f), onBack = onClose)
            if (model.restored && !model.pending) Box(Modifier.size(36.dp).clip(CircleShape).novaRowPress { options = true }
                .testTag("education.options").semantics { contentDescription = "Eğitim seçenekleri" }, contentAlignment = Alignment.Center) {
                NovaIcon("ellipsis", 20.dp)
            }
        }
        if (banner) Row(Modifier.fillMaxWidth().background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(12.dp)).padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaText("Önceki taslağınız geri yüklendi", Modifier.weight(1f), NovaTypeToken.meta)
            if (!model.pending) NovaText("Baştan başla", Modifier.novaRowPress { banner = false; model.discard(initialCompany) }, NovaTypeToken.bodyStrong)
        }
        if (!model.ready) {
            model.error?.let { NovaText(it, color = NovaColorToken.statusDangerInk.color()) }
                ?: Box(Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) { NovaSpinner(NovaColorToken.text.color(), size = 24.dp) }
            return@Column
        }
        EducationProgress(model.draft)
        NovaEducationStep.entries.forEach { step ->
            SectionCard(model, step, Modifier.onGloballyPositioned { positions[step.name] = it.positionInParent().y.toInt() }) {
                when (step) {
                    NovaEducationStep.companies -> CompaniesStep(model, canWrite) { sheet = EducationSheet.companies }
                    NovaEducationStep.info -> InfoStep(model, canWrite) { sheet = EducationSheet.cycle }
                    NovaEducationStep.topics -> if (model.selectedCycle.isEmpty()) NovaHelpHint("Konular, eğitim türünü seçtikten sonra hazırlanır.")
                        else TopicsStep(model, canWrite)
                    NovaEducationStep.schedule -> if (model.selectedCycle.isEmpty()) NovaHelpHint("Gün ve saatler, eğitim türünü seçtikten sonra hazırlanır.")
                        else ScheduleStep(model, canWrite)
                    NovaEducationStep.trainers -> TrainersStep(model, client.userName, canWrite)
                    NovaEducationStep.participants -> ParticipantsStep(model, canWrite, editingSaved = original != null) { sheet = EducationSheet.participants }
                    NovaEducationStep.review -> ReviewStep(model)
                }
            }
        }
        model.error?.let { NovaCard(Modifier.fillMaxWidth(), padding = 14) { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) } }
        model.notice?.takeIf { !model.restored || (original != null && original.version != model.draft.expectedVersion) }?.let { text ->
            NovaCard(Modifier.fillMaxWidth(), padding = 14) { NovaText(text, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color()) }
        }
        saveProgress?.let { NovaHelpHint(it) }
        if (model.pending) NovaButton("Bekleyen kaydı aynı işlemle tamamla", { coroutines.launch { retry() } }, variant = NovaButtonVariant.Surface,
            enabled = !busy, symbol = "arrow.clockwise")
        if (model.step == NovaEducationStep.review) {
            NovaButton(if (original == null) "Gerçekleşen eğitimi kaydet" else "Değişiklikleri kaydet", { submit() },
                Modifier.fillMaxWidth().testTag("education.save"),
                enabled = canWrite && !busy && !model.pending, loading = busy && !deleting, symbol = "checkmark")
            // The draft already autosaves; this makes that explicit so the expert can leave knowing it.
            NovaButton("Taslak olarak kaydet", { runCatching { client.preserve(model.draft) }; onClose() }, Modifier.fillMaxWidth().testTag("education.savedraft"),
                variant = NovaButtonVariant.Surface, enabled = canWrite && !busy, symbol = "tray.and.arrow.down")
            if (model.saved != null) NovaButton("Eğitimi sil", { confirmingDelete = true }, Modifier.fillMaxWidth().testTag("education.delete"),
                variant = NovaButtonVariant.Danger, enabled = canWrite && !busy && !model.pending, loading = deleting, symbol = "trash")
        } else StepNavigation(model)
        val saved = model.saved
        if (saved != null && !model.changed) NovaButton("Sertifikaları aç", { certificatesPage = CertificatesPage(saved, celebrate = false, created = false) },
            Modifier.fillMaxWidth().testTag("education.certificates.open"), variant = NovaButtonVariant.Surface, symbol = "doc.text")
        else if (saved != null) NovaText("Sertifikaları görmek için değişiklikleri kaydedin.", style = NovaTypeToken.metaQuiet)
    }
    NovaPopup(confirmingDelete, { confirmingDelete = false }, identifier = "education.delete.confirm") {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaPopupHeading("Eğitim silinsin mi?", symbol = "trash")
            NovaText("Eğitim tüm seçili firmaların ve katılımcıların güncel kayıtlarından kaldırılır. Önceki sürümler geçmişte korunur.",
                style = NovaTypeToken.metaQuiet)
            NovaButton("Eğitimi sil", { confirmingDelete = false; coroutines.launch { deleteTraining() } },
                Modifier.fillMaxWidth().testTag("education.delete.confirm.yes"), variant = NovaButtonVariant.Danger, symbol = "trash")
            NovaButton("Vazgeç", { confirmingDelete = false }, Modifier.fillMaxWidth(), variant = NovaButtonVariant.Surface)
        }
    }
    NovaPopup(options, { options = false }, identifier = "education.options.popup") {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaPopupHeading("Eğitim seçenekleri", symbol = "ellipsis")
            NovaPopupOption("Baştan başla", "arrow.counterclockwise", identifier = "education.draft.discard") {
                options = false; banner = false; model.discard(initialCompany)
            }
        }
    }
}

@Composable
private fun EducationProgress(draft: NovaEducationDraft) {
    NovaCard(Modifier.fillMaxWidth().testTag("education.progress"), padding = 12) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaText("Eğitim oluşturuluyor · ${draft.completedCount} / ${NovaEducationStep.entries.size}", style = NovaTypeToken.label)
            Box(Modifier.fillMaxWidth().height(6.dp).background(NovaColorToken.borderMuted.color(), CircleShape)) {
                Box(Modifier.fillMaxWidth(draft.progress).fillMaxHeight().background(NovaColorToken.accent.color(), CircleShape))
            }
        }
    }
}

private fun summary(model: EducationEditorModel, step: NovaEducationStep): String? {
    val draft = model.draft
    val template = model.template
    return when (step) {
        NovaEducationStep.companies -> if (draft.scopes.isEmpty()) null else "${draft.scopes.size} firma/işyeri seçimi · " +
            "${NovaTrainingWords.hazard(draft.scopes.first().hazardClass)} · " + draft.scopes.mapNotNull { it.companyName }.joinToString(", ")
        NovaEducationStep.info -> if (model.selectedCycle.isEmpty()) null else "${template.cycleName} · ${if (model.method == "online") "Online" else "Yüz yüze"}"
        NovaEducationStep.topics -> if (model.selectedCycle.isNotEmpty() && template.net > 0) "Toplam öğretim: ${duration(template.net)}" else null
        NovaEducationStep.schedule -> if (model.selectedCycle.isEmpty() || template.lessons.isEmpty()) null
            else "${model.days.size} gün · ${duration(template.net + template.breakTotal)} (molalar dahil)"
        NovaEducationStep.trainers -> if (draft.trainers.isEmpty()) null else draft.trainers.map { it.name }.filter { it.isNotEmpty() }.joinToString(", ")
        NovaEducationStep.participants -> if (draft.scopes.isEmpty()) null else
            "${draft.scopes.sumOf { it.participants.size }} kişi · ${draft.scopes.map { it.companyId.lowercase() }.distinct().size} firma"
        NovaEducationStep.review -> if (draft.isComplete(NovaEducationStep.review)) "Kaydetmeye hazır" else null
    }
}

/** One accordion section: the open one shows its form, a closed one its two-line summary. */
@Composable
private fun SectionCard(model: EducationEditorModel, step: NovaEducationStep, modifier: Modifier, content: @Composable () -> Unit) {
    val flagged = model.flagged(step)
    val complete = model.draft.isComplete(step)
    val completed = complete && !flagged
    val status = when {
        flagged -> "Eksik bilgi"
        step == NovaEducationStep.schedule && model.selectedCycle.isNotEmpty() && !model.endsInPast -> "Kontrol gerekli"
        complete -> "Tamamlandı"
        step == NovaEducationStep.review -> "Kontrol gerekli"
        else -> "Eksik bilgi"
    }
    NovaCard(modifier.fillMaxWidth().testTag("education.current-step.${step.name}"), padding = 16) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(Modifier.fillMaxWidth().novaRowPress { model.step = step }.testTag("education.section.${step.name}"),
                horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon(if (completed) "checkmark.circle.fill" else step.symbol, 17.dp, Modifier.width(24.dp),
                    tint = if (completed) NovaColorToken.accent.color() else NovaColorToken.textSecondary.color())
                NovaText(step.title, Modifier.weight(1f), NovaTypeToken.cardTitle)
                NovaStatusPill(status, if (completed) NovaStatus.Success else NovaStatus.Warning)
            }
            if (model.step == step) {
                NovaDivider()
                if (model.validationStep == step) model.validationMessage?.let { NovaHelpHint(it) }
                content()
            } else summary(model, step)?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color(), maxLines = 2) }
        }
    }
}

@Composable
private fun StepNavigation(model: EducationEditorModel) {
    val step = model.step
    val canAdvance = model.draft.isComplete(step) && (step != NovaEducationStep.schedule || model.endsInPast) && !model.flagged(step)
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        val previous = NovaEducationStep.entries.getOrNull(step.ordinal - 1)
        if (previous != null) NovaButton("Geri", { model.step = previous }, Modifier.weight(1f), variant = NovaButtonVariant.Surface, symbol = "chevron.left")
        else Spacer(Modifier.weight(1f))
        NovaButton(if (model.returningToReview) "Kontrole dön" else "Devam", {
            if (model.returningToReview) { model.step = NovaEducationStep.review; model.returningToReview = false }
            else model.next?.let { model.step = it }
        }, Modifier.weight(1f).testTag("education.next.${step.name}"), enabled = canAdvance, symbol = "chevron.right")
    }
}

@Composable
private fun CompaniesStep(model: EducationEditorModel, canWrite: Boolean, onPick: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        NovaText("Birden fazla firma seçebilirsiniz. İşyeri olmayan firma doğrudan eklenir; işyeri varsa ilgili işyerini seçin. Tehlike sınıfları aynı olmalıdır.",
            style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color())
        summary(model, NovaEducationStep.companies)?.let { NovaText(it, style = NovaTypeToken.bodyStrong) }
        model.draft.scopes.forEach { scope ->
            Row(Modifier.fillMaxWidth().background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(12.dp)).padding(12.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("building.2", 16.dp, tint = NovaColorToken.accent.color())
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(scope.companyName ?: "Firma", style = NovaTypeToken.bodyStrong)
                    scope.workplaceName?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
                }
                if (canWrite) NovaText("Kaldır", Modifier.novaRowPress { model.removeScope(scope.id) }.testTag("education.company.remove.${scope.id}")
                    .padding(vertical = 8.dp), NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color())
            }
        }
        NovaButton(if (model.draft.scopes.isEmpty()) "Firma ekle" else "Başka firma veya işyeri ekle", onPick, Modifier.testTag("education.companies.open"),
            variant = NovaButtonVariant.Surface, enabled = canWrite, symbol = "building.2")
    }
}

/** A full page like iOS: every writable company, its workplaces, or the company itself when it has none. */
@Composable
private fun CompanyPicker(model: EducationEditorModel, writable: Set<String>, onDone: () -> Unit) {
    BackHandler(onBack = onDone)
    var search by remember { mutableStateOf("") }
    val available = model.companies.filter { it.id.lowercase() in writable }
    val filtered = if (search.isBlank()) available else available.filter { it.name.contains(search.trim(), true) }
    val scopes = model.draft.scopes
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            NovaText("Firma ve işyerleri", Modifier.weight(1f), NovaTypeToken.screenTitle)
            NovaButton("Bitti", onDone, variant = NovaButtonVariant.Surface, compact = true)
        }
        NovaSearchCapsule(search, "Firma ara", "education.companies.search") { search = it }
        NovaText("${scopes.size} firma/işyeri seçimi" + (scopes.firstOrNull()?.let { " · ${NovaTrainingWords.hazard(it.hazardClass)}" } ?: ""),
            style = NovaTypeToken.metaQuiet)
        filtered.forEach { company ->
            val places = model.context.workplaces.filter { it.companyId.sameId(company.id) }
            NovaCard(Modifier.fillMaxWidth().testTag("education.companies.${company.id}"), padding = 12) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    NovaText(company.name, style = NovaTypeToken.cardTitle)
                    if (places.isEmpty()) {
                        val hazard = company.hazardClass.orEmpty()
                        val picked = model.isPicked(company.id, null)
                        ChoiceRow("Firmayı ekle", NovaTrainingWords.hazard(hazard), picked, picked || scopes.none { it.hazardClass != hazard },
                            "education.companies.${company.id}.self") { model.toggle(company.id, null) }
                    }
                    places.forEach { place ->
                        val picked = model.isPicked(company.id, place.id)
                        ChoiceRow(place.name, NovaTrainingWords.hazard(place.hazardClass), picked,
                            picked || scopes.none { it.hazardClass != place.hazardClass }, "education.companies.${company.id}.${place.id}") { model.toggle(company.id, place.id) }
                    }
                }
            }
        }
        if (filtered.isEmpty()) NovaText("Eğitim eklenebilecek firma bulunamadı.", style = NovaTypeToken.metaQuiet)
        model.error?.let { NovaHelpHint(it) }
        NovaButton("${scopes.size} seçimi tamamla", onDone, Modifier.fillMaxWidth().testTag("education.companies.done"), enabled = scopes.isNotEmpty(),
            symbol = "checkmark")
    }
}

@Composable
private fun ChoiceRow(title: String, detail: String, checked: Boolean, enabled: Boolean, tag: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).alpha(if (enabled) 1f else 0.4f).novaRowPress(enabled = enabled, onClick = onClick).testTag(tag)
        .semantics { role = Role.Checkbox; selected = checked }.padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(if (checked) "checkmark.square.fill" else "square", 18.dp, tint = if (checked) NovaColorToken.accentInk.color() else NovaColorToken.textMuted.color())
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            NovaText(title, style = NovaTypeToken.bodyStrong)
            NovaText(detail, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        }
    }
}

/** The record's title is its cycle's own name: the cycle is the one choice that drives topics, minutes and rules. */
@Composable
private fun CyclePicker(selectedCycle: String, onClose: () -> Unit, onPick: (String) -> Unit) {
    BackHandler(onBack = onClose)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            NovaText("Eğitim türü", Modifier.weight(1f), NovaTypeToken.screenTitle)
            NovaButton("Kapat", onClose, variant = NovaButtonVariant.Surface, compact = true)
        }
        NovaText("Eğitimin amacına uygun türü seçin. Konular ve süreler bu seçime göre hazırlanır.", style = NovaTypeToken.metaQuiet,
            color = NovaColorToken.textSecondary.color())
        NovaEducationScope.cycles.forEach { (code, name) ->
            val on = selectedCycle == code
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(NovaColorToken.surface.color(), RoundedCornerShape(16.dp))
                .novaRowPress { onPick(code) }.testTag("education.cycle.$code").semantics { selected = on }.padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    NovaText(name, style = NovaTypeToken.bodyStrong)
                    NovaText(cycleDescriptions[code].orEmpty(), style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                }
                NovaIcon(if (on) "checkmark.circle.fill" else "circle", 20.dp, tint = if (on) NovaColorToken.accent.color() else NovaColorToken.textSecondary.color())
            }
        }
    }
}

@Composable
private fun InfoStep(model: EducationEditorModel, canWrite: Boolean, onCycle: () -> Unit) {
    val template = model.template
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        NovaText("Eğitim türü ve konusu", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(14.dp))
            .border(1.5.dp, NovaColorToken.accent.color(), RoundedCornerShape(14.dp))
            .novaRowPress(enabled = canWrite, onClick = onCycle).testTag("education.cycle").padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon("books.vertical", 19.dp, tint = NovaColorToken.accentInk.color())
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                NovaText(if (model.selectedCycle.isEmpty()) "Eğitim türünü seç" else template.cycleName, style = NovaTypeToken.bodyStrong)
                NovaText(if (model.selectedCycle.isEmpty()) "Konular ve süreler seçiminize göre hazırlanır" else "Değiştirmek için dokunun",
                    style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            }
            NovaIcon("chevron.right", 13.dp, tint = NovaColorToken.accentInk.color())
        }
        NovaText("Eğitim türü değişirse konular ve dakikalar seçilen tehlike sınıfına göre yeniden hazırlanır.", style = NovaTypeToken.metaQuiet)
        NovaText("Eğitim yöntemi", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
        val online = model.method == "online"
        NovaSegmentedControl(listOf("Yüz yüze", "Online"), if (online) 1 else 0, Modifier.testTag("education.method")) { index ->
            if (canWrite) model.applyMethod(if (index == 1) "online" else "face_to_face")
        }
        if (template.hazardClass != "low" && online) NovaText("İşyerine özgü konular yüz yüze olarak kalır.", style = NovaTypeToken.metaQuiet)
        NovaTextField("Düzenleyici kişi / kurum", model.draft.providerName, { model.draft = model.draft.copy(providerName = it) },
            identifier = "education.provider", placeholder = "Kişi veya kurum adı", enabled = canWrite)
        NovaTextField("Notlar (isteğe bağlı)", model.draft.notes, { model.draft = model.draft.copy(notes = it) }, identifier = "education.notes",
            multiline = true, placeholder = "Eklemek istediğiniz notu yazın", enabled = canWrite)
    }
}

@Composable
private fun TopicsStep(model: EducationEditorModel, canWrite: Boolean) {
    val template = model.template
    var expanded by remember { mutableStateOf<String?>(null) }
    fun defaultMinutes(topic: NovaEducationTopic) =
        model.context.`package`.topics(template.cycle, template.hazardClass ?: "low").firstOrNull { it.code == topic.code }?.instructionMinutes ?: 30
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaText("${NovaTrainingWords.hazard(template.hazardClass)} · ${template.cycleName}", style = NovaTypeToken.bodyStrong)
        NovaText("Bir konu grubuna dokunarak konuları ve dakikaları düzenleyin. Süre değişince eğitim günleri yeniden hesaplanır.",
            style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color())
        topicGroups.forEach { (group, name) ->
            val items = template.topics.filter { it.group == group }
            if (items.isEmpty() && group != "G4") return@forEach
            val open = expanded == group
            Column(Modifier.fillMaxWidth().background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(12.dp))
                .border(1.dp, (if (open) NovaColorToken.accent else NovaColorToken.border).color(), RoundedCornerShape(12.dp)).padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(Modifier.fillMaxWidth().novaRowPress { expanded = if (open) null else group }.testTag("education.topics.$group"),
                    horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("list.bullet.rectangle", 15.dp, tint = NovaColorToken.accentInk.color())
                    NovaText("$group · $name", Modifier.weight(1f), NovaTypeToken.bodyStrong)
                    NovaText(duration(items.sumOf { it.instructionMinutes }), style = NovaTypeToken.meta)
                    NovaIcon(if (open) "chevron.up" else "chevron.down", 13.dp)
                }
                if (open) {
                    items.forEach { topic ->
                        TopicEditor(topic, removable = group == "G4" || !model.basic || topic.parentCode != null, defaultMinutes = defaultMinutes(topic),
                            enabled = canWrite, onChange = { value -> model.setTopics(model.template.topics.map { if (it.code == topic.code) value else it }) },
                            onRemove = { model.setTopics(model.template.topics.filterNot { it.code == topic.code }) })
                    }
                    if (group == "G4" && canWrite) NovaButton("Konu ekle", {
                        model.setTopics(model.template.topics + NovaEducationTopic("G4-" + java.util.UUID.randomUUID().toString().uppercase(), "G4", "", 0,
                            trainerIds = model.draft.trainers.map { it.id }))
                    }, variant = NovaButtonVariant.Surface, symbol = "plus", compact = true)
                }
            }
        }
        Column(Modifier.fillMaxWidth().background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(12.dp)).padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp)) {
            NovaText("Toplam öğretim: ${duration(template.net)}", style = NovaTypeToken.bodyStrong)
            NovaText("Planlanan eğitim: ${model.days.size} gün · ${duration(template.net + template.breakTotal)} (molalar dahil)", style = NovaTypeToken.metaQuiet)
        }
        model.context.`package`.preset(template.cycle, template.hazardClass.orEmpty())?.takeIf { template.net < it.defaultInstructionMinutes }?.let { preset ->
            NovaText("Bu eğitim profili için önerilen öğretim süresi ${duration(preset.defaultInstructionMinutes)}. Konu dakikalarını kontrol edin.",
                style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color())
        }
        if (model.context.`package`.preset(template.cycle, template.hazardClass.orEmpty()) != null)
            NovaText("İşyerine özgü konular sertifikanın arka yüzünde gösterilir.", style = NovaTypeToken.metaQuiet)
    }
}

@Composable
private fun EditorIconButton(symbol: String, description: String, enabled: Boolean, onClick: () -> Unit) {
    Box(Modifier.size(36.dp).clip(CircleShape).novaRowPress(enabled = enabled, onClick = onClick).semantics { contentDescription = description },
        contentAlignment = Alignment.Center) {
        NovaIcon(symbol, 22.dp, tint = if (enabled) NovaColorToken.accentInk.color() else NovaColorToken.textMuted.color())
    }
}

/** One topic: included or not, its title where the expert names it, and minutes in ten-minute steps or a quick pick. */
@Composable
private fun TopicEditor(topic: NovaEducationTopic, removable: Boolean, defaultMinutes: Int, enabled: Boolean,
                        onChange: (NovaEducationTopic) -> Unit, onRemove: () -> Unit) {
    val included = topic.instructionMinutes > 0
    var quick by remember { mutableStateOf(false) }
    val ink = NovaColorToken.text.color()
    Column(Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
            Box(Modifier.size(32.dp).clip(RoundedCornerShape(8.dp)).novaRowPress(enabled = enabled) {
                onChange(topic.copy(instructionMinutes = if (included) 0 else if (defaultMinutes > 0) defaultMinutes else 30))
            }.semantics { contentDescription = "Bu konu bu eğitimde işlendi"; role = Role.Checkbox; selected = included }, contentAlignment = Alignment.Center) {
                NovaIcon(if (included) "checkmark.square.fill" else "square", 18.dp,
                    tint = if (included) NovaColorToken.accentInk.color() else NovaColorToken.textSecondary.color())
            }
            if (topic.group == "G4" || topic.parentCode != null || topic.code.startsWith("CUSTOM"))
                NovaTextField("Konu başlığı", topic.title, { onChange(topic.copy(title = it)) }, Modifier.weight(1f), multiline = true, enabled = enabled)
            else NovaText(topic.title, Modifier.weight(1f).padding(top = 6.dp))
            if (removable && enabled) Box(Modifier.size(32.dp).clip(CircleShape).novaRowPress(onClick = onRemove).semantics { contentDescription = "Kaldır" },
                contentAlignment = Alignment.Center) { NovaIcon("trash", 13.dp, tint = NovaColorToken.statusDangerInk.color()) }
        }
        Row(Modifier.padding(start = 30.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            EditorIconButton("minus.circle", "10 dakika azalt", enabled) { onChange(topic.copy(instructionMinutes = maxOf(0, topic.instructionMinutes - 10))) }
            BasicTextField(if (topic.instructionMinutes == 0) "" else topic.instructionMinutes.toString(), { text ->
                onChange(topic.copy(instructionMinutes = text.filter(Char::isDigit).take(4).toIntOrNull() ?: 0))
            }, Modifier.width(52.dp).background(NovaColorToken.surface.color(), RoundedCornerShape(8.dp))
                .border(1.dp, NovaColorToken.borderMuted.color(), RoundedCornerShape(8.dp)).padding(vertical = 6.dp)
                .semantics { contentDescription = "Dakika" }, enabled = enabled, singleLine = true,
                textStyle = novaTextStyle(NovaTypeToken.body).copy(color = ink, textAlign = androidx.compose.ui.text.style.TextAlign.Center),
                cursorBrush = SolidColor(ink), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
            NovaText("dk", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            EditorIconButton("plus.circle", "10 dakika artır", enabled) { onChange(topic.copy(instructionMinutes = topic.instructionMinutes + 10)) }
            Spacer(Modifier.weight(1f))
            NovaText("Hızlı seç", Modifier.novaRowPress(enabled = enabled) { quick = !quick }.padding(vertical = 8.dp), NovaTypeToken.meta,
                color = NovaColorToken.accentInk.color())
        }
        if (quick) Row(Modifier.padding(start = 30.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf(10, 20, 30, 40, 60).forEach { minutes ->
                NovaChoiceChip("$minutes dk", topic.instructionMinutes == minutes) { onChange(topic.copy(instructionMinutes = minutes)); quick = false }
            }
        }
    }
}

/** The start–end of one day, breaks included, from the lessons already placed on it. */
private fun dayRange(model: EducationEditorModel, day: NovaEducationDay): String? {
    val key = NovaEducationClock.day(day.instant)
    val lessons = model.template.lessons.filter { lesson -> NovaEducationClock.date(lesson.startsAt)?.let(NovaEducationClock::day) == key }.sortedBy { it.startsAt }
    val start = lessons.firstOrNull()?.let { NovaEducationClock.date(it.startsAt) } ?: return null
    val last = lessons.last()
    val end = NovaEducationClock.date(last.startsAt)?.plusSeconds((last.instructionMinutes + last.breakMinutes) * 60L) ?: return null
    val format = DateTimeFormatter.ofPattern("HH:mm").withZone(NovaEducationClock.zone)
    return "${format.format(start)} – ${format.format(end)}"
}

/** Each 45 + 15-minute lesson unit belongs to one editable day; the standard 16-unit profile starts as two eight-hour days. */
@Composable
private fun ScheduleStep(model: EducationEditorModel, canWrite: Boolean) {
    val needed = model.neededDays
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        NovaText("Önerilen plan: $needed gün. Gün, başlangıç saati ve günlük ders süresi değiştirilebilir.", style = NovaTypeToken.metaQuiet)
        if (model.days.size != needed && canWrite) NovaButton("Önerilen $needed güne dön", { model.resetRecommendedDays() },
            variant = NovaButtonVariant.Surface, symbol = "arrow.counterclockwise", compact = true)
        model.days.forEachIndexed { index, day ->
            val local = day.instant.atZone(NovaEducationClock.zone)
            fun update(value: NovaEducationDay) { if (canWrite) model.changeDays(model.days.map { if (it.id == day.id) value else it }) }
            Column(Modifier.fillMaxWidth().background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(12.dp)).padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaDayField("Eğitim günü", local.toLocalDate().toString(), { picked ->
                    NovaDay.parse(picked)?.takeIf { !it.isAfter(java.time.LocalDate.now(NovaEducationClock.zone)) }?.let {
                        update(day.at(it.atTime(local.toLocalTime()).atZone(NovaEducationClock.zone).toInstant()))
                    }
                }, "education.day.$index.date")
                NovaTimeField("Başlangıç saati", local.toLocalTime().withSecond(0).withNano(0), "education.day.$index.time") { time: LocalTime ->
                    update(day.at(local.toLocalDate().atTime(time).atZone(NovaEducationClock.zone).toInstant()))
                }
                if (model.basic) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaText("Günlük eğitim: ${day.lessonCount} saat (molalar dahil)", Modifier.weight(1f), NovaTypeToken.bodyStrong)
                    EditorIconButton("minus.circle", "Bir saat azalt", canWrite && day.lessonCount > 1) { update(day.copy(lessonCount = day.lessonCount - 1)) }
                    EditorIconButton("plus.circle", "Bir saat artır", canWrite && day.lessonCount < 8) { update(day.copy(lessonCount = day.lessonCount + 1)) }
                }
                dayRange(model, day)?.let { NovaText("Hesaplanan saat: $it (molalar dahil)", style = NovaTypeToken.bodyStrong) }
                if (model.days.size > needed && canWrite) NovaButton("Bu günü kaldır", {
                    model.days = model.days.filterNot { it.id == day.id }; model.rebalance()
                }, variant = NovaButtonVariant.Danger, symbol = "trash", compact = true)
            }
        }
        if (model.basic && model.days.size < model.units && canWrite) NovaButton("Gün ekle", {
            val last = model.days.lastOrNull()?.instant ?: Instant.now()
            model.days = model.days + NovaEducationDay.of(last.plus(1, ChronoUnit.DAYS), 1); model.rebalance()
        }, variant = NovaButtonVariant.Surface, symbol = "calendar.badge.plus", compact = true)
        NovaText("Toplam: ${duration(model.template.net + model.units * (if (model.basic) 15 else 0))} (mola dahil)", style = NovaTypeToken.meta,
            color = NovaColorToken.textSecondary.color())
        if (!model.distributionValid) NovaText("Günlere dağıtılan toplam ${model.days.sumOf { it.lessonCount }} saat; bu eğitim için ${model.units} saat olmalı. " +
            "Günlük süreleri veya tarihleri kontrol edin.", style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color())
        if (!model.endsInPast) NovaText("Eğitimin bitiş saati henüz gelmemiş görünüyor. Gerçekleşen eğitim kaydı için gün ve başlangıç saatini kontrol edin.",
            style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color())
        NovaTextField("Eğitim yeri / online bağlantı (isteğe bağlı)", model.template.location, { model.applyTemplate(model.template.copy(location = it)) },
            identifier = "education.location", enabled = canWrite)
    }
}

@Composable
private fun TrainersStep(model: EducationEditorModel, userName: String, canWrite: Boolean) {
    val trainers = model.draft.trainers
    var editing by remember { mutableStateOf<String?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (canWrite && userName.isNotBlank() && trainers.none { it.name == userName }) NovaButton("Ben eğiticiyim", {
            // A blank add row is replaced rather than left behind as an unnamed trainer.
            model.setTrainers(trainers.filterNot { it.name.isBlank() && it.title.isBlank() } + NovaEducationTrainer(name = userName))
            model.advanceIfComplete(NovaEducationStep.trainers)
        }, Modifier.testTag("education.trainer.me"), variant = NovaButtonVariant.Surface, symbol = "person.crop.circle.badge.checkmark", compact = true)
        trainers.forEachIndexed { index, trainer ->
            fun update(value: NovaEducationTrainer) = model.setTrainers(trainers.toMutableList().also { it[index] = value })
            NovaCard(Modifier.fillMaxWidth(), padding = 10) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            NovaText(trainer.name.ifEmpty { "Yeni eğitici" }, style = NovaTypeToken.bodyStrong)
                            if (trainer.title.isNotEmpty()) NovaText(trainer.title, style = NovaTypeToken.metaQuiet)
                        }
                        if (canWrite) NovaText(if (editing == trainer.id) "Bitti" else "Düzenle",
                            Modifier.novaRowPress { editing = if (editing == trainer.id) null else trainer.id }.testTag("education.trainer.edit.$index")
                                .padding(vertical = 8.dp), NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
                    }
                    if (editing == trainer.id || trainer.name.isEmpty()) {
                        NovaTextField("Eğitici adı soyadı", trainer.name, { update(trainer.copy(name = it)) }, identifier = "education.trainer.name.$index", enabled = canWrite)
                        NovaTextField("Unvan / belge bilgisi", trainer.title, { update(trainer.copy(title = it)) }, identifier = "education.trainer.title.$index",
                            enabled = canWrite)
                    }
                    if (canWrite) NovaButton("Eğiticiyi kaldır", { if (editing == trainer.id) editing = null; model.removeTrainer(trainer.id) },
                        Modifier.testTag("education.trainer.remove.$index"), variant = NovaButtonVariant.Danger, compact = true)
                }
            }
        }
        if (canWrite) NovaButton("Eğitici ekle", {
            val trainer = NovaEducationTrainer()
            model.setTrainers(trainers + trainer); editing = trainer.id
        }, variant = NovaButtonVariant.Surface, symbol = "plus", compact = true)
    }
}

@Composable
private fun ParticipantsStep(model: EducationEditorModel, canWrite: Boolean, editingSaved: Boolean, onEdit: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        NovaText("Her firma/işyeri seçiminden en az bir katılımcı seçin. Aynı kişi eğitimde bir kez yer alabilir.", style = NovaTypeToken.metaQuiet)
        summary(model, NovaEducationStep.participants)?.let { NovaText(it, style = NovaTypeToken.bodyStrong) }
        // A saved training lists who attended per company, so one person can be taken out directly.
        if (editingSaved) model.draft.scopes.forEachIndexed { index, scope ->
            val place = scope.workplaceName ?: scope.companyName ?: "Firma"
            if (scope.participants.isNotEmpty()) NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    NovaText(place, style = NovaTypeToken.bodyStrong)
                    scope.participants.forEach { person ->
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                            NovaIcon("person.crop.circle", 16.dp, tint = NovaColorToken.accentInk.color())
                            NovaText(person.name ?: "Personel", Modifier.weight(1f))
                            if (canWrite) NovaText("Çıkar", Modifier.novaRowPress { model.removeParticipant(index, person.id) }
                                .testTag("education.participant.remove.${person.id}"), NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color())
                        }
                    }
                }
            } else NovaHelpHint("$place için katılımcı kalmadı. Yeni bir kişi seçin veya bu firma/işyerini eğitimden kaldırın.")
        }
        NovaButton("Katılımcıları düzenle", onEdit, Modifier.testTag("education.participants.open"), variant = NovaButtonVariant.Surface,
            enabled = canWrite && model.draft.scopes.isNotEmpty(), symbol = "person.3")
    }
}

/** Every chosen company's people on one page, filterable by company, department and job. */
@Composable
private fun ParticipantsPicker(model: EducationEditorModel, onDone: () -> Unit) {
    BackHandler(onBack = onDone)
    var company by remember { mutableStateOf<String?>(null) }
    var search by remember { mutableStateOf("") }
    var department by remember { mutableStateOf("") }
    var job by remember { mutableStateOf("") }
    var selectedOnly by remember { mutableStateOf(false) }
    val scopes = model.draft.scopes
    val companyIds = scopes.map { it.companyId.lowercase() }.distinct()
        .sortedBy { id -> scopes.firstOrNull { it.companyId.sameId(id) }?.companyName.orEmpty() }
    val candidates = scopes.indices.filter { company == null || scopes[it].companyId.sameId(company) }
        .flatMap { index -> model.people[scopes[index].companyId.lowercase()].orEmpty().map { index to it } }
    val departments = candidates.mapNotNull { it.second.department }.distinct().sorted()
    val jobs = candidates.mapNotNull { it.second.jobTitle }.distinct().sorted()
    val matches = candidates.filter { (index, person) ->
        (search.isBlank() || person.name.contains(search.trim(), true)) && (department.isEmpty() || person.department == department) &&
            (job.isEmpty() || person.jobTitle == job) && (!selectedOnly || model.isSelected(index, person))
    }
    fun pickCompany(value: String?) { company = value; department = ""; job = "" }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            NovaText("Katılımcılar", Modifier.weight(1f), NovaTypeToken.screenTitle)
            NovaButton("Bitti", onDone, variant = NovaButtonVariant.Surface, compact = true)
        }
        NovaText("Eğitimdeki tüm firmaların personeli gösteriliyor. İsterseniz firmaya göre filtreleyin.", style = NovaTypeToken.metaQuiet)
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaChoiceChip("Tüm firmalar", company == null) { pickCompany(null) }
            companyIds.forEach { id ->
                NovaChoiceChip(scopes.firstOrNull { it.companyId.sameId(id) }?.companyName ?: "Firma", company?.sameId(id) == true) { pickCompany(id) }
            }
        }
        NovaSearchCapsule(search, "Personel ara", "education.participants.search") { search = it }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaFilterField("Departman", listOf(NovaChooserOption(null, "Tümü")) + departments.map { NovaChooserOption(it, it) }, department.ifEmpty { null },
                "education.participants.department", Modifier.weight(1f)) { department = it.orEmpty() }
            NovaFilterField("Görev", listOf(NovaChooserOption(null, "Tümü")) + jobs.map { NovaChooserOption(it, it) }, job.ifEmpty { null },
                "education.participants.job", Modifier.weight(1f)) { job = it.orEmpty() }
        }
        Row(Modifier.padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.novaRowPress { selectedOnly = !selectedOnly }.testTag("education.participants.selectedonly").padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon(if (selectedOnly) "checkmark.circle.fill" else "circle", 14.dp, tint = NovaColorToken.accentInk.color())
                NovaText("Yalnız seçilenler", style = NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
            }
            Spacer(Modifier.weight(1f))
            NovaText("Görünenlerin tümünü seç", Modifier.novaRowPress { matches.forEach { (index, person) -> model.setSelected(index, person, true) } }
                .testTag("education.participants.selectall").padding(vertical = 8.dp), NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
        }
        if (matches.isEmpty()) NovaText("Eşleşen personel bulunamadı.", style = NovaTypeToken.metaQuiet)
        matches.forEach { (index, person) -> ParticipantRow(model, index, person) }
        NovaButton("${model.draft.scopes.sumOf { it.participants.size }} kişiyi ekle", onDone, Modifier.fillMaxWidth().testTag("education.participants.done"),
            symbol = "checkmark")
    }
}

@Composable
private fun ParticipantRow(model: EducationEditorModel, index: Int, person: NovaPersonOption) {
    val scopes = model.draft.scopes
    val on = model.isSelected(index, person)
    val elsewhere = scopes.withIndex().any { (other, scope) -> other != index && scope.participants.any { it.id.sameId(person.id) } }
    val scope = scopes[index]
    NovaCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).alpha(if (elsewhere) 0.45f else 1f)
        .novaRowPress(enabled = !elsewhere) { model.setSelected(index, person, !on) }
        .testTag("education.person.${person.id}").semantics { role = Role.Checkbox; selected = on }, padding = 14) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon(if (on) "checkmark.circle.fill" else "circle", 23.dp, tint = if (on) NovaColorToken.accent.color() else NovaColorToken.textSecondary.color())
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                NovaText(person.name, style = NovaTypeToken.bodyStrong)
                NovaText(listOfNotNull(scope.companyName, scope.workplaceName, person.department, person.jobTitle).joinToString(" · "),
                    style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            }
        }
    }
}

/** The explicit last checkpoint: what will be written, each line one tap from its section. */
@Composable
private fun ReviewStep(model: EducationEditorModel) {
    val draft = model.draft
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        NovaText("Kaydetmeden önce kontrol edin", style = NovaTypeToken.sectionTitle)
        NovaCard(Modifier.fillMaxWidth(), padding = 12) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(
                    Triple("Eğitim", draft.title.ifEmpty { model.template.cycleName }, NovaEducationStep.info),
                    Triple("Toplam süre", duration(model.template.net + model.template.breakTotal), NovaEducationStep.topics),
                    Triple("Gün sayısı", "${model.days.size} gün", NovaEducationStep.schedule),
                    Triple("Eğiticiler", "${draft.trainers.count { it.name.isNotBlank() }} kişi", NovaEducationStep.trainers),
                    Triple("Katılımcılar", "${draft.scopes.sumOf { it.participants.size }} kişi", NovaEducationStep.participants),
                    Triple("Firma / işyeri", draft.scopes.joinToString(", ") { listOfNotNull(it.companyName, it.workplaceName).joinToString(" · ") },
                        NovaEducationStep.companies),
                ).forEach { (label, value, step) ->
                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            NovaText(label, Modifier.weight(1f), NovaTypeToken.metaQuiet)
                            NovaText("Düzenle", Modifier.novaRowPress { model.returningToReview = true; model.step = step }
                                .testTag("education.review.edit.${step.name}").padding(vertical = 6.dp), NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
                        }
                        NovaText(value.ifEmpty { "Belirtilmedi" }, style = NovaTypeToken.bodyStrong)
                    }
                }
            }
        }
        NovaText("Bu özet onaylandığında eğitim kaydı ve kişi bazlı katılım bilgisi oluşturulur.", style = NovaTypeToken.metaQuiet)
    }
}
