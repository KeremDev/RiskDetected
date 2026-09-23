package com.riskdetectedan.feature.nova

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.saveable.rememberSaveable
import com.riskdetectedan.feature.profile.novaClient
import com.riskdetectedan.feature.profile.novaDirectoryClient
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import com.riskdetectedan.core.designsystem.isg.*

/**
 * The single expert root (iOS `NovaPilotRoot`): personal experts pass a null
 * [workspace]; OSGB experts pass the selected organization.
 */
@Composable
fun NovaPilotRoot(identity: IsgWorkspaceIdentity, workspace: NovaWorkspaceUiState?, slots: NovaPilotSlots,
                  onWorkspaceSwitch: (() -> Unit)?, viewModel: NovaPilotViewModel = hiltViewModel(),
                  services: NovaRootServices = hiltViewModel()) {
    val state by viewModel.state.collectAsState()
    LaunchedEffect(identity, workspace?.selection, workspace?.dashboard) {
        viewModel.bind(identity, workspace?.expertWorkspace, workspace?.selection?.name, workspace?.dashboard)
    }
    OnForeground { viewModel.reload() }
    val celebrate = rememberNovaCelebrate()
    // iOS `isgada.mutation.succeeded` / `isgada.records.changed`: only this account's events count.
    LaunchedEffect(identity) {
        launch { services.events.succeeded.collect { if (it.userId == identity.userId) celebrate(it.message) } }
        services.events.changed.collect { if (it.userId == identity.userId) viewModel.reload() }
    }
    if (state.identity != identity) {
        NovaPageSurface { NovaLoadingView("Verileriniz güncelleniyor…") }
        return
    }
    val navigate: (NovaDestination) -> Unit = viewModel::navigate
    val workspaceId = workspace?.expertWorkspace?.workspaceId
    // iOS `ExpertUsagePresence`: active time counts only while the pilot is in front.
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    DisposableEffect(identity, workspaceId, lifecycle) {
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
            when (event) {
                androidx.lifecycle.Lifecycle.Event.ON_START -> services.presence.foreground(identity, workspaceId)
                androidx.lifecycle.Lifecycle.Event.ON_STOP -> services.presence.background()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer); services.presence.background() }
    }
    val notices = state.notices
    NovaExpertShell(state.navigation, state.userName, viewModel::apply,
        profileAvatar = state.avatar, menuRoleTitle = "İSG Uzmanı",
        menuStats = menuStats(state), menuNextAction = nextAction(state),
        hasUnread = notices.unread > 0, unreadCount = notices.unread,
        notices = notices.rows.map(::noticeItem),
        noticeNote = if (notices.rows.isEmpty()) "" else NovaNoticeWords.dismissNote,
        connectionLabel = status(state),
        actions = NovaShellActions(
            onReadNotice = { viewModel.markNotice("read", it) },
            onDismissNotice = { viewModel.markNotice("dismiss", it) },
            onRestoreNotice = { viewModel.markNotice("restore", it) },
            onReadAll = { viewModel.markNotice("read_all") },
            onClearNotifications = { viewModel.markNotice("dismiss_all") },
            onLogout = viewModel::signOut,
        )) { destination ->
        when (destination) {
            NovaDestination.home -> NovaDashboardScreen(dashboardData(state), onNavigate = navigate,
                onPhoto = { navigate(NovaDestination.newAnalysis) }, onAssistant = viewModel::showUnavailable)
            NovaDestination.notifications -> NovaNoticeCenterScreen(services.noticeClient(identity),
                onOpen = { raw -> NovaDestination.entries.firstOrNull { it.name == raw }?.let(navigate) },
                onBack = { navigate(NovaDestination.home) })
            NovaDestination.profile -> Column(Modifier.fillMaxSize()) {
                NovaPageHeading("Profil", modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) { navigate(NovaDestination.home) }
                Box(Modifier.weight(1f)) { slots.profile { navigate(NovaDestination.home) } }
            }
            NovaDestination.findings -> NovaFindingsDestination(identity, NovaFindingsSurface.board, state.writable, navigate)
            NovaDestination.newFinding -> NovaFindingsDestination(identity, NovaFindingsSurface.addFinding, state.writable, navigate)
            NovaDestination.companies, NovaDestination.newCompany -> key(destination) {
                CompaniesDestination(services, identity, state, workspace, navigate, viewModel::reload, startCreating = destination == NovaDestination.newCompany)
            }
            NovaDestination.riskAssessments -> NovaRiskScreen(services.riskClient(identity), state.writable,
                onBack = { navigate(NovaDestination.home) })
            NovaDestination.periodicChecks -> NovaEquipmentScreen(services.equipmentClient(identity), state.writable,
                onBack = { navigate(NovaDestination.home) })
            NovaDestination.emergencyPlans -> NovaEmergencyScreen(services.emergencyClient(identity), state.writable,
                onBack = { navigate(NovaDestination.home) })
            NovaDestination.drills -> NovaDrillScreen(services.drillClient(identity), state.writable, onBack = { navigate(NovaDestination.home) })
            NovaDestination.appointments -> NovaAppointmentScreen(services.appointmentClient(identity), state.writable,
                onBack = { navigate(NovaDestination.home) })
            NovaDestination.ppeHandovers -> NovaPPEScreen(services.ppeClient(identity), state.writable, onBack = { navigate(NovaDestination.home) })
            // iOS NovaPilotRoot files these through the shared process records.
            NovaDestination.katipContracts, NovaDestination.annualWorkPlans, NovaDestination.boardMeetings, NovaDestination.visits,
            NovaDestination.workPermits, NovaDestination.contractors, NovaDestination.newVisit -> key(destination) {
                NovaProcessGate(services.processClient(identity), processKind(destination), state.writable, onBack = { navigate(NovaDestination.home) })
            }
            NovaDestination.documents, NovaDestination.newDocument -> key(destination) {
                NovaFileLibraryScreen(services.fileClient(identity), services.companyOptions(identity), state.writable, onBack = { navigate(NovaDestination.home) },
                    sources = { entry -> services.fileSources(identity, entry) }, openSource = recordOpener(services, identity, state.writable, state.userName),
                    startInAddMode = destination == NovaDestination.newDocument)
            }
            NovaDestination.documentChecklist -> NovaFollowupScreen({ company, status, query, offset -> services.followup(identity, company, status, query, offset) },
                services.companyOptions(identity), services.changes(identity), recordOpener(services, identity, state.writable, state.userName),
                onBack = { navigate(NovaDestination.home) })
            NovaDestination.training, NovaDestination.newTraining -> key(destination) {
                NovaTrainingScreen(services.trainingClient(identity, state.userName), state.writable, onBack = { navigate(NovaDestination.home) },
                    createOnOpen = destination == NovaDestination.newTraining)
            }
            NovaDestination.statistics -> NovaStatisticsScreen(services.statisticsClient(identity), onBack = { navigate(NovaDestination.home) },
                onNavigate = navigate, openTracked = trackedOpener(services, identity, state.writable)) { company, onBack ->
                NovaFollowupScreen({ selected, status, query, offset -> services.followup(identity, selected, status, query, offset) },
                    services.companyOptions(identity), services.changes(identity), recordOpener(services, identity, state.writable, state.userName),
                    onBack = onBack, initialCompany = company)
            }
            NovaDestination.notebook, NovaDestination.newNote -> key(destination) {
                com.riskdetectedan.feature.profile.NotebookScreen(onClose = { navigate(NovaDestination.home) },
                    startWithNewNote = destination == NovaDestination.newNote)
            }
            NovaDestination.activity -> ActivityDestination(services, identity, workspaceId, state.writable, state.userName, navigate, viewModel::showMessage)
            NovaDestination.reports -> NovaReportCenter(services.reportClient(identity), slots.analysisReports, onBack = { navigate(NovaDestination.home) })
            NovaDestination.reportArchive -> NovaReportArchive(services.reportClient(identity), slots.analysisReports,
                onBack = { navigate(NovaDestination.reports) })
            NovaDestination.memory -> NovaReportArchive(services.reportClient(identity), slots.analysisReports, onBack = { navigate(NovaDestination.home) })
            NovaDestination.checklists -> NovaChecklistScreen(services.checklistClient(identity), state.writable, onBack = { navigate(NovaDestination.home) })
            else -> NovaModulePending(destination, state, onWorkspaceSwitch) { navigate(NovaDestination.home) }
        }
    }
    NovaNoticeDialog(state.message, "İSGADA pilot", viewModel::dismissMessage)
}

