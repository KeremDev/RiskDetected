package com.riskdetectedan.feature.nova

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.isg.*
import com.riskdetectedan.core.data.nova.NovaRecordEvents
import com.riskdetectedan.core.data.profile.ProfileRepository
import com.riskdetectedan.core.designsystem.isg.*
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import java.util.UUID
import javax.inject.Inject

/** Active counts of a company's (or the whole workspace's) directory (iOS `IsgPersonnelMetrics`). */
data class NovaOsgbPersonnel(val employees: Long, val workplaces: Long, val departments: Long) {
    companion object {
        fun parse(value: JsonObject): NovaOsgbPersonnel {
            fun active(key: String) = value[key]?.jsonObject?.get("active")?.jsonPrimitive?.longOrNull ?: 0
            return NovaOsgbPersonnel(active("employees"), active("workplaces"), active("departments"))
        }
    }
}

data class NovaOsgbManagerUiState(
    val identity: IsgWorkspaceIdentity? = null,
    val navigation: NovaNavigationState = NovaNavigationState(UUID.randomUUID().toString(), NovaWorkspaceRole.osgbManager.destinations),
    val userName: String = "",
    val avatar: ImageBitmap? = null,
    val personnel: NovaOsgbPersonnel? = null,
)

/**
 * Session state for the OSGB management root (iOS `IsgOSGBWorkspaceRoot`). The workspace itself lives
 * in [NovaWorkspaceStore]; this only owns navigation, the profile header and the workspace-wide counters.
 * Reports and the activity log are the account's own, so they run over a personal pilot ticket.
 */
@HiltViewModel
class NovaOsgbManagerViewModel @Inject constructor(
    private val transport: NovaExpertTransport,
    val repository: IsgWorkspaceRepository,
    val events: NovaRecordEvents,
    private val profiles: ProfileRepository,
    private val auth: AuthRepository,
) : ViewModel() {
    private val mutable = MutableStateFlow(NovaOsgbManagerUiState())
    val state = mutable.asStateFlow()
    private var ticket: NovaExpertTicket? = null

    fun bind(identity: IsgWorkspaceIdentity) {
        if (state.value.identity == identity) return
        ticket?.let(transport::release)
        ticket = transport.bind(identity, null)
        mutable.value = NovaOsgbManagerUiState(identity = identity)
        viewModelScope.launch {
            val profile = (profiles.fetchProfile(identity.userId) as? RdResult.Success)?.value ?: return@launch
            if (state.value.identity != identity) return@launch
            mutable.value = state.value.copy(userName = profile.fullName?.trim().orEmpty())
            val path = profile.avatarUrl?.trim().orEmpty()
            if (path.isEmpty()) return@launch
            val bytes = (profiles.downloadAvatar(path) as? RdResult.Success)?.value ?: return@launch
            val bitmap = runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() }.getOrNull()
            if (state.value.identity == identity) mutable.value = state.value.copy(avatar = bitmap)
        }
    }

    fun apply(event: NovaNavigationEvent, from: String) {
        mutable.value = state.value.copy(navigation = state.value.navigation.apply(event, from))
    }

    fun navigate(destination: NovaDestination) = apply(NovaNavigationEvent.Navigate(destination), state.value.navigation.epoch)

    /** The workspace-wide directory counters behind the statistics page and the menu progress. */
    suspend fun loadPersonnel(context: IsgWorkspaceContext) {
        val value = try { NovaOsgbPersonnel.parse(repository.personnelMetrics(context, null)) }
            catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { null }
        mutable.value = state.value.copy(personnel = value)
    }

    fun signOut() { viewModelScope.launch { auth.signOut() } }

    override fun onCleared() {
        ticket?.let(transport::release)
        super.onCleared()
    }
}

private val monitoredDomains = listOf(IsgWorkspaceDomain.RISK, IsgWorkspaceDomain.EMERGENCY_PLAN, IsgWorkspaceDomain.EQUIPMENT,
    IsgWorkspaceDomain.NONCONFORMITY, IsgWorkspaceDomain.TRAINING, IsgWorkspaceDomain.APPOINTMENT, IsgWorkspaceDomain.DRILL,
    IsgWorkspaceDomain.CHECKLIST, IsgWorkspaceDomain.BOARD, IsgWorkspaceDomain.KATIP, IsgWorkspaceDomain.FILES, IsgWorkspaceDomain.VISIT)

private fun companySummary(company: NovaWorkspaceCompany) = listOfNotNull(hazardTitle(company.hazardClass) ?: "Tehlikeli",
    company.sector?.takeIf { it.isNotEmpty() }, company.declaredEmployeeCount?.let { "$it çalışan" }).joinToString(" · ")

private fun managerRole(value: String) = when (value) { "owner" -> "OSGB sahibi"; "admin" -> "OSGB yöneticisi"; else -> "İSG uzmanı" }

private fun searchSymbol(kind: String) = when (kind) {
    "employee" -> "person"; "equipment" -> "shippingbox"; "training" -> "graduationcap"; "file" -> "doc"; else -> "checklist"
}

/** The status a company page shows for one domain (iOS `companyModuleStatus`). */
internal fun osgbModuleStatus(snapshot: IsgWorkspaceSnapshot?): Pair<String, NovaStatus>? {
    snapshot ?: return null
    if (snapshot.rows.isEmpty()) return "Başlanmadı" to NovaStatus.Warning
    val statuses = snapshot.rows.mapNotNull { it.status }
    val metric = snapshot.metrics.filter { it.value > 0 }.map { it.id }
    return when {
        statuses.any { it in setOf("overdue", "expired", "failed", "critical") } ||
            metric.any { it.contains("overdue") || it.contains("expired") || it.contains("failed") } -> "Dikkat" to NovaStatus.Danger
        statuses.any { it in setOf("due_soon", "upcoming") } || metric.any { it.contains("due_soon") || it.contains("upcoming") } ->
            "Yaklaşıyor" to NovaStatus.Warning
        statuses.any { it in setOf("open", "assigned", "in_progress", "pending_verification", "untracked", "never_inspected", "period_unknown") } ||
            metric.any { it.contains("untracked") || it.contains("open") } -> "Takip gerekli" to NovaStatus.Warning
        statuses.any { it in setOf("draft", "planned") } -> "Devam ediyor" to NovaStatus.Info
        else -> "Güncel" to NovaStatus.Success
    }
}

