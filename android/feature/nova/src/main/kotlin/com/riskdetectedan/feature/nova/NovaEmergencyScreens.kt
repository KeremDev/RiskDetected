package com.riskdetectedan.feature.nova

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.launch

/** One active employee of a company, offered as a name to copy into a snapshot. */
data class NovaPersonOption(val id: String, val name: String)

/** The module's calls bound to one identity (iOS `NovaEmergencyClient`); the design preview supplies its own. */
interface NovaEmergencyClient {
    val companies: suspend () -> List<NovaCompanyOption>
    val files: NovaFileClient
    /** Active personnel of a company; a chosen name is copied into the plan's team snapshot. */
    suspend fun employees(company: String): List<NovaPersonOption>
    suspend fun catalogue(company: String?): NovaEmergencyCatalogue
    suspend fun board(query: NovaEmergencyQuery): NovaEmergencyBoard
    suspend fun detail(id: String): NovaEmergencyPlan
    suspend fun publish(company: String, draft: NovaEmergencyPlanDraft): NovaEmergencyPlan?
    /** Reopens a published plan for correction or removal; absent where records are not editable. */
    val manage: NovaModuleManage? get() = null
}

class NovaServiceEmergencyClient(private val service: NovaEmergencyService, private val identity: IsgWorkspaceIdentity,
                                 override val companies: suspend () -> List<NovaCompanyOption>, override val files: NovaFileClient,
                                 private val people: suspend (String) -> List<NovaPersonOption>,
                                 override val manage: NovaModuleManage? = null) : NovaEmergencyClient {
    override suspend fun employees(company: String) = people(company)
    override suspend fun catalogue(company: String?) = service.catalogue(identity, company)
    override suspend fun board(query: NovaEmergencyQuery) = service.board(identity, query)
    override suspend fun detail(id: String) = service.detail(identity, id)
    override suspend fun publish(company: String, draft: NovaEmergencyPlanDraft) = service.publish(identity, company, draft)
}

internal fun emergencyMessage(error: Throwable) = (error as? NovaEmergencyException)?.failure?.message ?: NovaEmergencyFailure.unavailable.message

private fun NovaEmergencyGroup.status() = when (this) {
    NovaEmergencyGroup.expired -> NovaStatus.Danger; NovaEmergencyGroup.untracked -> NovaStatus.Warning
    NovaEmergencyGroup.dueSoon -> NovaStatus.Info; NovaEmergencyGroup.current -> NovaStatus.Success
}

@Composable
private fun EmergencyFact(symbol: String, label: String, value: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 10.dp, tint = NovaColorToken.textMuted.color())
        Column {
            NovaSizedText(label, 9f, FontWeight.Medium, NovaColorToken.textMuted.color())
            NovaSizedText(value, 11f, FontWeight.Bold)
        }
    }
}

@Composable
private fun EmergencyPlanCard(plan: NovaEmergencyPlan, modifier: Modifier, onClick: () -> Unit) {
    NovaCard(modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onClick).testTag("nova.emergency.row.${plan.id}"), padding = 14) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(plan.scope, style = NovaTypeToken.cardTitle)
                    NovaText(listOfNotNull(plan.workplaceName, plan.companyName).distinct().joinToString(" · "), style = NovaTypeToken.meta,
                        color = NovaColorToken.textSecondary.color())
                }
                NovaStatusPill(plan.state.title, plan.group.status())
            }
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                EmergencyFact("calendar", "Hazırlanma", NovaDay.label(plan.preparedOn))
                plan.validUntil?.let { EmergencyFact("calendar.badge.clock", "Geçerlilik", NovaDay.label(it)) }
                EmergencyFact("person.2", "Ekip", "${plan.teamSize}")
                EmergencyFact("number", "Sürüm", "v${plan.version}")
            }
        }
    }
}