/** Opens the module record a followup row or a file link points at (iOS `NovaFollowupDestination`). */
private fun recordOpener(services: NovaRootServices, identity: IsgWorkspaceIdentity, canWrite: Boolean, userName: String): NovaRecordOpener = { row, onBack ->
    when (row.kind) {
        "completed_drill", "personnel_certificate", "katip_contract", "approved_notebook", "site_visit", "board", "board_decision", "annual_work_item" ->
            NovaProcessEditor(services.processClient(identity), row.kind, row.companyId, null, row.recordId, canWrite, onBack)
        "risk_assessment" -> NovaRiskScreen(services.riskClient(identity), canWrite, onBack, initialCompany = row.companyId)
        "equipment" -> NovaEquipmentScreen(services.equipmentClient(identity), canWrite, onBack, initialCompany = row.companyId)
        "emergency_plan" -> NovaEmergencyScreen(services.emergencyClient(identity), canWrite, onBack, initialCompany = row.companyId)
        "appointment" -> NovaAppointmentScreen(services.appointmentClient(identity), canWrite, onBack, initialCompany = row.companyId)
        "training" -> NovaTrainingRecordScreen(services.trainingClient(identity, userName), row.sourceId, row.companyId, canWrite, onBack)
        "document" -> Column(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            NovaPageHeading("Önceki evrak kaydı", onBack = onBack)
            NovaText("Önceki evrak kaydı · ${row.title}")
        }
        else -> NovaFileLibraryScreen(services.fileClient(identity), services.companyOptions(identity), canWrite, onBack, initialCompany = row.companyId)
    }
}