/**
 * The OSGB management root (iOS `IsgOSGBWorkspaceRoot` for owners and admins). Every page reads through the
 * workspace API of the selected company; nothing falls back to a personal owner boundary.
 */
@Composable
fun NovaOsgbManagerRoot(identity: IsgWorkspaceIdentity, workspace: NovaWorkspaceUiState, store: NovaWorkspaceStore, slots: NovaPilotSlots,
                        viewModel: NovaOsgbManagerViewModel = hiltViewModel(),
                        services: NovaRootServices = hiltViewModel()) {
    LaunchedEffect(identity) { viewModel.bind(identity) }
    val state by viewModel.state.collectAsState()
    val celebrate = rememberNovaCelebrate()
    LaunchedEffect(identity) {
        launch { viewModel.events.succeeded.collect { if (it.userId == identity.userId) celebrate(it.message) } }
        viewModel.events.changed.collect { if (it.userId == identity.userId) store.refresh() }
    }
    OnForeground { store.refresh() }
    val context = workspace.selection ?: return
    if (state.identity != identity) {
        NovaPageSurface { NovaLoadingView("Verileriniz güncelleniyor…") }
        return
    }
    val ready = workspace.phase == NovaWorkspacePhase.ready
    val companyKey = workspace.companies.joinToString(",") { it.id }
    LaunchedEffect(context.workspaceId, workspace.phase, workspace.selectedCompanyId, companyKey) {
        if (ready) viewModel.loadPersonnel(context)
    }
    val canManage = context.canOperate && context.membership.role in setOf("owner", "admin")
    val selected = workspace.companies.firstOrNull { it.id == workspace.selectedCompanyId }
    val board = workspace.dashboard
    val navigate: (NovaDestination) -> Unit = viewModel::navigate
    var showingSearch by rememberSaveable { mutableStateOf(false) }
    var dashboardDomain by remember { mutableStateOf<IsgWorkspaceDomain?>(null) }
    var companyPage by remember { mutableStateOf<String?>(null) }
    var companyDomain by remember { mutableStateOf<IsgWorkspaceDomain?>(null) }
    var editor by remember { mutableStateOf<ManagerEditor?>(null) }
    var showingMembers by remember { mutableStateOf(false) }
    var showingAssignments by remember { mutableStateOf(false) }
    val domainClient = remember(context, selected?.id) {
        selected?.let { company ->
            NovaOsgbDomainClient(snapshot = { viewModel.repository.snapshot(context, company.id, it) },
                detail = { domain, id -> viewModel.repository.domainDetail(context, company.id, domain, id) },
                workplaces = { viewModel.repository.directory(context, company.id, "workplaces").toMap() },
                employees = { viewModel.repository.directory(context, company.id, "employees").toMap() })
        }
    }

    @Composable fun domain(value: IsgWorkspaceDomain, onBack: () -> Unit = { navigate(NovaDestination.home) }, startInAddMode: Boolean = false) {
        if (selected == null || domainClient == null) CompanyRequired(value.title, onBack)
        else key(selected.id, value, startInAddMode) {
            val scope = remember(context, selected) { NovaOsgbScope(context, viewModel.repository, selected.id, selected.name, selected.hazardClass) }
            NovaOsgbDomainScreen(domainClient, value, selected.name, onBack, startInAddMode = startInAddMode,
                create = if (context.canOperate) ({ close -> NovaOsgbCreateFlow(scope, value, close) }) else null) { row, workplaces, changed ->
                NovaOsgbRecordActions(context, viewModel.repository, selected.id, value, row, workplaces, selected.hazardClass, changed)
            }
        }
    }

    @Composable fun search(onBack: () -> Unit) {
        NovaOsgbSearchScreen(selected?.name, { query -> viewModel.repository.search(context, selected!!.id, query) }, onBack)
    }

    editor?.let { route ->
        key(route) {
            NovaOsgbCompanyEditor(context, viewModel.repository, route.company, onClose = { editor = null },
                onSaved = { editor = null; store.refresh() }, onArchived = { editor = null; companyPage = null; store.refresh() })
        }
        return
    }
    if (showingMembers) {
        NovaOsgbMemberManagement(context, viewModel.repository, onBack = { showingMembers = false }) { member, onClose ->
            NovaActivityScreen(remember(member) { services.activityClient(identity, context.workspaceId, member) }, onClose = onClose, member = true)
        }
        return
    }
    if (showingAssignments && selected != null) {
        NovaOsgbAssignmentManagement(context, viewModel.repository, selected) { showingAssignments = false }
        return
    }
    val createCompany: (() -> Unit)? = if (canManage) ({ editor = ManagerEditor(null) }) else null
    NovaExpertShell(state.navigation, state.userName, viewModel::apply, profileAvatar = state.avatar,
        menuRoleTitle = if (canManage) "OSGB Yetkilisi" else "İSG Uzmanı",
        menuStats = managerMenuStats(board), menuNextAction = managerNextAction(workspace, board, state.personnel, canManage),
        connectionLabel = "${context.name} · ${managerRole(context.membership.role)}", isManager = canManage,
        actions = NovaShellActions(
            onCompanyCreate = createCompany,
            onExpertCreate = if (canManage) ({ showingMembers = true }) else null,
            onAssignmentOpen = if (canManage) ({
                if (selected != null) showingAssignments = true else navigate(NovaDestination.companies)
            }) else null,
            onInvite = { navigate(NovaDestination.profile) },
            onDestination = { if (it == NovaDestination.companies) { companyPage = null; companyDomain = null } },
            onLogout = viewModel::signOut,
        )) { destination ->
        when (destination) {
            NovaDestination.home -> when {
                showingSearch -> search { showingSearch = false }
                dashboardDomain != null -> domain(dashboardDomain!!, onBack = { dashboardDomain = null })
                else -> NovaDashboardScreen(managerDashboardData(state.userName, context, selected, board), onNavigate = navigate,
                    onPhoto = { navigate(NovaDestination.newAnalysis) }, onAssistant = {}, showsAssistant = false) {
                    ManagerHomeFooter(workspace, selected, canManage, context.canManageMembers, store, onSearch = { showingSearch = true },
                        onEdit = { editor = ManagerEditor(it) }, onMembers = { showingMembers = true },
                        onDomain = { dashboardDomain = it }, onAnalyses = { navigate(NovaDestination.analyses) })
                }
            }
            NovaDestination.activity -> NovaActivityScreen(remember(identity) { services.activityClient(identity, null) },
                onClose = { navigate(NovaDestination.home) })
            NovaDestination.notebook, NovaDestination.newNote -> key(destination) {
                com.riskdetectedan.feature.profile.NotebookScreen(onClose = { navigate(NovaDestination.home) },
                    startWithNewNote = destination == NovaDestination.newNote)
            }
            NovaDestination.statistics -> ManagerStatistics(workspace, board, state.personnel, isExpert = !canManage && workspace.isExpert,
                onRetry = store::refresh, onDomain = { navigate(it.destination) }) { navigate(NovaDestination.home) }
            NovaDestination.companies, NovaDestination.newCompany -> {
                if (destination == NovaDestination.newCompany && canManage) LaunchedEffect(Unit) {
                    editor = ManagerEditor(null); navigate(NovaDestination.companies)
                }
                val open = workspace.companies.firstOrNull { it.id == companyPage }
                when {
                    open != null && showingSearch -> search { showingSearch = false }
                    open != null && companyDomain != null -> domain(companyDomain!!, onBack = { companyDomain = null })
                    open != null -> NovaOsgbCompanyOverview(context, open, workspace, viewModel.repository,
                        onEdit = if (canManage) ({ editor = ManagerEditor(open) }) else null,
                        onBack = { companyPage = null; companyDomain = null }, onDomain = { companyDomain = it },
                        onAnalyses = { navigate(NovaDestination.analyses) }, onSearch = { showingSearch = true })
                    else -> NovaCompaniesScreen(workspace.companies.map { NovaCompanyItem(it.id, it.name, companySummary(it), it.profileCompletionCount, 8) },
                        isLoading = workspace.phase == NovaWorkspacePhase.loading && workspace.companies.isEmpty(),
                        onSelect = { id ->
                            companyPage = id; companyDomain = null
                            if (workspace.selectedCompanyId != id) store.selectCompany(id)
                        }, onBack = { navigate(NovaDestination.home) }, onRetry = store::refresh, isOwnedList = true, onCreate = createCompany)
                }
            }
            NovaDestination.reports -> NovaReportCenter(remember(identity) { services.reportClient(identity) }, slots.analysisReports,
                onBack = { navigate(NovaDestination.home) })
            NovaDestination.reportArchive -> NovaReportArchive(remember(identity) { services.reportClient(identity) }, slots.analysisReports,
                onBack = { navigate(NovaDestination.reports) })
            NovaDestination.findings -> domain(IsgWorkspaceDomain.NONCONFORMITY)
            NovaDestination.newFinding -> domain(IsgWorkspaceDomain.NONCONFORMITY, startInAddMode = true)
            NovaDestination.training -> domain(IsgWorkspaceDomain.TRAINING)
            NovaDestination.newTraining -> domain(IsgWorkspaceDomain.TRAINING, startInAddMode = true)
            NovaDestination.riskAssessments -> domain(IsgWorkspaceDomain.RISK)
            NovaDestination.checklists -> domain(IsgWorkspaceDomain.CHECKLIST)
            NovaDestination.emergencyPlans -> domain(IsgWorkspaceDomain.EMERGENCY_PLAN)
            NovaDestination.drills -> domain(IsgWorkspaceDomain.DRILL)
            NovaDestination.ppeHandovers -> domain(IsgWorkspaceDomain.PPE)
            NovaDestination.appointments -> domain(IsgWorkspaceDomain.APPOINTMENT)
            NovaDestination.katipContracts -> domain(IsgWorkspaceDomain.KATIP)
            NovaDestination.annualWorkPlans -> domain(IsgWorkspaceDomain.ANNUAL_PLAN)
            NovaDestination.boardMeetings -> domain(IsgWorkspaceDomain.BOARD)
            NovaDestination.visits -> domain(IsgWorkspaceDomain.VISIT)
            NovaDestination.newVisit -> domain(IsgWorkspaceDomain.VISIT, startInAddMode = true)
            NovaDestination.workPermits -> domain(IsgWorkspaceDomain.WORK_PERMIT)
            NovaDestination.periodicChecks -> domain(IsgWorkspaceDomain.EQUIPMENT)
            NovaDestination.documentChecklist, NovaDestination.documents -> domain(IsgWorkspaceDomain.FILES)
            NovaDestination.newDocument -> domain(IsgWorkspaceDomain.FILES, startInAddMode = true)
            NovaDestination.contractors -> domain(IsgWorkspaceDomain.PERSONNEL)
            NovaDestination.memory, NovaDestination.notifications -> NovaOsgbChangeScreen({
                viewModel.repository.changes(context, selected?.id)["rows"]?.jsonArray.orEmpty().mapNotNull { item ->
                    val row = item as? JsonObject ?: return@mapNotNull null
                    Triple(row["sequence"]?.jsonPrimitive?.longOrNull ?: return@mapNotNull null,
                        row["aggregate_type"]?.jsonPrimitive?.contentOrNull.orEmpty(), row["event_type"]?.jsonPrimitive?.contentOrNull.orEmpty())
                }
            }, selected?.name) { navigate(NovaDestination.home) }
            NovaDestination.profile -> Column(Modifier.fillMaxSize()) {
                NovaPageHeading("Profil", modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) { navigate(NovaDestination.home) }
                Box(Modifier.weight(1f)) { slots.profile { navigate(NovaDestination.home) } }
            }
            else -> CompanyRequired(destination.title, onBack = { navigate(NovaDestination.home) },
                message = "Bu sayfa OSGB çalışma alanında henüz açılmadı. Ana sayfadaki firma operasyonlarını kullanabilirsiniz.",
                title = "Sayfa hazırlanıyor")
        }
    }
}