/** Acil Durum Planları (iOS `NovaEmergencyPlanScreen`). */
@Composable
fun NovaEmergencyScreen(client: NovaEmergencyClient, canWrite: Boolean, onBack: () -> Unit, initialCompany: String? = null,
                        headingOverride: String? = null, startInAddMode: Boolean = false) {
    val coroutines = rememberCoroutineScope()
    var board by remember { mutableStateOf<NovaEmergencyBoard?>(null) }
    var catalogue by remember { mutableStateOf<NovaEmergencyCatalogue?>(null) }
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var query by remember { mutableStateOf(NovaEmergencyQuery(company = initialCompany)) }
    var loading by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    var chooser by remember { mutableStateOf<String?>(null) }
    var detail by remember { mutableStateOf<NovaEmergencyPlan?>(null) }
    var drafting by remember { mutableStateOf<NovaEmergencyPlanDraft?>(null) }
    var draftCompany by remember { mutableStateOf<String?>(null) }
    // A draft the expert set aside; it is never published and never listed.
    var savedDraft by remember { mutableStateOf<NovaEmergencyPlanDraft?>(null) }
    suspend fun load(reset: Boolean) {
        query = if (reset) query.copy(offset = 0) else query.copy(offset = query.offset + query.limit)
        loading = true; failure = null
        try {
            if (companies.isEmpty()) companies = client.companies()
            catalogue = client.catalogue(query.company)
            val answer = client.board(query)
            val existing = board
            board = if (reset || existing == null) answer else answer.copy(rows = existing.rows + answer.rows)
        } catch (error: Exception) { failure = emergencyMessage(error) }
        loading = false
    }
    fun reload() = coroutines.launch { load(true) }
    suspend fun publish(draft: NovaEmergencyPlanDraft): String? {
        val company = draftCompany ?: query.company ?: return NovaEmergencyFailure.validation.message
        return try { client.publish(company, draft); savedDraft = null; load(true); null } catch (error: Exception) { emergencyMessage(error) }
    }
    val closeAdd: () -> Unit = { if (startInAddMode) onBack() else drafting = null }
    val current = drafting
    if (startInAddMode || (current != null && current.planId == null)) {
        val draft = current ?: savedDraft ?: NovaEmergencyPlanDraft(preparedOn = NovaDay.today())
        NovaCompanyCreateFlow("Acil durum planı ekle", client.companies, { company -> client.catalogue(company) }, initialCompany, closeAdd) { selected, company ->
            LaunchedEffect(company) { draftCompany = company }
            EmergencyPlanSheet(draft, selected, client, company, onSave = { publish(it) },
                onSaveDraft = { savedDraft = it; closeAdd() }, onClose = closeAdd)
        }
        return
    }
    if (current != null) {
        EmergencyPlanSheet(current, catalogue, client, draftCompany, onSave = { publish(it) },
            onSaveDraft = { savedDraft = it; drafting = null }, onClose = { drafting = null })
        return
    }
    LaunchedEffect(Unit) { load(true) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaListHeading(headingOverride ?: NovaDestination.emergencyPlans.title, onBack) {
            if (canWrite) NovaButton("Plan Ekle", {
                draftCompany = null; drafting = savedDraft ?: NovaEmergencyPlanDraft(preparedOn = NovaDay.today())
            }, symbol = "plus", compact = true)
        }
        NovaHelpHint("Firmanın acil durum planını ve dosyasını ekleyin; geçerlilik tarihini buradan takip edin.")
        board?.let { shown ->
            val columns = if (novaFontScaleIsAccessibility()) 2 else 4
            NovaEmergencyGroup.entries.chunked(columns).forEach { chunk ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    chunk.forEach { group ->
                        NovaListStat(group.title, group.symbol, shown.count(group), Modifier.weight(1f).testTag("nova.emergency.stat.${group.wire}"),
                            selected = query.state == group.wire) {
                            query = query.copy(state = if (query.state == group.wire) null else group.wire); reload()
                        }
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaChooserButton("Firma", companies.firstOrNull { it.id == query.company }?.name ?: "Tüm firmalar", "nova.emergency.chooser.company",
                Modifier.weight(1f), open = chooser == "company") { chooser = if (chooser == "company") null else "company" }
            val stateTitle = query.state?.let { value -> NovaEmergencyGroup.ofWire(value)?.title ?: NovaEmergencyState.of(value)?.title } ?: "Tüm durumlar"
            NovaChooserButton("Durum", stateTitle, "nova.emergency.chooser.state", Modifier.weight(1f), open = chooser == "state") {
                chooser = if (chooser == "state") null else "state"
            }
        }
        if (chooser == "company") NovaChooserPanel((if (initialCompany == null) listOf(NovaChooserOption(null, "Tüm firmalar")) else emptyList()) +
            companies.filter { initialCompany == null || it.id == initialCompany }.map { NovaChooserOption(it.id, it.name) },
            query.company, "nova.emergency.panel.company") { query = query.copy(company = it); chooser = null; reload() }
        if (chooser == "state") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm durumlar")) +
            NovaEmergencyGroup.entries.map { NovaChooserOption(it.wire, it.title, board?.count(it), it.symbol) } +
            NovaEmergencyState.entries.filter { state -> NovaEmergencyGroup.entries.none { it.wire == state.wire } }
                .map { NovaChooserOption(it.wire, it.title, board?.counts?.get(it.wire)) }, query.state, "nova.emergency.panel.state") {
            query = query.copy(state = it); chooser = null; reload()
        }
        NovaSearchCapsule(query.search, "Kapsam, işyeri veya firma ara", "nova.emergency.search") { query = query.copy(search = it) }
        LaunchedEffect(query.search) { if (board != null) { kotlinx.coroutines.delay(350); load(true) } }
        val shown = board
        when {
            loading && shown == null -> Box(Modifier.fillMaxWidth().padding(vertical = 30.dp), contentAlignment = Alignment.Center) {
                NovaSpinner(NovaColorToken.text.color(), size = 24.dp)
            }
            failure != null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText(failure!!, color = NovaColorToken.statusDangerInk.color()) }
            shown != null && shown.rows.isEmpty() -> NovaEmptyState("Henüz acil durum planı yok",
                "Plan ekleyerek ekibi, dosyayı ve geçerlilik tarihini dijital ortamda takip edebilirsiniz.")
            shown != null -> NovaListEntrance(true) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    shown.rows.forEachIndexed { index, plan ->
                        EmergencyPlanCard(plan, Modifier.novaRowEntrance(index)) {
                            coroutines.launch {
                                draftCompany = plan.companyId
                                try { catalogue = client.catalogue(plan.companyId); detail = client.detail(plan.id) }
                                catch (_: Exception) { failure = "Kayıt açılamadı. Yeniden deneyin." }
                            }
                        }
                    }
                    NovaText("${shown.rows.size} / ${shown.total} plan", style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
                    if (shown.hasMore) NovaButton("Daha fazla göster", { coroutines.launch { load(false) } }, variant = NovaButtonVariant.Surface,
                        symbol = "chevron.down")
                }
            }
        }
    }
    val open = detail
    NovaPopup(open != null, { detail = null }, identifier = "nova.emergency.detail") {
        if (open != null) {
            EmergencyDetail(open, canWrite, { bucket, path -> client.files.download(bucket, path) }) {
                detail = null; draftCompany = open.companyId
                drafting = NovaEmergencyPlanDraft(open.id, open.workplaceId, open.scope, NovaDay.today(), team = open.team, assetId = open.assetId)
            }
            val manage = client.manage
            val company = open.companyId
            if (canWrite && manage != null && company != null) Box(Modifier.padding(horizontal = 12.dp, vertical = 12.dp)) {
                NovaModuleManageAction(manage, "emergency_plan", company, open.id) { detail = null; coroutines.launch { load(true) } }
            }
        }
    }
}