/** Firmalar (iOS `companies`): the list, and once one is chosen its company page over the same identity. */
@Composable
private fun CompaniesDestination(services: NovaRootServices, identity: IsgWorkspaceIdentity, state: NovaPilotUiState, workspace: NovaWorkspaceUiState?,
                                 navigate: (NovaDestination) -> Unit, reload: () -> Unit, startCreating: Boolean = false) {
    var selected by rememberSaveable { mutableStateOf<String?>(null) }
    // Only a personal account manages its own companies; an OSGB expert works on assigned ones.
    val canCreate = workspace == null && state.writable
    var creating by rememberSaveable { mutableStateOf(startCreating && canCreate) }
    if (creating) {
        NovaCompanyCreateScreen(remember(identity) { services.companyCreateClient(identity) }, onClose = { creating = false }) { company ->
            creating = false; selected = company; reload()
        }
        return
    }
    val items = companyItems(state, workspace)
    val company = selected
    if (company != null) {
        val name = items.firstOrNull { it.id == company }?.name ?: "Firma"
        val scope = remember(identity, company) { services.personnelScope(identity, company) }
        key(company) {
            NovaCompanyWorkspaceScreen(remember(identity, company) { services.companyClient(identity, company) }, company, name, state.writable,
                canManageCompany = workspace == null && state.writable, onBack = { selected = null; reload() },
                onOpenFindings = { navigate(NovaDestination.findings) }) { page, onBack ->
                CompanyPage(services, identity, scope, company, name, state, page, onBack)
            }
        }
        return
    }
    NovaCompaniesScreen(companies = items,
        isLoading = state.overview == null && !state.overviewFailed && workspace == null,
        error = if (state.overviewFailed && workspace == null) "Firmalar yüklenemedi. Lütfen tekrar deneyin." else null,
        isOwnedList = workspace == null, onSelect = { selected = it },
        onBack = { navigate(NovaDestination.home) }, onRetry = reload, onCreate = if (canCreate) ({ creating = true }) else null)
}