private fun managerMenuStats(board: NovaWorkspaceDashboard?) = listOf(
    NovaMenuStat("upcoming", "Yaklaşan İşler", board?.let { (it.equipmentDueSoon + it.riskDueSoon).toString() } ?: "—",
        "calendar.badge.clock", NovaDestination.periodicChecks),
    NovaMenuStat("overdue", "Süresi biten", board?.overdueNonconformities?.toString() ?: "—", "exclamationmark.triangle", NovaDestination.findings),
    NovaMenuStat("analyses", "Analiz", board?.openNonconformities?.toString() ?: "—", "photo.on.rectangle.angled", NovaDestination.analyses),
)

private fun managerNextAction(workspace: NovaWorkspaceUiState, board: NovaWorkspaceDashboard?, personnel: NovaOsgbPersonnel?,
                              canManage: Boolean): NovaMenuNextAction {
    if (workspace.companies.isEmpty()) return NovaMenuNextAction("Firma ekle", "building.2.crop.circle",
        if (canManage) NovaDestination.newCompany else NovaDestination.companies, 0, 1)
    if ((board?.openNonconformities ?: 0) == 0L) return NovaMenuNextAction("Fotoğraf analiz et", "camera", NovaDestination.newAnalysis, 0, 8)
    var completed = 1
    if ((board?.openNonconformities ?: 0) > 0) completed++
    if ((personnel?.employees ?: 0) > 0) completed++
    if ((board?.trainingCompleted ?: 0) > 0) completed++
    if ((board?.visitsTotal ?: 0) > 0) completed++
    return NovaMenuNextAction("Risk analizi ekle", "shield.lefthalf.filled", NovaDestination.riskAssessments, minOf(completed, 8), 8)
}