@Composable
private fun EmergencyTeam(members: List<NovaEmergencyMember>, title: String) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        NovaText(title, style = NovaTypeToken.cardTitle)
        members.forEach { member ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon(member.role.symbol, 12.dp, tint = NovaColorToken.textMuted.color())
                Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    NovaText(member.fullName)
                    NovaSizedText(member.role.title + (member.contact?.let { " · $it" } ?: ""), 10.5f, FontWeight.Medium, NovaColorToken.textSecondary.color())
                }
            }
        }
    }
}

@Composable
private fun EmergencyCell(symbol: String, label: String, value: String, modifier: Modifier, detail: String = "") {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        NovaIcon(symbol, 11.dp, Modifier.padding(top = 2.dp), tint = NovaColorToken.textMuted.color())
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            NovaSizedText(label, 9f, FontWeight.Medium, NovaColorToken.textMuted.color())
            NovaSizedText(value, 12f, FontWeight.Bold)
            if (detail.isNotEmpty()) NovaSizedText(detail, 9.5f, FontWeight.Medium, NovaColorToken.textSecondary.color())
        }
    }
}

/** One plan: the version that stands and every version behind it; nothing here edits a published version. */
@Composable
private fun EmergencyDetail(plan: NovaEmergencyPlan, canWrite: Boolean, download: suspend (String, String) -> ByteArray, onRenew: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val context = LocalContext.current
    var opening by remember { mutableStateOf(false) }
    var openFailure by remember { mutableStateOf<String?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            NovaPopupHeading(plan.scope, symbol = "shield")
            NovaText(listOfNotNull(plan.workplaceName, plan.companyName).joinToString(" · "), style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            NovaText(plan.explain, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    EmergencyCell("calendar", "Hazırlanma", NovaDay.label(plan.preparedOn), Modifier.weight(1f))
                    EmergencyCell("calendar.badge.clock", "Geçerlilik", plan.validUntil?.let(NovaDay::label) ?: "Belirtilmedi", Modifier.weight(1f), "uzmanın kararı")
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    EmergencyCell("number", "Sürüm", "v${plan.version}", Modifier.weight(1f), "${plan.versionsTotal} sürüm")
                    EmergencyCell("person.2", "Ekip", "${plan.teamSize}", Modifier.weight(1f))
                }
            }
        }
        val asset = plan.assetDownload
        if (asset != null) NovaCard(Modifier.fillMaxWidth(), padding = 12) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("doc.fill", 14.dp, tint = NovaColorToken.statusSuccessInk.color())
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    NovaText("Dosya ekli", style = NovaTypeToken.cardTitle)
                    openFailure?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
                }
                NovaButton("Dosyayı aç", {
                    opening = true; openFailure = null
                    coroutines.launch {
                        try {
                            val bytes = download(asset.bucket, asset.path)
                            val name = asset.path.substringAfterLast('/').ifEmpty { "belge" }
                            novaShareFile(context, bytes, name, android.webkit.MimeTypeMap.getSingleton()
                                .getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase()) ?: "application/octet-stream")
                        } catch (_: Exception) { openFailure = "Dosya servisi şu anda kullanılamıyor." }
                        opening = false
                    }
                }, Modifier.testTag("nova.emergency.detail.file.open"), variant = NovaButtonVariant.Surface, enabled = !opening, loading = opening,
                    symbol = "arrow.up.right.square", compact = true)
            }
        }
        EmergencyTeam(plan.team, "Ekip")
        if (canWrite) NovaButton("Yeni sürüm yayımla", onRenew, symbol = "arrow.triangle.2.circlepath")
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaText("Sürüm geçmişi", style = NovaTypeToken.cardTitle)
            // Each version keeps its own team, dates and scope; renewing never rewrote what came before.
            plan.versions.forEach { version ->
                NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            NovaText("v${version.version} · ${version.scope}", Modifier.weight(1f), NovaTypeToken.cardTitle)
                            NovaStatusPill(if (version.isActive) "Yürürlükte" else "Geçmiş", if (version.isActive) NovaStatus.Success else NovaStatus.Neutral)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            NovaSizedText("Hazırlanma: ${NovaDay.label(version.preparedOn)}", 10.5f, FontWeight.Medium)
                            version.validUntil?.let { NovaSizedText("Geçerlilik: ${NovaDay.label(it)}", 10.5f, FontWeight.Medium) }
                        }
                        if (version.needsReview) NovaTag("exclamationmark.circle", "Dayanağı yazılmamış · gözden geçirin", NovaStatus.Warning)
                        else version.reviewNote?.takeIf { it.isNotEmpty() }?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color()) }
                        EmergencyTeam(version.team, "Bu sürümün ekibi (${version.team.size})")
                    }
                }
            }
        }
    }
}