/** One module page opened from a company, already narrowed to that company. */
@Composable
private fun CompanyPage(services: NovaRootServices, identity: IsgWorkspaceIdentity, scope: NovaPersonnelScope, company: String, name: String,
                        state: NovaPilotUiState, page: NovaCompanyPage, onBack: () -> Unit) {
    val canWrite = state.writable
    when (page) {
        NovaCompanyPage.Personnel -> NovaPersonnelDestination(scope, name, remember(scope) { services.personnelClient(scope) }, onBack,
            remember(scope) { services.directoryClient(scope) }, canWrite) { employee, writable ->
            key(employee) {
                NovaEmployeeLearningCard({ services.learning(identity, company, employee.toString()) }, services.changes(identity)) { back ->
                    NovaProcessGate(services.processClient(identity), "personnel_certificate", writable, back, initialCompany = company, parent = employee.toString())
                }
            }
        }
        is NovaCompanyPage.Directory -> NovaDirectoryDestination(scope, page.kind, client = remember(scope) { services.directoryClient(scope) },
            canWrite = canWrite, onBack = onBack)
        NovaCompanyPage.Training -> NovaTrainingScreen(services.trainingClient(identity, state.userName), canWrite, onBack, initialCompany = company)
        is NovaCompanyPage.Files -> NovaFileLibraryScreen(services.fileClient(identity), services.companyOptions(identity), canWrite, onBack,
            initialCompany = company, initialCategories = page.categories, headingOverride = page.heading, startInAddMode = page.adding)
        is NovaCompanyPage.Module -> when (page.kind) {
            "risk" -> NovaRiskScreen(services.riskClient(identity), canWrite, onBack, initialCompany = company, startInAddMode = page.adding)
            "equipment" -> NovaEquipmentScreen(services.equipmentClient(identity), canWrite, onBack, initialCompany = company,
                startInAddMode = page.adding, headingOverride = page.heading)
            "appointment" -> NovaAppointmentScreen(services.appointmentClient(identity), canWrite, onBack, initialCompany = company, startInAddMode = page.adding)
            "emergency_plan" -> NovaEmergencyScreen(services.emergencyClient(identity), canWrite, onBack, initialCompany = company, startInAddMode = page.adding)
            "drill" -> NovaDrillScreen(services.drillClient(identity), canWrite, onBack, initialCompany = company)
            "ppe" -> NovaPPEScreen(services.ppeClient(identity), canWrite, onBack, initialCompany = company, startInAddMode = page.adding)
            else -> key(page.kind) { NovaProcessGate(services.processClient(identity), page.kind, canWrite, onBack, initialCompany = company,
                startInAddMode = page.adding) }
        }
        NovaCompanyPage.Editor -> Unit
    }
}

/** Aktivitem with its record links (iOS `openActivityRecord`): a record of another workspace is never opened here. */
@Composable
private fun ActivityDestination(services: NovaRootServices, identity: IsgWorkspaceIdentity, workspaceId: String?, canWrite: Boolean, userName: String,
                                navigate: (NovaDestination) -> Unit, notice: (String) -> Unit) {
    var source by remember { mutableStateOf<NovaFollowupPage.Row?>(null) }
    val row = source
    if (row != null) {
        recordOpener(services, identity, canWrite, userName)(row) { source = null }
        return
    }
    NovaActivityScreen(services.activityClient(identity, workspaceId), onClose = { navigate(NovaDestination.home) }) { detail, companyOnly ->
        val company = detail.linkCompanyId ?: return@NovaActivityScreen
        if (!detail.linkWorkspaceId.orEmpty().equals(workspaceId.orEmpty(), true)) {
            notice("Bu kayıt başka bir çalışma alanına ait. Önce ilgili çalışma alanına geçin.")
            return@NovaActivityScreen
        }
        val kind = mapOf("drill" to "completed_drill", "certificate" to "personnel_certificate", "contract" to "katip_contract", "visit" to "site_visit",
            "board" to "board", "risk" to "risk_assessment", "equipment" to "equipment", "emergency" to "emergency_plan",
            "assignment" to "appointment", "training_session" to "training")[detail.entityType]
        val record = detail.entityId
        if (!companyOnly && record != null && kind != null) {
            source = NovaFollowupPage.Row(kind, company, "", record, record, NovaActivityWords.title(detail.action), null, "active")
        } else navigate(if (companyOnly) NovaDestination.companies else mapOf("nonconformity" to NovaDestination.findings,
            "training" to NovaDestination.training, "file" to NovaDestination.documents, "checklist" to NovaDestination.checklists,
            "ppe" to NovaDestination.ppeHandovers, "permit" to NovaDestination.workPermits, "plan" to NovaDestination.annualWorkPlans)[detail.entityType]
            ?: NovaDestination.companies)
    }
}