private fun managerDashboardData(userName: String, context: IsgWorkspaceContext, selected: NovaWorkspaceCompany?,
                                 board: NovaWorkspaceDashboard?): NovaDashboardData {
    fun metric(id: String, value: String, label: String, footer: String, symbol: String, destination: NovaDestination) =
        NovaMetricItem(id, value, label, footer, symbol, NovaColorToken.accent, destination)
    return NovaDashboardData(firstName = userName.split(" ").firstOrNull()?.takeIf { it.isNotEmpty() } ?: "İSGADA",
        openCount = board?.openNonconformities?.toInt(),
        metrics = listOf(
            metric("companies", board?.companies?.toString() ?: "—", "Firmalar", "Aktif", "building.2", NovaDestination.companies),
            metric("experts", board?.experts?.toString() ?: "—", "Uzmanlar", "Aktif", "person.badge.shield.checkmark", NovaDestination.companies),
            metric("open", board?.openNonconformities?.toString() ?: "—", "Açık uygunsuzluk", "Takipte", "checklist", NovaDestination.findings),
            metric("overdue", board?.overdueNonconformities?.toString() ?: "—", "Süresi geçen", "Kontrol", "exclamationmark.triangle", NovaDestination.findings),
            metric("training", board?.trainingCompleted?.toString() ?: "—", "Tamamlanan eğitim", "Kayıt", "graduationcap", NovaDestination.training),
            metric("deadlines", board?.let { (it.equipmentDueSoon + it.riskDueSoon).toString() } ?: "—", "Yaklaşan kontroller", "Takvim",
                "calendar.badge.clock", NovaDestination.periodicChecks)),
        activity = selected?.let { "${it.name} firması için güncel kayıtlar" },
        trainingMessage = "Gerçekleşen eğitimler ve katılımcı kayıtları",
        summaryMessage = "${context.name} için güncel kayıtlar.")
}

/** The tenant-scoped part of the manager home (iOS `osgbHomeFooter`). */
@Composable
private fun ManagerHomeFooter(workspace: NovaWorkspaceUiState, selected: NovaWorkspaceCompany?, canManage: Boolean, canManageMembers: Boolean,
                              store: NovaWorkspaceStore, onSearch: () -> Unit, onEdit: (NovaWorkspaceCompany) -> Unit, onMembers: () -> Unit, onDomain: (IsgWorkspaceDomain) -> Unit, onAnalyses: () -> Unit) {
    Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        selected?.let { NovaHelpHint("${it.name} firması için yetkili kayıtları görüntülüyorsunuz.") }
        NovaText("Firma seçimi", style = NovaTypeToken.sectionTitle)
        workspace.companies.forEach { company ->
            NovaCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress { store.selectCompany(company.id) }
                .testTag("osgb.company.${company.id}"), padding = 12) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("building.2", 19.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        NovaText(company.name, style = NovaTypeToken.bodyStrong)
                        NovaText(companySummary(company), style = NovaTypeToken.metaQuiet)
                    }
                    if (workspace.selectedCompanyId == company.id) NovaIcon("checkmark.circle.fill", 18.dp)
                    if (canManage) Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).novaRowPress { onEdit(company) }
                        .semantics { contentDescription = "Firmayı düzenle" }, contentAlignment = Alignment.Center) { NovaIcon("pencil", 17.dp) }
                }
            }
        }
        if (selected != null) FooterLink("magnifyingglass", "Firma Kayıtlarında Ara", "Personel, uygunsuzluk, ekipman ve dosyalarda arayın.",
            "osgb.search.open", onSearch)
        if (canManageMembers) FooterLink("person.2.badge.gearshape", "Uzman ve yönetici ekibi", "Davetleri, rolleri ve erişim durumlarını yönetin.",
            "osgb.members.open", onMembers)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaText("Firma operasyonları", style = NovaTypeToken.sectionTitle)
            val tiles = IsgWorkspaceDomain.entries.map { Triple(it.symbol, it.title) { onDomain(it) } } +
                Triple(NovaDestination.analyses.symbol, NovaDestination.analyses.title, onAnalyses)
            tiles.chunked(2).forEach { pair ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    pair.forEach { (symbol, title, action) ->
                        NovaCard(Modifier.weight(1f).clip(RoundedCornerShape(22.dp))
                            .then(if (selected != null) Modifier.novaRowPress(onClick = action) else Modifier), padding = 12) {
                            Row(Modifier.heightIn(min = 44.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically) {
                                NovaIcon(symbol, 18.dp)
                                NovaText(title, Modifier.weight(1f), NovaTypeToken.bodyStrong,
                                    color = if (selected != null) NovaColorToken.text.color() else NovaColorToken.textMuted.color())
                                NovaIcon("chevron.right", 11.dp)
                            }
                        }
                    }
                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
        if (!canManage && workspace.companies.isEmpty()) NovaEmptyState("Henüz firma yok", "Size atanan firmalar burada görünür.")
    }
}

@Composable
private fun FooterLink(symbol: String, title: String, detail: String, tag: String, onClick: () -> Unit) {
    NovaCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onClick).testTag(tag), padding = 12) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon(symbol, 19.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                NovaText(title, style = NovaTypeToken.bodyStrong)
                NovaText(detail, style = NovaTypeToken.metaQuiet)
            }
            NovaIcon("chevron.right", 12.dp)
        }
    }
}