private enum class EmergencyStep(val title: String) {
    scope("Kapsam"), dates("Tarih ve geçerlilik"), team("Acil durum ekibi"), file("Plan dosyası"), review("Kontrol ve kaydet")
}

/** Publishing a plan or the next version of one, as a five-step task (iOS `NovaEmergencyPlanSheet`). */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
private fun EmergencyPlanSheet(initial: NovaEmergencyPlanDraft, catalogue: NovaEmergencyCatalogue?, client: NovaEmergencyClient, company: String?,
                               onSave: suspend (NovaEmergencyPlanDraft) -> String?, onSaveDraft: (NovaEmergencyPlanDraft) -> Unit, onClose: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val workplaces = catalogue?.workplaces.orEmpty()
    var draft by remember { mutableStateOf(if (initial.workplaceId == null && workplaces.size == 1) initial.copy(workplaceId = workplaces[0].id) else initial) }
    var step by remember { mutableStateOf(EmergencyStep.scope) }
    var failure by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    var didSave by remember { mutableStateOf(false) }
    var confirmingExit by remember { mutableStateOf(false) }
    var choosingWorkplace by remember { mutableStateOf(false) }
    var choosingPerson by remember { mutableStateOf(false) }
    var personnel by remember { mutableStateOf<List<NovaPersonOption>>(emptyList()) }
    var personnelLoading by remember { mutableStateOf(false) }
    var personnelFailure by remember { mutableStateOf<String?>(null) }
    var selectedPerson by remember { mutableStateOf<NovaPersonOption?>(null) }
    var memberRole by remember { mutableStateOf(NovaEmergencyRole.coordinator) }
    var memberContact by remember { mutableStateOf("") }
    val workplaceTitle = workplaces.firstOrNull { it.id == draft.workplaceId }?.name ?: "İşyeri seçin"
    val suggestedYears = workplaces.firstOrNull { it.id == draft.workplaceId }?.suggestedPeriodYears
    // Prefills once, never overwrites what the expert already set.
    LaunchedEffect(draft.workplaceId, draft.preparedOn) {
        val years = suggestedYears ?: return@LaunchedEffect
        val prepared = NovaDay.parse(draft.preparedOn) ?: return@LaunchedEffect
        if (draft.validUntil.isEmpty()) draft = draft.copy(validUntil = prepared.plusYears(years.toLong()).toString())
    }
    LaunchedEffect(company) {
        val chosen = company ?: return@LaunchedEffect
        personnelLoading = true; personnelFailure = null
        try {
            personnel = client.employees(chosen)
            if (personnel.isEmpty()) personnelFailure = "Bu firmada henüz aktif personel yok."
        } catch (_: Exception) { personnelFailure = "Firma personelleri yüklenemedi. Yeniden deneyin." }
        personnelLoading = false
    }
    if (didSave) {
        NovaTaskSuccessView("Acil durum planı kaydedildi",
            "Hazırlama: ${NovaDay.label(draft.preparedOn)}\nGeçerlilik: ${NovaDay.label(draft.validUntil)}\nEkip: ${draft.team.size} kişi\n\nSıradaki önerilen işlem: tatbikat kaydı oluştur.",
            "Planlara dön", onClose)
        return
    }
    androidx.activity.compose.BackHandler { confirmingExit = true }
    fun advance() {
        failure = null
        val valid = when (step) {
            EmergencyStep.scope -> draft.workplaceId != null
            EmergencyStep.dates -> {
                val prepared = NovaDay.parse(draft.preparedOn); val until = NovaDay.parse(draft.validUntil)
                prepared != null && until != null && until.isAfter(prepared)
            }
            else -> true
        }
        if (!valid) { failure = "Bu adımı tamamlamak için eksik bilgileri kontrol edin."; return }
        if (step == EmergencyStep.review) {
            if (saving) return
            coroutines.launch { saving = true; failure = onSave(draft); saving = false; if (failure == null) didSave = true }
            return
        }
        step = EmergencyStep.entries[step.ordinal + 1]
    }
    Column(Modifier.fillMaxSize().testTag("nova.emergency.form")) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 18.dp).padding(top = 8.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)) {
            NovaTaskHeader(if (draft.isRenewal) "Acil durum planını yenile" else "Acil durum planı ekle", step.ordinal + 1, EmergencyStep.entries.size,
                step.title) { confirmingExit = true }
            failure?.let { NovaTaskErrorSummary(it) }
            AnimatedContent(step, transitionSpec = { fadeIn(NovaMotion.easeInOut(0.2)) togetherWith fadeOut(NovaMotion.easeInOut(0.2)) }, label = "emergencyStep") { current ->
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    when (current) {
                        EmergencyStep.scope -> NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                            FieldIcon("building.2") {
                                when {
                                    draft.isRenewal || workplaces.size == 1 -> {
                                        NovaText("İşyeri", style = NovaTypeToken.label)
                                        NovaText(workplaceTitle, style = NovaTypeToken.cardTitle)
                                    }
                                    workplaces.isEmpty() -> NovaText("Bu firmada kayıt açılacak bir işyeri yok.", style = NovaTypeToken.metaQuiet)
                                    else -> {
                                        NovaChooserButton("İşyeri", workplaceTitle, "nova.emergency.form.workplace", open = choosingWorkplace) {
                                            choosingWorkplace = !choosingWorkplace
                                        }
                                        if (choosingWorkplace) NovaChooserPanel(workplaces.map { NovaChooserOption(it.id, it.name) }, draft.workplaceId,
                                            "nova.emergency.form.workplace.panel") { draft = draft.copy(workplaceId = it); choosingWorkplace = false }
                                    }
                                }
                            }
                        }
                        EmergencyStep.dates -> {
                            NovaDayField("Hazırlama tarihi", draft.preparedOn, { draft = draft.copy(preparedOn = it) }, "nova.emergency.form.prepared")
                            NovaDayField("Geçerlilik", draft.validUntil, { draft = draft.copy(validUntil = it) }, "nova.emergency.form.until",
                                clearable = true, symbol = "calendar.badge.clock")
                            suggestedYears?.let { years ->
                                NovaWhyDisclosure {
                                    NovaText("İşyerinin tehlike sınıfına göre $years yıl otomatik dolduruldu. Gerekirse değiştirebilirsiniz.", style = NovaTypeToken.metaQuiet)
                                }
                            }
                        }
                        EmergencyStep.team -> {
                            NovaText("Acil durum ekibi", style = NovaTypeToken.sectionTitle)
                            NovaHelpHint("Ekip eklemek isteğe bağlıdır. Şimdi kişi seçebilir veya bu adımı boş geçip ekibi daha sonra tamamlayabilirsiniz.")
                            NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                                FieldIcon("person.2") {
                                    NovaText("Ekip", style = NovaTypeToken.label)
                                    if (draft.team.isEmpty()) NovaText("En az bir kişi gerekli.", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                                    NovaChooserButton("Firma personeli", selectedPerson?.name ?: "Personel seçin", "nova.emergency.form.employee",
                                        symbol = "person", open = choosingPerson) { choosingPerson = !choosingPerson }
                                    if (choosingPerson) NovaChooserPanel(personnel.filter { person -> draft.team.none { it.fullName == person.name } }
                                        .map { NovaChooserOption(it.id, it.name) }, selectedPerson?.id, "nova.emergency.form.employee.options") { picked ->
                                        selectedPerson = personnel.firstOrNull { it.id == picked }; choosingPerson = false
                                    }
                                    if (personnelLoading) NovaSpinner(NovaColorToken.text.color())
                                    personnelFailure?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
                                    draft.team.forEach { member ->
                                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                            NovaIcon(member.role.symbol, 11.dp)
                                            NovaText("${member.fullName} · ${member.role.title}", Modifier.weight(1f), NovaTypeToken.meta)
                                            Box(Modifier.size(32.dp).novaRowPress { draft = draft.copy(team = draft.team.filter { it.key != member.key }) }
                                                .semantics { contentDescription = "Ekipten çıkar" }, contentAlignment = Alignment.Center) { NovaIcon("xmark.circle", 12.dp) }
                                        }
                                    }
                                    // Only the roles the schema knows, so the snapshot cannot carry one the server would refuse.
                                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        (catalogue?.roles?.ifEmpty { null } ?: NovaEmergencyRole.entries).forEach { role ->
                                            val on = memberRole == role
                                            Row(Modifier.clip(CircleShape).background(if (on) NovaColorToken.accent.color() else NovaColorToken.surfaceMuted.color(), CircleShape)
                                                .novaRowPress { memberRole = role }.padding(vertical = 7.dp, horizontal = 11.dp)
                                                .testTag("nova.emergency.form.role.${role.wire}").semantics { selected = on },
                                                horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                                                val ink = if (on) NovaColorToken.onInverse.color() else NovaColorToken.textSecondary.color()
                                                NovaIcon(role.symbol, 10.dp, tint = ink)
                                                NovaSizedText(role.title, 11f, if (on) FontWeight.Bold else FontWeight.Medium, ink)
                                            }
                                        }
                                    }
                                    NovaTextField("İletişim (isteğe bağlı)", memberContact, { memberContact = it }, identifier = "nova.emergency.form.contact")
                                    NovaButton("Ekibe ekle", {
                                        val name = selectedPerson?.name?.trim().orEmpty()
                                        if (name.isNotEmpty() && draft.team.size < 200) {
                                            draft = draft.copy(team = draft.team + NovaEmergencyMember(name, memberRole, memberContact.trim().ifEmpty { null }))
                                            memberContact = ""; selectedPerson = null
                                        }
                                    }, variant = NovaButtonVariant.Surface, symbol = "person.badge.plus", enabled = selectedPerson != null)
                                }
                            }
                        }
                        EmergencyStep.file -> {
                            NovaText("Plan dosyası", style = NovaTypeToken.sectionTitle)
                            NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                                FieldIcon("paperclip") {
                                    NovaText("Dosya", style = NovaTypeToken.label)
                                    if (company != null) NovaInlineFileField("emergency_plan", company, client.files, draft.assetId.orEmpty(),
                                        { draft = draft.copy(assetId = it.ifEmpty { null }) })
                                }
                            }
                            NovaWhyDisclosure("Dosya bilgileri") {
                                NovaText("Dosya eklemek zorunlu değil; planı kaydedip belgeyi daha sonra bağlayabilirsiniz.", style = NovaTypeToken.metaQuiet)
                            }
                        }
                        EmergencyStep.review -> {
                            NovaText("Kaydetmeden önce kontrol edin", style = NovaTypeToken.sectionTitle)
                            NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    ReviewRow("İşyeri", workplaceTitle)
                                    ReviewRow("Hazırlama", NovaDay.label(draft.preparedOn))
                                    ReviewRow("Geçerlilik", NovaDay.label(draft.validUntil))
                                    ReviewRow("Ekip", "${draft.team.size} kişi")
                                    ReviewRow("Dosya", if (draft.assetId == null) "Daha sonra eklenebilir" else "Dosya eklendi")
                                }
                            }
                            NovaButton("Taslak olarak kaydet", { onSaveDraft(draft) }, Modifier.testTag("nova.emergency.form.save-draft"),
                                variant = NovaButtonVariant.Surface, symbol = "tray.and.arrow.down")
                            NovaText("Taslak yayımlanmaz ve plan listesinde görünmez; daha sonra bu bilgilerle devam edebilirsiniz.", style = NovaTypeToken.metaQuiet)
                        }
                    }
                }
            }
        }
        NovaTaskStickyActions(if (step == EmergencyStep.review) "Yayımla" else "Devam", onBack = {
            failure = null; if (step.ordinal > 0) step = EmergencyStep.entries[step.ordinal - 1]
        }, onPrimary = ::advance, modifier = Modifier.navigationBarsPadding().padding(bottom = novaTabBarClearance),
            primarySymbol = if (step == EmergencyStep.review) "checkmark.seal" else "arrow.right", working = saving,
            canGoBack = step != EmergencyStep.scope)
    }
    NovaPopup(confirmingExit, { confirmingExit = false }) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            NovaPopupHeading("Acil durum planı akışından çıkılsın mı?", symbol = "exclamationmark.triangle")
            NovaText("Henüz kaydedilmemiş bilgiler silinir.")
            NovaButton("Çık", { confirmingExit = false; onClose() }, variant = NovaButtonVariant.Danger)
            NovaButton("Devam et", { confirmingExit = false }, variant = NovaButtonVariant.Surface)
        }
    }
}

/** A plain line icon in front of one field group, matching the rest of the forms. */
@Composable
internal fun FieldIcon(symbol: String, content: @Composable ColumnScope.() -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        NovaIcon(symbol, 15.dp, Modifier.size(20.dp, 22.dp), tint = NovaColorToken.textSecondary.color())
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp), content = content)
    }
}