/** The module page a tracking row opens (iOS `NovaTrackedModuleDestination`). */
private fun trackedOpener(services: NovaRootServices, identity: IsgWorkspaceIdentity, canWrite: Boolean): NovaTrackedModuleOpener = { kind, company, onBack ->
    when (kind) {
        "emergency_plan" -> NovaEmergencyScreen(services.emergencyClient(identity), canWrite, onBack, initialCompany = company)
        "drill" -> NovaDrillScreen(services.drillClient(identity), canWrite, onBack, initialCompany = company)
        "appointment" -> NovaAppointmentScreen(services.appointmentClient(identity), canWrite, onBack, initialCompany = company)
        "checklist_run" -> NovaChecklistScreen(services.checklistClient(identity), canWrite, onBack, initialCompany = company)
        "ppe" -> NovaPPEScreen(services.ppeClient(identity), canWrite, onBack, initialCompany = company)
        else -> key(kind) { NovaProcessGate(services.processClient(identity), kind, canWrite, onBack, initialCompany = company) }
    }
}

private fun processKind(destination: NovaDestination) = when (destination) {
    NovaDestination.katipContracts -> "katip_contract"; NovaDestination.annualWorkPlans -> "annual_work_plan"
    NovaDestination.boardMeetings -> "board"; NovaDestination.visits, NovaDestination.newVisit -> "site_visit"
    NovaDestination.workPermits -> "work_permit"; else -> "contractor"
}

/** A module whose Android page is not ported yet says so plainly; it never pretends to work. */
@Composable
private fun NovaModulePending(destination: NovaDestination, state: NovaPilotUiState, onWorkspaceSwitch: (() -> Unit)?,
                              onBack: () -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)
        .padding(top = 12.dp, bottom = 24.dp + novaTabBarInset), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        NovaPageHeading(destination.title, onBack = onBack)
        NovaEmptyState("Bu sayfa Android'e taşınıyor",
            "${destination.title} iOS'ta kullanılabiliyor; Android sürümü sıradaki güncellemelerle bu ekrana gelecek. Kayıtlarınız değişmez.")
        NovaCard(Modifier.fillMaxWidth(), padding = 12) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaIcon(if (state.ready) "checkmark.shield" else "lock.shield", 18.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    state.workspaceLabel?.let { NovaText(it, style = NovaTypeToken.bodyStrong) }
                    NovaText(status(state), style = NovaTypeToken.metaQuiet)
                }
            }
        }
        if (onWorkspaceSwitch != null) NovaButton("Çalışma alanını değiştir", onWorkspaceSwitch,
            variant = NovaButtonVariant.Surface, symbol = "arrow.triangle.2.circlepath")
        NovaButton("Ana sayfaya dön", onBack, variant = NovaButtonVariant.Surface, symbol = "chevron.left")
    }
}

private fun status(state: NovaPilotUiState): String = when {
    state.ready && state.isWorkspaceExpert -> state.workspaceLabel?.let { "$it · İSG uzmanı" } ?: "OSGB · İSG uzmanı"
    state.ready -> "Canlı pilot · yalnızca pilot firmalar"
    else -> "Canlı pilot erişimi henüz kullanılamıyor"
}

private fun companyItems(state: NovaPilotUiState, workspace: NovaWorkspaceUiState?): List<NovaCompanyItem> =
    if (workspace != null) workspace.companies.map { NovaCompanyItem(it.id, it.name,
        listOfNotNull(hazardTitle(it.hazardClass), it.sector).filter(String::isNotBlank).joinToString(" · ")) }
    else state.activeCompanies.orEmpty().map { company ->
        NovaCompanyItem(company.id, company.name, listOfNotNull(hazardTitle(company.hazardClass), company.sector)
            .filter(String::isNotBlank).joinToString(" · "),
            progressCompleted = ((company.completionScore ?: 0.0) * 8).toInt().coerceIn(0, 8))
    }

internal fun hazardTitle(value: String): String? = when (value) {
    "low" -> "Az tehlikeli"
    "medium" -> "Tehlikeli"
    "high" -> "Çok tehlikeli"
    else -> value.ifBlank { null }
}

private fun menuAnalysisCount(state: NovaPilotUiState): Int? =
    state.dashboard?.openNonconformities?.toInt() ?: state.activeCompanies?.sumOf { it.findingCount ?: 0 }