@Composable
private fun CompanyRequired(heading: String, onBack: () -> Unit, title: String = "Önce firma seçin",
                            message: String = "Bu modüldeki kayıtlar firma kapsamında tutulur. Ana sayfadan bir firma seçin.") {
    BackHandler(onBack = onBack)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPageHeading(heading, onBack = onBack)
        NovaEmptyState(title, message)
    }
}

/** İstatistikler for the workspace (iOS manager `statistics`). */
@Composable
private fun ManagerStatistics(workspace: NovaWorkspaceUiState, board: NovaWorkspaceDashboard?, personnel: NovaOsgbPersonnel?, isExpert: Boolean,
                              onRetry: () -> Unit, onDomain: (IsgWorkspaceDomain) -> Unit, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val hasCompany = workspace.selectedCompanyId != null
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).padding(bottom = novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPageHeading(NovaDestination.statistics.title, onBack = onBack)
        NovaHelpHint("Firma, uzman ve operasyon göstergeleri.")
        when {
            board != null -> {
                val stats = listOfNotNull(Triple("Firmalar", "building.2", board.companies.toString()),
                    if (isExpert) null else Triple("Uzmanlar", "person.badge.shield.checkmark", board.experts?.toString() ?: "—"),
                    Triple("Açık uygunsuzluk", "checklist", board.openNonconformities.toString()),
                    Triple("Süresi geçen", "exclamationmark.triangle", board.overdueNonconformities.toString()),
                    Triple("Tamamlanan eğitim", "graduationcap", board.trainingCompleted.toString()),
                    Triple("Yaklaşan kontroller", "calendar.badge.clock", (board.equipmentDueSoon + board.riskDueSoon).toString()))
                stats.chunked(2).forEach { pair ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        pair.forEach { (title, symbol, value) -> NovaListStat(title, symbol, value, Modifier.weight(1f)) }
                        if (pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
                personnel?.let {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        NovaListStat("Personel", "person.2", it.employees.toString(), Modifier.weight(1f))
                        NovaListStat("İşyerleri", "building.2", it.workplaces.toString(), Modifier.weight(1f))
                        NovaListStat("Departmanlar", "square.grid.2x2", it.departments.toString(), Modifier.weight(1f))
                    }
                }
            }
            workspace.phase == NovaWorkspacePhase.loading -> NovaLoadingView("İstatistikler yükleniyor…")
            else -> {
                NovaEmptyState("İstatistikler alınamadı", "Bağlantınızı kontrol edip tekrar deneyin.")
                NovaCompactActionButton("Tekrar dene", "arrow.clockwise", Modifier.width(IntrinsicSize.Max), onClick = onRetry)
            }
        }
        IsgWorkspaceDomain.entries.forEach { item ->
            NovaCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp))
                .then(if (hasCompany) Modifier.novaRowPress { onDomain(item) } else Modifier), padding = 12) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon(item.symbol, 18.dp)
                    NovaText(item.title, Modifier.weight(1f), NovaTypeToken.bodyStrong)
                    NovaIcon("chevron.right", 12.dp)
                }
            }
        }
    }
}

/** Firma Kayıtlarında Ara (iOS manager `search`): the selected company's authorized records only. */
@Composable
private fun NovaOsgbSearchScreen(companyName: String?, search: suspend (String) -> JsonObject, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val coroutines = rememberCoroutineScope()
    var query by remember { mutableStateOf("") }
    var rows by remember { mutableStateOf<List<Triple<String, String, String?>>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var searching by remember { mutableStateOf(false) }
    val run = {
        val clean = query.trim()
        if (clean.toByteArray().size >= 2 && !searching) {
            searching = true; error = null
            coroutines.launch {
                try {
                    rows = search(clean)["rows"]?.jsonArray.orEmpty().mapNotNull { item ->
                        val row = item as? JsonObject ?: return@mapNotNull null
                        Triple(row["kind"]?.jsonPrimitive?.contentOrNull.orEmpty(), row["title"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null,
                            row["subtitle"]?.jsonPrimitive?.contentOrNull)
                    }
                } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                    rows = null; error = "Bağlantınızı kontrol edip yeniden deneyin."
                }
                searching = false
            }
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPageHeading("Firma Kayıtlarında Ara", onBack = onBack)
        if (companyName == null) {
            NovaEmptyState("Önce firma seçin", "Arama yalnız seçtiğiniz firmanın yetkili kayıtlarında çalışır.")
            return@Column
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.weight(1f)) { NovaSearchCapsule(query, "Personel, uygunsuzluk, ekipman veya dosya ara", "osgb.search.field") { query = it } }
            if (searching) Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) {
                androidx.compose.material3.CircularProgressIndicator(Modifier.size(20.dp), color = NovaColorToken.text.color(), strokeWidth = 2.dp)
            }
            else Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(NovaColorToken.surfaceMuted.color())
                .novaRowPress(onClick = run).testTag("osgb.search.run"), contentAlignment = Alignment.Center) { NovaIcon("arrow.right", 16.dp) }
        }
        error?.let { NovaEmptyState("Arama tamamlanamadı", it) }
        val found = rows
        when {
            found == null -> Unit
            found.isEmpty() -> NovaEmptyState("Eşleşen kayıt yok", "Farklı bir ad, başlık veya kodla yeniden arayın.")
            else -> found.forEach { (kind, title, subtitle) ->
                NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon(searchSymbol(kind), 18.dp)
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            NovaText(title, style = NovaTypeToken.bodyStrong)
                            subtitle?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Firma Detayı (iOS `companyOverview`): readiness from the monitored domains, the next actions and every
 * record category of one company.
 */
@Composable
private fun NovaOsgbCompanyOverview(context: IsgWorkspaceContext, company: NovaWorkspaceCompany, workspace: NovaWorkspaceUiState,
                                    repository: IsgWorkspaceRepository, onEdit: (() -> Unit)?, onBack: () -> Unit,
                                    onDomain: (IsgWorkspaceDomain) -> Unit, onAnalyses: () -> Unit, onSearch: () -> Unit) {
    BackHandler(onBack = onBack)
    var snapshots by remember(company.id) { mutableStateOf<Map<IsgWorkspaceDomain, IsgWorkspaceSnapshot>>(emptyMap()) }
    var personnel by remember(company.id) { mutableStateOf<NovaOsgbPersonnel?>(null) }
    var loading by remember(company.id) { mutableStateOf(true) }
    var error by remember(company.id) { mutableStateOf<String?>(null) }
    var reload by remember { mutableIntStateOf(0) }
    val active = workspace.phase == NovaWorkspacePhase.ready && workspace.selectedCompanyId == company.id
    LaunchedEffect(company.id, active, reload) {
        if (!active) return@LaunchedEffect
        loading = true; error = null
        coroutineScope {
            val people = async { runCatching { NovaOsgbPersonnel.parse(repository.personnelMetrics(context, company.id)) }.getOrNull() }
            val values = monitoredDomains.map { domain -> async { runCatching { repository.snapshot(context, company.id, domain) }.getOrNull() } }
            personnel = people.await()
            snapshots = values.mapNotNull { it.await() }.associateBy { it.domain }
        }
        if (personnel == null || snapshots.size < monitoredDomains.size)
            error = "Bazı firma durumları alınamadı. Görünen kayıtları kullanabilir veya özeti yenileyebilirsiniz."
        loading = false
    }
    val openFindings = snapshots[IsgWorkspaceDomain.NONCONFORMITY]?.rows.orEmpty().count { it.status !in setOf("closed", "cancelled") }
    val nextActions = buildList {
        if (openFindings > 0) add(CompanyAction("Açık uygunsuzlukları incele", "$openFindings kayıt takip bekliyor", "exclamationmark.triangle",
            NovaStatus.Danger, IsgWorkspaceDomain.NONCONFORMITY))
        listOf(Triple(IsgWorkspaceDomain.RISK, "Risk değerlendirmesi oluştur", "Henüz değerlendirme kaydı yok") to "checkmark.shield",
            Triple(IsgWorkspaceDomain.EMERGENCY_PLAN, "Acil durum planı oluştur", "Henüz yürürlükte bir plan yok") to "light.beacon.max",
            Triple(IsgWorkspaceDomain.EQUIPMENT, "Ekipman ve kontrol takibini başlat", "Henüz ekipman kaydı yok") to "wrench.and.screwdriver",
            Triple(IsgWorkspaceDomain.APPOINTMENT, "Çalışan görevlerini tanımla", "Henüz atama kaydı yok") to "person.badge.shield.checkmark",
            Triple(IsgWorkspaceDomain.TRAINING, "İlk eğitim kaydını oluştur", "Henüz gerçekleşen eğitim yok") to "graduationcap",
        ).forEach { (item, symbol) ->
            if (snapshots[item.first]?.rows?.isEmpty() == true) add(CompanyAction(item.second, item.third, symbol, NovaStatus.Warning, item.first))
        }
    }
    val android = LocalContext.current
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    var logo by remember(company.id) { mutableStateOf<Bitmap?>(null) }
    var logoEntry by remember(company.id) { mutableStateOf<String?>(null) }
    var logoSaving by remember { mutableStateOf(false) }
    var logoError by remember { mutableStateOf<String?>(null) }
    val uploadAttempt = remember { IsgWorkspaceMutationAttempt() }
    val linkAttempt = remember { IsgWorkspaceMutationAttempt() }
    val logoRow = snapshots[IsgWorkspaceDomain.FILES]?.rows?.firstOrNull { row -> row.fact("category") == "company_logo" }
    LaunchedEffect(logoRow?.id) {
        val row = logoRow ?: return@LaunchedEffect
        val asset = row.assetId ?: return@LaunchedEffect
        if (row.id == logoEntry && logo != null) return@LaunchedEffect
        val bytes = runCatching { repository.downloadAsset(context, asset) }.getOrNull() ?: return@LaunchedEffect
        logo = withContext(Dispatchers.Default) { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) } ?: return@LaunchedEffect
        logoEntry = row.id
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null || !context.canOperate) return@rememberLauncherForActivityResult
        coroutines.launch {
            logoSaving = true; logoError = null
            try {
                val (jpeg, image) = withContext(Dispatchers.IO) {
                    val source = android.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: error("empty")
                    val decoded = BitmapFactory.decodeByteArray(source, 0, source.size) ?: error("image")
                    (normalizedLogo(decoded) ?: error("size")) to decoded
                }
                val digest = java.security.MessageDigest.getInstance("SHA-256").digest(jpeg).joinToString("") { "%02x".format(it) }
                val (entry, _) = repository.uploadFile(context, uploadAttempt.id("company.logo.upload", company.id.lowercase(), digest), company.id,
                    "Firma logosu", "firma-logo.jpg", "company_logo", jpeg)
                repository.mutateDomain(context, linkAttempt.id("company.logo.link", company.id.lowercase(), entry.lowercase()), company.id,
                    IsgWorkspaceDomain.FILES, buildJsonObject { put("action", "set_company_logo"); put("entry_id", entry) })
                logo = image; logoEntry = entry
                celebrate("Firma logosu başarıyla eklendi!")
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                logoError = "Logo eklenemedi. JPG veya PNG görseliyle yeniden deneyin."
            }
            logoSaving = false
        }
    }
    val hasLogo = logo != null || logoRow != null
    fun readiness(id: String, title: String, domain: IsgWorkspaceDomain): NovaCompanyReadinessItem {
        val snapshot = snapshots[domain] ?: return NovaCompanyReadinessItem(id, title,
            if (loading) "Durum yükleniyor." else "Durum bilgisi alınamadı.", NovaCompanyReadinessStatus.unknown)
        if (snapshot.rows.isEmpty()) return NovaCompanyReadinessItem(id, title, "Henüz kayıt yok.", NovaCompanyReadinessStatus.missing)
        val status = osgbModuleStatus(snapshot)
        return NovaCompanyReadinessItem(id, title, status?.let { "${snapshot.rows.size} kayıt · ${it.first}" } ?: "${snapshot.rows.size} kayıt bulundu.",
            when (status?.second) { NovaStatus.Success -> NovaCompanyReadinessStatus.complete; null, NovaStatus.Neutral -> NovaCompanyReadinessStatus.unknown
                else -> NovaCompanyReadinessStatus.needsReview })
    }
    val hasInfo = !company.sector.isNullOrBlank() && !company.address.isNullOrBlank()
    val responsible = company.responsibleName?.trim().orEmpty()
    val readinessItems = listOf(
        NovaCompanyReadinessItem("company", "Firma Bilgileri", if (hasInfo) "Temel firma bilgileri güncel." else "Sektör veya adres bilgisi eksik.",
            if (hasInfo) NovaCompanyReadinessStatus.complete else NovaCompanyReadinessStatus.missing),
        readiness("risk", "Risk Analizi", IsgWorkspaceDomain.RISK),
        readiness("emergency", "Acil Durum Planı", IsgWorkspaceDomain.EMERGENCY_PLAN),
        readiness("training", "Eğitim", IsgWorkspaceDomain.TRAINING),
        NovaCompanyReadinessItem("personnel", "Personel", personnel?.let { "${it.employees} aktif personel kayıtlı." } ?: "Personel verisi yükleniyor.",
            personnel?.let { if (it.employees > 0) NovaCompanyReadinessStatus.complete else NovaCompanyReadinessStatus.missing }
                ?: NovaCompanyReadinessStatus.unknown),
        readiness("nonconformity", "Uygunsuzluk", IsgWorkspaceDomain.NONCONFORMITY),
        readiness("equipment", "Periyodik Kontrol", IsgWorkspaceDomain.EQUIPMENT),
        NovaCompanyReadinessItem("logo", "Logo", if (hasLogo) "Firma logosu kayıtlı." else "Firma logosu eklenmemiş.",
            when { loading && snapshots[IsgWorkspaceDomain.FILES] == null -> NovaCompanyReadinessStatus.unknown
                hasLogo -> NovaCompanyReadinessStatus.complete; else -> NovaCompanyReadinessStatus.missing }),
        NovaCompanyReadinessItem("responsible", "Sorumlu Kişi", responsible.ifEmpty { "Sorumlu kişi tanımlanmamış." },
            if (responsible.isNotEmpty()) NovaCompanyReadinessStatus.complete else NovaCompanyReadinessStatus.missing),
        readiness("visits", "Ziyaretler", IsgWorkspaceDomain.VISIT),
    )
    fun subtitle(domain: IsgWorkspaceDomain) = snapshots[domain]?.let { if (it.rows.isEmpty()) "Henüz kayıt yok" else "${it.rows.size} kayıt" }
        ?: if (loading) "Yükleniyor…" else "Kayıtları görüntüle"

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset)
        .testTag("osgb.company.overview"), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        NovaPageHeading("Firma Detayı", onBack = onBack)
        NovaCard(Modifier.fillMaxWidth(), padding = 16) {
            Column(verticalArrangement = Arrangement.spacedBy(13.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    NovaCompanyMark(logo)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        NovaText(company.name, style = NovaTypeToken.cardTitle)
                        NovaText(listOfNotNull(IsgWorkspaceDisplayText.value(company.hazardClass), personnel?.let { "${it.employees} personel" })
                            .joinToString(" · "), style = NovaTypeToken.metaQuiet)
                    }
                    if (onEdit != null) Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).novaRowPress(onClick = onEdit)
                        .semantics { contentDescription = "Firmayı düzenle" }.testTag("osgb.company.edit"), contentAlignment = Alignment.Center) {
                        NovaIcon("pencil", 17.dp)
                    }
                }
                NovaMetricStrip(listOf(
                    NovaMetricStripItem("open-findings", openFindings.toString(), "açık uygunsuzluk", "exclamationmark.triangle",
                        if (openFindings > 0) NovaStatus.Danger else NovaStatus.Success),
                    NovaMetricStripItem("actions", nextActions.size.toString(), "işlem gerekli", "checklist",
                        if (nextActions.isEmpty()) NovaStatus.Success else NovaStatus.Warning)))
            }
        }
        NovaCompanyReadinessCard(readinessItems)
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            NovaCard(Modifier.fillMaxWidth(), padding = 11) {
                Row(Modifier.heightIn(min = 54.dp), horizontalArrangement = Arrangement.spacedBy(11.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaCompanyMark(logo)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        NovaText(if (logo == null) "Firma logosu ekleyin" else "Firma logosu", style = NovaTypeToken.bodyStrong)
                        NovaText(if (logoSaving) "Logo yükleniyor…" else "Firma kartında ve oluşturulan raporlarda kullanılır.", style = NovaTypeToken.micro,
                            color = NovaColorToken.textMuted.color())
                    }
                    if (logoSaving) NovaSpinner(NovaColorToken.text.color(), size = 18.dp)
                    else if (context.canOperate) NovaCompactActionButton(if (logo == null) "Logo seç" else "Değiştir",
                        if (logo == null) "plus" else "arrow.triangle.2.circlepath", Modifier.width(IntrinsicSize.Max), identifier = "company.logo.picker") {
                        picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    }
                }
            }
            logoError?.let { NovaText(it, style = NovaTypeToken.micro, color = NovaColorToken.statusDangerInk.color()) }
        }
        if (!active) NovaLoadingView("Firma çalışma alanı hazırlanıyor…")
        else {
            if (loading && snapshots.isEmpty()) NovaLoadingView("Sıradaki işler hazırlanıyor…")
            else {
                Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                    NovaText("Sıradaki işler", style = NovaTypeToken.sectionTitle)
                    if (nextActions.isEmpty()) NovaCard(Modifier.fillMaxWidth(), padding = 14, tint = NovaColorToken.statusSuccessBg.color()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                            NovaIcon("checkmark.circle.fill", 18.dp)
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                NovaText("Şu anda kritik iş görünmüyor", style = NovaTypeToken.bodyStrong)
                                NovaText("Kayıt kategorilerinden ayrıntıları inceleyebilirsiniz.", style = NovaTypeToken.metaQuiet)
                            }
                        }
                    }
                    nextActions.take(3).forEach { item ->
                        NovaCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress { onDomain(item.domain) }, padding = 13) {
                            Row(horizontalArrangement = Arrangement.spacedBy(11.dp)) {
                                Box(Modifier.size(36.dp).background(item.status.background.color(), RoundedCornerShape(11.dp)),
                                    contentAlignment = Alignment.Center) { NovaIcon(item.symbol, 18.dp) }
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                    NovaText(item.title, style = NovaTypeToken.bodyStrong)
                                    NovaText(item.detail, style = NovaTypeToken.metaQuiet)
                                }
                                NovaIcon("chevron.right", 11.dp)
                            }
                        }
                    }
                }
                Row(Modifier.fillMaxWidth().heightIn(min = 50.dp).clip(RoundedCornerShape(14.dp)).novaControlBackground(14.dp)
                    .novaRowPress(onClick = onSearch).padding(horizontal = 12.dp).testTag("osgb.company.search"),
                    horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("magnifyingglass", 18.dp)
                    NovaText("Firma kayıtlarında ara", Modifier.weight(1f), NovaTypeToken.bodyStrong)
                    NovaIcon("chevron.right", 11.dp)
                }
                Category("Firma ve kadro") {
                    CategoryRow("Firma bilgileri", company.sector?.takeIf { it.isNotEmpty() } ?: "Profil bilgileri", "building.2",
                        if (company.sector.isNullOrEmpty()) "Takip gerekli" to NovaStatus.Warning else "Güncel" to NovaStatus.Success, onEdit)
                    CategoryRow("Personel", personnel?.let { "${it.employees} kişi" } ?: "Yükleniyor", IsgWorkspaceDomain.PERSONNEL.symbol,
                        if ((personnel?.employees ?: 0) > 0) "Güncel" to NovaStatus.Success else "Başlanmadı" to NovaStatus.Warning) {
                        onDomain(IsgWorkspaceDomain.PERSONNEL)
                    }
                    DomainRow(IsgWorkspaceDomain.APPOINTMENT, snapshots, ::subtitle, onDomain)
                }
                Category("Risk ve acil durum") {
                    listOf(IsgWorkspaceDomain.RISK, IsgWorkspaceDomain.EMERGENCY_PLAN, IsgWorkspaceDomain.DRILL)
                        .forEach { DomainRow(it, snapshots, ::subtitle, onDomain) }
                }
                Category("Kontrol ve kayıtlar") {
                    listOf(IsgWorkspaceDomain.EQUIPMENT, IsgWorkspaceDomain.NONCONFORMITY, IsgWorkspaceDomain.CHECKLIST, IsgWorkspaceDomain.FILES)
                        .forEach { DomainRow(it, snapshots, ::subtitle, onDomain) }
                    CategoryRow(NovaDestination.analyses.title, "Fotoğraflı saha analizleri", NovaDestination.analyses.symbol, null, onAnalyses)
                }
                Category("Eğitim ve organizasyon") {
                    listOf(IsgWorkspaceDomain.TRAINING, IsgWorkspaceDomain.BOARD, IsgWorkspaceDomain.KATIP)
                        .forEach { DomainRow(it, snapshots, ::subtitle, onDomain) }
                }
                Category("Diğer kayıtlar") {
                    listOf(IsgWorkspaceDomain.ANNUAL_PLAN, IsgWorkspaceDomain.WORK_PERMIT, IsgWorkspaceDomain.VISIT, IsgWorkspaceDomain.PPE)
                        .forEach { DomainRow(it, snapshots, ::subtitle, onDomain) }
                }
            }
            error?.let {
                NovaTaskErrorSummary(it)
                NovaCompactActionButton("Firma özetini yeniden yükle", "arrow.clockwise", Modifier.width(IntrinsicSize.Max)) { reload++ }
            }
        }
    }
}