private fun menuStats(state: NovaPilotUiState): List<NovaMenuStat> {
    val board = state.dashboard
    val upcoming = board?.let { (it.equipmentDueSoon + it.riskDueSoon).toString() } ?: "—"
    val overdue = board?.overdueNonconformities?.toString() ?: "—"
    val analyses = menuAnalysisCount(state)?.toString() ?: "—"
    return listOf(
        NovaMenuStat("upcoming", "Yaklaşan İşler", upcoming, "calendar.badge.clock", NovaDestination.periodicChecks),
        NovaMenuStat("overdue", "Süresi biten", overdue, "exclamationmark.triangle", NovaDestination.findings),
        NovaMenuStat("analyses", "Analiz", analyses, "photo.on.rectangle.angled", NovaDestination.analyses))
}

private fun nextAction(state: NovaPilotUiState): NovaMenuNextAction? {
    val companies = state.activeCompanies ?: return null
    if (companies.isEmpty()) return NovaMenuNextAction("Firma ekle", "building.2.crop.circle",
        if (state.isWorkspaceExpert) NovaDestination.companies else NovaDestination.newCompany, 0, 1)
    if ((menuAnalysisCount(state) ?: 0) == 0) return NovaMenuNextAction("Fotoğraf analiz et", "camera",
        NovaDestination.newAnalysis, 0, 8)
    var completed = 1
    if ((menuAnalysisCount(state) ?: 0) > 0) completed++
    state.dashboard?.let {
        if (it.trainingCompleted > 0) completed++
        if (it.visitsTotal > 0) completed++
    }
    return NovaMenuNextAction("Risk analizi ekle", "shield.lefthalf.filled", NovaDestination.riskAssessments,
        completed.coerceAtMost(8), 8)
}

private fun dashboardData(state: NovaPilotUiState): NovaDashboardData {
    val companies = state.activeCompanies
    fun sum(pick: (com.riskdetectedan.core.data.nova.NovaCompanySummary) -> Int) = companies?.sumOf(pick)?.toString() ?: "—"
    val metrics = listOf(
        NovaMetricItem("companies", companies?.size?.toString() ?: "—", "Firmalar", "Aktif pilot", "building.2",
            NovaColorToken.accent, NovaDestination.companies),
        NovaMetricItem("personnel", sum { it.personnelCount }, "Personel", "Aktif kayıt", "person.2", NovaColorToken.accent,
            NovaDestination.companies),
        NovaMetricItem("workplaces", sum { it.workplaceCount }, "İşyerleri", "Aktif kayıt", "building.2", NovaColorToken.accent,
            NovaDestination.companies),
        NovaMetricItem("departments", sum { it.departmentCount }, "Departman", "Aktif kayıt", "square.grid.2x2",
            NovaColorToken.accent, NovaDestination.companies),
        NovaMetricItem("equipment", state.dashboard?.equipmentDueSoon?.toString() ?: "—", "Kontrol", "ilgi bekleyen",
            "checkmark.shield", NovaColorToken.accent, NovaDestination.periodicChecks),
    )
    val summary = when {
        state.isWorkspaceExpert -> "Atandığınız firmalardaki toplam güncel kayıtlar."
        companies != null -> "Pilot firmalarınızın güncel kayıtları."
        state.overviewFailed -> "Özet alınamadı. Yenileyerek tekrar deneyin."
        else -> "Özet verileri henüz bağlı değil."
    }
    return NovaDashboardData(state.userName.split(" ").firstOrNull().orEmpty(), null, metrics, null,
        "Gerçekleşen eğitimler ve katılımcı kayıtları", summaryMessage = summary)
}

/** One notice as the shell draws it: kind and company as the detail, lateness in words. */
private fun noticeItem(entry: NovaNoticeEntry): NovaNotice = NovaNotice(entry.key, entry.title,
    listOfNotNull(entry.kind.title, entry.companyName).joinToString(" · "), NovaNoticeWords.badge(entry),
    entry.kind.symbol, entry.severity.tone, entry.unread, entry.dismissed,
    NovaDestination.entries.firstOrNull { it.name == entry.destination } ?: NovaDestination.notifications)