/** The create flow of one domain (iOS `IsgWorkspaceDomainScreen.createEditor`). */
@Composable
private fun NovaOsgbCreateFlow(scope: NovaOsgbScope, domain: IsgWorkspaceDomain, onClose: () -> Unit) = when (domain) {
    IsgWorkspaceDomain.FILES -> NovaOsgbFileCreateEditor(scope, onClose)
    IsgWorkspaceDomain.TRAINING -> NovaOsgbTrainingCreateEditor(scope, onClose)
    IsgWorkspaceDomain.NONCONFORMITY -> NovaOsgbManualNonconformityEditor(scope, onClose)
    IsgWorkspaceDomain.RISK -> NovaOsgbRiskCreateEditor(scope, onClose)
    IsgWorkspaceDomain.EMERGENCY_PLAN -> NovaOsgbEmergencyPlanCreateFlow(scope, onClose)
    IsgWorkspaceDomain.EQUIPMENT -> NovaOsgbEquipmentCreateEditor(scope, onClose)
    else -> NovaOsgbDomainCreateEditor(scope, domain, onClose)
}

/** A white-backed JPEG of at most 5 MB, stepping down in size and quality (iOS `normalizedCompanyLogo`). */
private fun normalizedLogo(image: Bitmap): ByteArray? {
    for ((maximum, quality) in listOf(1_600 to 84, 1_200 to 72, 900 to 60)) {
        val longest = maxOf(image.width, image.height).takeIf { it > 0 } ?: return null
        val scale = minOf(1f, maximum.toFloat() / longest)
        val width = maxOf(1, (image.width * scale).toInt()); val height = maxOf(1, (image.height * scale).toInt())
        val canvas = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        android.graphics.Canvas(canvas).apply {
            drawColor(android.graphics.Color.WHITE)
            drawBitmap(image, null, android.graphics.Rect(0, 0, width, height), android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG))
        }
        val data = java.io.ByteArrayOutputStream().also { canvas.compress(Bitmap.CompressFormat.JPEG, quality, it) }.toByteArray()
        if (data.size <= 5 * 1_024 * 1_024) return data
    }
    return null
}

/** A new company (null) or the one being edited; a fresh route restarts the editor. */
private class ManagerEditor(val company: NovaWorkspaceCompany?)

private data class CompanyAction(val title: String, val detail: String, val symbol: String, val status: NovaStatus, val domain: IsgWorkspaceDomain)

@Composable
private fun Category(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        NovaText(title, style = NovaTypeToken.sectionTitle)
        NovaCard(Modifier.fillMaxWidth(), padding = 0) { Column(content = content) }
    }
}

@Composable
private fun DomainRow(domain: IsgWorkspaceDomain, snapshots: Map<IsgWorkspaceDomain, IsgWorkspaceSnapshot>, subtitle: (IsgWorkspaceDomain) -> String,
                      onDomain: (IsgWorkspaceDomain) -> Unit) =
    CategoryRow(domain.title, subtitle(domain), domain.symbol, osgbModuleStatus(snapshots[domain])) { onDomain(domain) }

@Composable
private fun CategoryRow(title: String, subtitle: String, symbol: String, status: Pair<String, NovaStatus>?, action: (() -> Unit)?) {
    Row(Modifier.fillMaxWidth().heightIn(min = 58.dp).then(if (action != null) Modifier.novaRowPress(onClick = action) else Modifier)
        .padding(horizontal = 13.dp), horizontalArrangement = Arrangement.spacedBy(11.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) { NovaIcon(symbol, 17.dp) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            NovaText(title, style = NovaTypeToken.bodyStrong)
            NovaText(subtitle, style = NovaTypeToken.metaQuiet)
        }
        status?.let { NovaStatusPill(it.first, it.second) }
        if (action != null) NovaIcon("chevron.right", 11.dp)
    }
}