/** Hands screens their service calls without exposing the SDK. */
@dagger.hilt.android.lifecycle.HiltViewModel
class NovaRootServices @javax.inject.Inject constructor(
    private val notices: NovaNoticeService,
    private val findings: NovaNonconformityService,
    private val files: NovaFileLibraryService,
    private val risk: NovaRiskService,
    private val equipment: NovaEquipmentService,
    private val emergency: NovaEmergencyService,
    private val drills: NovaDrillService,
    private val appointments: NovaAppointmentService,
    private val ppe: NovaPPEService,
    private val katip: NovaKatipService,
    private val process: NovaProcessService,
    private val followups: NovaFollowupService,
    private val checklists: NovaChecklistService,
    private val checklistQueue: NovaChecklistOfflineQueue,
    private val training: NovaTrainingService,
    private val statistics: NovaStatisticsService,
    private val activity: NovaActivityService,
    val presence: NovaUsagePresence,
    private val personnel: com.riskdetectedan.core.data.company.PersonnelRepository,
    private val overview: NovaOverviewService,
    private val companyRecords: com.riskdetectedan.core.data.company.CompanyRepository,
    private val companyCreate: NovaCompanyCreateService,
    private val learning: NovaEmployeeLearningService,
    val events: NovaRecordEvents,
) : androidx.lifecycle.ViewModel() {
    private fun companies(identity: IsgWorkspaceIdentity): suspend () -> List<NovaCompanyOption> =
        { runCatching { findings.companyOptions(identity) }.getOrDefault(emptyList()) }
    fun fileClient(identity: IsgWorkspaceIdentity) = NovaFileClient(files, identity)
    /** Active personnel of one company, every page, capped like iOS at a thousand names. */
    private fun people(identity: IsgWorkspaceIdentity): suspend (String) -> List<NovaPersonOption> = { company ->
        val rows = mutableListOf<NovaPersonOption>()
        var cursor: String? = null
        do {
            val page = personnel.read(identity.userId, identity.sessionId, company, "employees", cursor = cursor)
            page["rows"]?.jsonArray?.forEach { row ->
                val entry = row.jsonObject
                rows += NovaPersonOption(entry.getValue("id").jsonPrimitive.content, entry.getValue("name").jsonPrimitive.content)
            }
            cursor = page["next"]?.jsonPrimitive?.contentOrNull
        } while (cursor != null && rows.size < 1_000)
        rows
    }
    fun emergencyClient(identity: IsgWorkspaceIdentity) =
        NovaServiceEmergencyClient(emergency, identity, companies(identity), fileClient(identity), people(identity))
    fun personnelScope(identity: IsgWorkspaceIdentity, company: String) = NovaPersonnelScope(java.util.UUID.fromString(identity.userId),
        java.util.UUID.fromString(identity.sessionId), java.util.UUID.fromString(company), "pilot-$company")
    fun personnelClient(scope: NovaPersonnelScope) = personnel.novaClient { scope }
    fun directoryClient(scope: NovaPersonnelScope) = personnel.novaDirectoryClient { scope }
    private fun <T> com.riskdetectedan.core.common.RdResult<T>.value(): T = when (this) {
        is com.riskdetectedan.core.common.RdResult.Success -> value
        is com.riskdetectedan.core.common.RdResult.Failure -> throw IllegalStateException(message)
    }
    suspend fun learning(identity: IsgWorkspaceIdentity, company: String, employee: String) = learning.load(identity, company, employee)
    fun companyCreateClient(identity: IsgWorkspaceIdentity) = NovaCompanyCreateClient(identity.userId, { companyCreate.pending(identity) },
        { intent -> companyCreate.create(identity, intent) }, { company, profile -> companyRecords.saveCompanyProfile(company, profile).value() })
    /** Every read and write the company page needs, bound to one identity and company. */
    fun companyClient(identity: IsgWorkspaceIdentity, company: String) = NovaCompanyWorkspaceClient(
        summary = { overview.overview(identity, company).firstOrNull { it.id.equals(company, true) } },
        record = { companyRecords.listCompanies(includeArchived = true).value().firstOrNull { it.id.equals(company, true) } },
        logo = { path -> (companyRecords.downloadLogo(path) as? com.riskdetectedan.core.common.RdResult.Success)?.value },
        saveLogo = { record, jpeg ->
            val path = companyRecords.uploadLogo(identity.userId, record.id, jpeg).value()
            companyRecords.saveCompany(identity.userId, com.riskdetectedan.core.data.company.CompanyDraft(id = record.id, name = record.name,
                hazardClass = record.hazardClass, logoPath = path, address = record.address.orEmpty(), contactPerson = record.contactPerson.orEmpty(),
                department = record.department.orEmpty(), defaultResponsible = record.defaultResponsible.orEmpty(),
                defaultDueDaysText = record.defaultDueDays?.toString().orEmpty())).value().also { events.recordsChanged(identity.userId) }
        },
        saveCompany = { draft -> companyRecords.saveCompany(identity.userId, draft).value().also { events.recordsChanged(identity.userId) } },
        nonconformities = { findings.list(NovaCompanyScope(identity, company)) },
        completedTrainings = { training.completed(identity, company) },
        tracking = { statistics.tracking(identity, company) },
        equipment = { equipment.board(identity, NovaEquipmentQuery(company = company, limit = 5)) },
        risk = { risk.board(identity, NovaRiskQuery(company = company, limit = 1)) },
        appointments = { role -> appointments.board(identity, NovaAppointmentQuery(company = company, role = role.wire, limit = 1)) },
        fileCategories = { files.catalogue(identity).categories },
        files = { files.library(identity, NovaFileQuery(company = company, limit = 1)) },
        changes = changes(identity),
    )
    fun activityClient(identity: IsgWorkspaceIdentity, workspace: String?, member: String? = null) =
        NovaServiceActivityClient(activity, identity, workspace, member)
    fun reportClient(identity: IsgWorkspaceIdentity) = NovaServiceReportClient(training, process, statistics, identity, companies(identity))
    fun statisticsClient(identity: IsgWorkspaceIdentity) = NovaServiceStatisticsClient(statistics, process, followups, identity, changes(identity))
    fun trainingClient(identity: IsgWorkspaceIdentity, userName: String) =
        NovaServiceTrainingClient(training, identity, companies(identity), userName, people(identity))
    fun checklistClient(identity: IsgWorkspaceIdentity) = NovaServiceChecklistClient(checklists, checklistQueue, files, identity, companies(identity))
    fun companyOptions(identity: IsgWorkspaceIdentity) = companies(identity)
    suspend fun followup(identity: IsgWorkspaceIdentity, company: String?, status: String?, query: String, offset: Int) =
        followups.load(identity, company, status, query, offset)
    suspend fun fileSources(identity: IsgWorkspaceIdentity, entry: NovaFileEntry) = followups.fileSources(identity, entry)
    /** This account's record changes, as the iOS `isgada.records.changed` notification. */
    fun changes(identity: IsgWorkspaceIdentity) = events.changed.filter { it.userId == identity.userId }.map { }
    fun processClient(identity: IsgWorkspaceIdentity) = NovaServiceProcessClient(process, identity, companies(identity), fileClient(identity))
    fun katipClient(identity: IsgWorkspaceIdentity) = NovaServiceKatipClient(katip, files, identity, companies(identity))
    fun ppeClient(identity: IsgWorkspaceIdentity) = NovaServicePPEClient(ppe, identity, companies(identity))
    fun appointmentClient(identity: IsgWorkspaceIdentity) = NovaServiceAppointmentClient(appointments, identity, companies(identity), fileClient(identity))
    fun drillClient(identity: IsgWorkspaceIdentity) = NovaServiceDrillClient(drills, identity, companies(identity))
    fun equipmentClient(identity: IsgWorkspaceIdentity) = NovaServiceEquipmentClient(equipment, identity, companies(identity), fileClient(identity))
    fun riskClient(identity: IsgWorkspaceIdentity) = NovaServiceRiskClient(risk, identity, companies(identity), fileClient(identity))

    fun noticeClient(identity: IsgWorkspaceIdentity) = NovaNoticeClient(
        feed = { scope -> notices.feed(identity, scope = scope) },
        read = { notices.read(identity, it) }, readAll = { notices.readAll(identity) },
        dismiss = { notices.dismiss(identity, it) }, dismissAll = { notices.dismissAll(identity) },
        restore = { notices.restore(identity, it) })
}
