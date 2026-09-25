package com.riskdetectedan.feature.nova

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.saveable.rememberSaveable
import com.riskdetectedan.feature.profile.novaClient
import com.riskdetectedan.feature.profile.novaDirectoryClient
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.isg.IsgWorkspaceContext
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonPrimitive
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
                  onWorkspaceSwitch: (() -> Unit)?, workspaceStore: NovaWorkspaceStore? = null, viewModel: NovaPilotViewModel = hiltViewModel(),
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
    // iOS reads one equipment page for the menu and home counters, again whenever the page changes.
    var equipmentBoard by remember(identity) { mutableStateOf<NovaEquipmentBoard?>(null) }
    var homePendingActionCount by remember(identity) { mutableStateOf<Int?>(null) }
    LaunchedEffect(identity, workspaceId, state.navigation.selected) {
        equipmentBoard = try { services.equipmentSummary(identity) }
            catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled } catch (_: Exception) { equipmentBoard }
    }
    // A notice opens its own record over the shell (iOS `openNotice`); training rows are matched to their session first.
    val coroutines = rememberCoroutineScope()
    var noticeRecord by remember(identity) { mutableStateOf<NovaFollowupPage.Row?>(null) }
    val recordChanges = remember(identity) { services.changes(identity) }
    fun openNotice(key: String) {
        val entry = notices.rows.firstOrNull { it.key == key } ?: return
        val company = entry.companyId ?: return
        val record = entry.recordId ?: return
        if (entry.kind == NovaNoticeKind.training) coroutines.launch {
            try {
                val page = services.followup(identity, company, null, entry.title.take(100), 0)
                page.rows.firstOrNull { it.recordId.equals(record, true) }?.let { noticeRecord = it }
                    ?: NovaDestination.entries.firstOrNull { it.name == entry.destination }?.let(navigate)
            } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled } catch (_: Exception) {
                viewModel.showMessage("Bildirim kaydı açılamadı. Yeniden deneyin.")
            }
        } else noticeRecord = NovaFollowupPage.Row(if (entry.kind == NovaNoticeKind.drill) "completed_drill" else entry.kind.wire, company,
            entry.companyName.orEmpty(), record, record, entry.title, null, entry.dueOn,
            if (entry.severity == NovaNoticeSeverity.overdue) "expired" else "soon")
    }
    // iOS home: the six newest analyses under the expert's own method, reread on each workspace/overview change.
    var recentAnalyses by remember(identity) { mutableStateOf<List<NovaRecentAnalysis>>(emptyList()) }
    var pendingAnalysis by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(identity, workspaceId, state.overview) {
        recentAnalyses = runCatching {
            services.analysis.summaries(identity, services.analysis.preferredMethod(identity), limit = 6).first.map {
                NovaRecentAnalysis(it.id.lowercase(), NovaAnalysisPresentation.title(it.title), it.companyName ?: "Firmasız",
                    NovaAnalysisPresentation.dateOnly(it.createdOn))
            }
        }.getOrDefault(emptyList())
    }
    // "Senin İçin" (iOS `forYouFeed`): the last answer, which also feeds the menu's next action, and what a
    // card asked its destination to open with. Each destination clears its request when it leaves.
    var forYouFeed by remember(identity) { mutableStateOf(services.forYou.cached(identity)) }
    var pendingFollowupStatus by remember(identity) { mutableStateOf<String?>(null) }
    var pendingRiskRecord by remember(identity) { mutableStateOf<String?>(null) }
    var pendingRiskWizard by remember(identity) { mutableStateOf(false) }
    var pendingEmergencyWizard by remember(identity) { mutableStateOf(false) }
    var pendingRecord by remember(identity) { mutableStateOf<NovaRecordTarget?>(null) }
    var pendingChecklistRun by remember(identity) { mutableStateOf<String?>(null) }
    var pendingListPreset by remember(identity) { mutableStateOf<NovaListPreset?>(null) }
    val routes = forYouRoutes(state.navigation, state.isWorkspaceExpert)
    fun openForYou(card: NovaForYouCard) {
        val target = card.target
        when (target.route) {
            // A dated record opens the way the deadline board opens it: the row comes from the same read.
            "followup_record" -> {
                val kind = target.kind; val record = target.id; val company = target.companyId
                if (kind == null || record == null || company == null) {
                    pendingFollowupStatus = target.status; navigate(NovaDestination.documentChecklist)
                } else coroutines.launch {
                    try {
                        val page = services.followup(identity, company, target.status, "", 0, kind)
                        page.rows.firstOrNull { it.recordId.equals(record, true) }?.let { noticeRecord = it } ?: run {
                            pendingFollowupStatus = target.status; navigate(NovaDestination.documentChecklist)
                        }
                    } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled } catch (_: Exception) {
                        viewModel.showMessage("Kayıt açılamadı. Yeniden deneyin.")
                    }
                }
            }
            "followup" -> { pendingFollowupStatus = target.status; navigate(NovaDestination.documentChecklist) }
            "analysis" -> { pendingAnalysis = target.id; navigate(NovaDestination.analyses) }
            "photo_analysis" -> navigate(NovaDestination.newAnalysis)
            "statistics" -> navigate(NovaDestination.statistics)
            "risk_assessment" -> { pendingRiskRecord = target.id; navigate(NovaDestination.riskAssessments) }
            "risk_wizard" -> { pendingRiskWizard = true; navigate(NovaDestination.riskAssessments) }
            "emergency_wizard" -> { pendingEmergencyWizard = true; navigate(NovaDestination.emergencyPlans) }
            "training_create" -> navigate(NovaDestination.newTraining)
            "nonconformity_create" -> navigate(NovaDestination.newFinding)
            "equipment" -> navigate(NovaDestination.periodicChecks)
            "personnel" -> navigate(NovaDestination.companies)
            "work_permit_forms" -> navigate(NovaDestination.workPermits)
            "ppe_form" -> navigate(NovaDestination.ppeHandovers)
            "company_create" -> if (!state.isWorkspaceExpert) navigate(NovaDestination.newCompany)
            "nonconformity" -> {
                val id = target.id; val company = target.companyId
                if (id != null && company != null) pendingRecord = NovaRecordTarget(id, company)
                navigate(NovaDestination.findings)
            }
            "checklist_run" -> { pendingChecklistRun = target.id; navigate(NovaDestination.checklists) }
            // The list opens on exactly the records the card counted, under the card's own words.
            "nonconformities", "analyses", "trainings" -> {
                pendingListPreset = NovaListPreset.of(NovaForYouCopy.make(card)?.title.orEmpty(), target, identity.userId)
                navigate(when (target.route) {
                    "nonconformities" -> NovaDestination.findings
                    "analyses" -> NovaDestination.analyses
                    else -> NovaDestination.training
                })
            }
            "checklists" -> navigate(NovaDestination.checklists)
        }
    }
    // The notebook is offered only when the server's personal_notes rollout says so (iOS NotebookUIRelease).
    var notebookAvailable by remember { mutableStateOf(false) }
    LaunchedEffect(identity) { notebookAvailable = services.notebook.enabled() }
    // An invite link or the menu's invite banner lands on the profile, which opens the invite page (iOS `.referral`).
    val referral: com.riskdetectedan.feature.profile.ReferralRewardsViewModel = hiltViewModel()
    val referralRequested by referral.openRequested.collectAsState()
    LaunchedEffect(referralRequested) { if (referralRequested) navigate(NovaDestination.profile) }
    NovaExpertShell(state.navigation, state.userName, viewModel::apply,
        profileAvatar = state.avatar, menuRoleTitle = "İSG Uzmanı", notebookAvailable = notebookAvailable,
        menuStats = menuStats(state, equipmentBoard), menuNextAction = forYouNextAction(forYouFeed, ::openForYou),
        hasUnread = notices.unread > 0, unreadCount = notices.unread,
        pendingActionCount = homePendingActionCount,
        notices = notices.rows.map(::noticeItem),
        noticeNote = if (notices.rows.isEmpty()) "" else NovaNoticeWords.dismissNote,
        connectionLabel = status(state),
        actions = NovaShellActions(
            onReadNotice = { viewModel.markNotice("read", it) },
            onDismissNotice = { viewModel.markNotice("dismiss", it) },
            onRestoreNotice = { viewModel.markNotice("restore", it) },
            onReadAll = { viewModel.markNotice("read_all") },
            onClearNotifications = { viewModel.markNotice("dismiss_all") },
            onOpenNotice = ::openNotice,
            // Only a personal account opens a company of its own (iOS `onCompanyCreate`).
            onCompanyCreate = if (state.isWorkspaceExpert) null else ({ navigate(NovaDestination.newCompany) }),
            onInvite = referral::requestOpen,
            onLogout = viewModel::signOut,
        )) { destination ->
        when (destination) {
            NovaDestination.home -> NovaDashboardScreen(dashboardData(state, equipmentBoard).copy(recentAnalyses = recentAnalyses), onNavigate = navigate,
                onPhoto = { navigate(NovaDestination.newAnalysis) },
                analysisThumbnail = { id ->
                    services.analysis.thumbnail(id, workspace?.selection)?.let { bytes ->
                        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
                            android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
                        }
                    }
                },
                onOpenAnalysis = { id -> pendingAnalysis = id; navigate(NovaDestination.analyses) },
                tracking = {
                    NovaHomeDeadlineBoard({ status, offset -> services.followup(identity, null, status, "", offset) },
                        recordChanges, scopeKey = workspaceId, onPendingActionCount = { homePendingActionCount = it },
                        onOpen = { row -> noticeRecord = row })
                },
                forYou = {
                    NovaForYouHost(load = { services.forYou.load(identity, routes, personal = !state.isWorkspaceExpert) },
                        pending = { services.forYou.pending(services.forYou.namespace(identity)) },
                        record = { services.forYou.record(identity, it) }, changes = recordChanges,
                        refreshKey = listOf(workspaceId, state.overview, routes), onOpen = ::openForYou,
                        onFeed = { forYouFeed = it }, cached = services.forYou.cached(identity),
                        rotation = remember(services.forYou.namespace(identity)) { services.forYou.rotation(identity) })
                })
            NovaDestination.notifications -> NovaNoticeCenterScreen(services.noticeClient(identity),
                onOpen = { raw -> NovaDestination.entries.firstOrNull { it.name == raw }?.let(navigate) },
                onBack = { navigate(NovaDestination.home) })
            NovaDestination.profile -> Column(Modifier.fillMaxSize()) {
                NovaPageHeading("Profil", modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) { navigate(NovaDestination.home) }
                // A personal account's "Firmalarım" opens its own companies here, where iOS opens the same
                // company page through NovaCompanyManagementGate; an OSGB expert keeps the app route.
                CompositionLocalProvider(LocalNovaOpenCompanies provides if (workspace == null) ({ navigate(NovaDestination.companies) }) else null,
                    LocalNovaPilotNavigate provides navigate) {
                    Box(Modifier.weight(1f)) { slots.profile { navigate(NovaDestination.home) } }
                }
            }
            NovaDestination.findings -> if (state.overviewFailed) NovaPilotStatusPage(destination, state, onWorkspaceSwitch, viewModel::reload) {
                navigate(NovaDestination.home)
            } else {
                DisposableEffect(Unit) { onDispose { pendingListPreset = null } }
                NovaFindingsDestination(identity, NovaFindingsSurface.board, state.writable, navigate, workspace?.selection,
                    initialRecord = pendingRecord, onInitialRecordOpened = { pendingRecord = null },
                    onRecordFailed = { viewModel.showMessage("Kayıt açılamadı. Yeniden deneyin.") },
                    initialPreset = pendingListPreset, onPresetCleared = { pendingListPreset = null })
            }
            NovaDestination.newFinding -> NovaFindingsDestination(identity, NovaFindingsSurface.addFinding, state.writable, navigate)
            NovaDestination.companies, NovaDestination.newCompany -> key(destination) {
                CompaniesDestination(services, identity, state, workspace, workspaceStore, navigate, viewModel::reload,
                    startCreating = destination == NovaDestination.newCompany)
            }
            NovaDestination.riskAssessments -> {
                DisposableEffect(Unit) { onDispose { pendingRiskRecord = null; pendingRiskWizard = false } }
                NovaRiskScreen(services.riskClient(identity), state.writable, onBack = { navigate(NovaDestination.home) },
                    initialRecordId = pendingRiskRecord, startWithWizard = pendingRiskWizard)
            }
            NovaDestination.periodicChecks -> NovaEquipmentScreen(services.equipmentClient(identity), state.writable,
                onBack = { navigate(NovaDestination.home) })
            NovaDestination.emergencyPlans -> {
                DisposableEffect(Unit) { onDispose { pendingEmergencyWizard = false } }
                NovaEmergencyScreen(services.emergencyClient(identity), state.writable, onBack = { navigate(NovaDestination.home) },
                    startWithWizard = pendingEmergencyWizard)
            }
            NovaDestination.drills -> NovaDrillScreen(services.drillClient(identity), state.writable, onBack = { navigate(NovaDestination.home) })
            NovaDestination.appointments -> NovaAppointmentScreen(services.appointmentClient(identity), state.writable,
                onBack = { navigate(NovaDestination.home) })
            NovaDestination.ppeHandovers -> NovaPPEExampleScreen(onBack = { navigate(NovaDestination.home) })
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
            NovaDestination.documentChecklist -> {
                DisposableEffect(Unit) { onDispose { pendingFollowupStatus = null } }
                NovaFollowupScreen({ company, status, kind, query, offset -> services.followup(identity, company, status, query, offset, kind) },
                    services.companyOptions(identity), services.changes(identity), recordOpener(services, identity, state.writable, state.userName),
                    onBack = { navigate(NovaDestination.home) }, initialStatus = pendingFollowupStatus)
            }
            NovaDestination.training, NovaDestination.newTraining -> key(destination) {
                DisposableEffect(Unit) { onDispose { pendingListPreset = null } }
                NovaTrainingScreen(services.trainingClient(identity, state.userName), state.writable, onBack = { navigate(NovaDestination.home) },
                    createOnOpen = destination == NovaDestination.newTraining,
                    initialPreset = if (destination == NovaDestination.training) pendingListPreset else null,
                    onPresetCleared = { pendingListPreset = null })
            }
            NovaDestination.statistics -> if (state.overviewFailed) NovaPilotStatusPage(destination, state, onWorkspaceSwitch, viewModel::reload) {
                navigate(NovaDestination.home)
            } else NovaStatisticsScreen(services.statisticsClient(identity), onBack = { navigate(NovaDestination.home) },
                onNavigate = navigate, openTracked = trackedOpener(services, identity, state.writable)) { company, onBack ->
                NovaFollowupScreen({ selected, status, kind, query, offset -> services.followup(identity, selected, status, query, offset, kind) },
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
            NovaDestination.analyses -> {
                DisposableEffect(Unit) { onDispose { pendingListPreset = null } }
                AnalysesDestination(services, identity, workspace, state.writable, navigate, pendingAnalysis, { pendingAnalysis = null },
                    initialPreset = pendingListPreset, onPresetCleared = { pendingListPreset = null })
            }
            NovaDestination.newAnalysis -> PhotoAnalysisDestination(services, identity, workspace, state.writable, navigate)
            NovaDestination.checklists -> {
                DisposableEffect(Unit) { onDispose { pendingChecklistRun = null } }
                NovaChecklistScreen(services.checklistClient(identity), state.writable, onBack = { navigate(NovaDestination.home) },
                    initialRunId = pendingChecklistRun)
            }
        }
    }
    noticeRecord?.let { row ->
        // Opaque and touch-absorbing: the record sits over the shell, never beside it.
        Box(Modifier.fillMaxSize().background(NovaColorToken.canvas.color())
            .pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent() } }) {
            recordOpener(services, identity, state.writable, state.userName)(row) { noticeRecord = null }
        }
    }
    NovaNoticeDialog(state.message, "İSGADA pilot", viewModel::dismissMessage)
}

/**
 * Fotoğraf Analizi (iOS `NovaPilotFindingsGate` photo surface): photos, then company, sector and focus in one popup,
 * then the waiting page; the finished analysis opens over it. Nothing is filled in behind the expert's answers.
 */
@Composable
private fun PhotoAnalysisDestination(services: NovaRootServices, identity: IsgWorkspaceIdentity, workspace: NovaWorkspaceUiState?, canWrite: Boolean,
                                     navigate: (NovaDestination) -> Unit) {
    val coroutines = rememberCoroutineScope()
    val context = workspace?.selection
    val organization = context != null
    var images by remember { mutableStateOf<List<android.graphics.Bitmap>>(emptyList()) }
    var companies by remember { mutableStateOf<List<NovaAnalysisCompanyOption>>(emptyList()) }
    var tier by remember { mutableStateOf<com.riskdetectedan.core.data.profile.SubscriptionTier?>(null) }
    var draft by remember { mutableStateOf(NovaAnalysisIntakeDraft()) }
    var intakeOpen by remember { mutableStateOf(false) }
    var running by remember { mutableStateOf(false) }
    var stage by remember { mutableStateOf<NovaAnalysisService.Progress?>(null) }
    var finished by rememberSaveable { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(identity) {
        companies = runCatching { services.analysis.companyOptions(identity) }.getOrDefault(emptyList())
        tier = runCatching { services.analysis.tier(identity) }.getOrNull()
    }
    finished?.let { id ->
        val cached = remember(identity) { mutableStateOf<NovaRiskMethod?>(null) }
        val method: suspend () -> NovaRiskMethod = { cached.value ?: services.analysis.preferredMethod(identity).also { cached.value = it } }
        NovaAnalysisDetailScreen(remember(identity, id) { services.analysisDetailClient(identity, context, id, method) },
            onBack = { finished = null; navigate(NovaDestination.analyses) }, canWrite = canWrite && (context?.canOperate ?: true))
        return
    }
    if (running) { NovaAnalyzingScreen(images.firstOrNull(), images.size, stage); return }
    NovaPhotoIntakeScreen(images, { images = it }, onStart = {
        // The workspace already has a company in scope: offer it rather than asking again.
        val current = workspace?.selectedCompanyId?.let { id -> companies.firstOrNull { it.id.equals(id, true) } }
        draft = NovaAnalysisIntakeDraft(photoCount = images.size).let { if (current != null) it.chooseOwner(current) else it }
        intakeOpen = true
    }, onBack = { navigate(NovaDestination.findings) })
    NovaPopup(intakeOpen, { if (!running) intakeOpen = false }, identifier = "analysis.intake") {
        NovaAnalysisIntakePopup(companies, tier, organization, draft, { draft = it }, running) {
            val focuses = draft.focusIds.filter { id -> organization || AnalysisCanvasTier.allowed(id, tier) }
            if (!draft.isReady || images.isEmpty()) return@NovaAnalysisIntakePopup
            if (focuses.isEmpty()) { notice = "Planınızın kapsadığı en az bir odak seçin."; return@NovaAnalysisIntakePopup }
            intakeOpen = false; running = true; stage = null
            coroutines.launch {
                try {
                    val bytes = analysisPhotoBytes(images)
                    val id = services.analysis.run(identity, context, draft.companyId, bytes, focuses, draft.sectorId) { stage = it }
                    images = emptyList()
                    services.events.recordsChanged(identity.userId)
                    finished = id
                } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled } catch (_: Exception) {
                    notice = "Analiz tamamlanamadı. Bağlantınızı kontrol edip tekrar deneyin."
                }
                running = false
            }
        }
    }
    NovaNoticeDialog(notice, "Fotoğraf Analizi", { notice = null })
}

/** Which focuses the account's plan includes; a locked one is shown, never sent. */
private object AnalysisCanvasTier {
    fun allowed(id: String, tier: com.riskdetectedan.core.data.profile.SubscriptionTier?) =
        com.riskdetectedan.core.data.analysis.AnalysisCanvas.all.firstOrNull { it.id == id }?.let { tier?.includes(it.minTier) == true } == true
}

/**
 * Analizler (iOS `NovaPilotFindingsGate` analyses surface): the list, the report archive, and an analysis opened over
 * them. The expert's own method opens every page.
 */
@Composable
private fun AnalysesDestination(services: NovaRootServices, identity: IsgWorkspaceIdentity, workspace: NovaWorkspaceUiState?, canWrite: Boolean,
                                navigate: (NovaDestination) -> Unit, initialAnalysis: String? = null, onInitialOpened: () -> Unit = {},
                                initialPreset: NovaListPreset? = null, onPresetCleared: () -> Unit = {}) {
    var reports by rememberSaveable { mutableStateOf(false) }
    var open by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(initialAnalysis) { initialAnalysis?.let { open = it; onInitialOpened() } }
    val context = workspace?.selection
    val cached = remember(identity) { mutableStateOf<NovaRiskMethod?>(null) }
    val method: suspend () -> NovaRiskMethod = { cached.value ?: services.analysis.preferredMethod(identity).also { cached.value = it } }
    open?.let { id ->
        key(id) {
            NovaAnalysisDetailScreen(remember(identity, id) { services.analysisDetailClient(identity, context, id, method) }, onBack = { open = null },
                canWrite = canWrite && (context?.canOperate ?: true))
        }
        return
    }
    if (reports) NovaAnalysisReportsScreen(load = { offset -> services.analysis.reports(identity, offset = offset) },
        download = { entry -> services.analysis.downloadReport(entry, identity, context) }, onBack = { reports = false }, onOpenAnalysis = { open = it })
    else NovaAnalysisListScreen(remember(identity, context) { services.analysisListClient(identity, context, method) }, onOpen = { open = it },
        onBack = { navigate(NovaDestination.findings) }, onNewPhotoAnalysis = { navigate(NovaDestination.newAnalysis) }, onReports = { reports = true },
        initialPreset = initialPreset, onPresetCleared = onPresetCleared)
}

/** Opens the module record a followup row or a file link points at (iOS `NovaFollowupDestination`). */
internal fun recordOpener(services: NovaRootServices, identity: IsgWorkspaceIdentity, canWrite: Boolean, userName: String): NovaRecordOpener = { row, onBack ->
    when (row.kind) {
        "completed_drill", "personnel_certificate", "katip_contract", "approved_notebook", "site_visit", "board", "board_decision", "annual_work_item" ->
            NovaProcessEditor(services.processClient(identity), row.kind, row.companyId, null, row.recordId, canWrite, onBack)
        "risk_assessment" -> NovaRiskScreen(services.riskClient(identity), canWrite, onBack,
            initialCompany = row.companyId, initialRecordId = row.recordId)
        "equipment" -> NovaEquipmentScreen(services.equipmentClient(identity), canWrite, onBack,
            initialCompany = row.companyId, initialRecordId = row.recordId)
        "emergency_plan" -> NovaEmergencyScreen(services.emergencyClient(identity), canWrite, onBack,
            initialCompany = row.companyId, initialRecordId = row.recordId)
        "appointment" -> NovaAppointmentScreen(services.appointmentClient(identity), canWrite, onBack,
            initialCompany = row.companyId, initialRecordId = row.recordId)
        "training" -> NovaTrainingRecordScreen(services.trainingClient(identity, userName), row.sourceId, row.companyId, canWrite, onBack)
        "document" -> NovaDocumentTrackingScreen(services.documentClient(identity), row.companyId,
            "Önceki Evrak Kayıtları", onBack, initialRecordId = row.recordId)
        "file" -> NovaFileLibraryScreen(services.fileClient(identity), services.companyOptions(identity), canWrite, onBack,
            initialCompany = row.companyId, initialEntryId = row.recordId)
        else -> NovaFileLibraryScreen(services.fileClient(identity), services.companyOptions(identity), canWrite, onBack, initialCompany = row.companyId)
    }
}

/** Firmalar (iOS `companies`): the list, and once one is chosen its company page over the same identity. */
@Composable
private fun CompaniesDestination(services: NovaRootServices, identity: IsgWorkspaceIdentity, state: NovaPilotUiState, workspace: NovaWorkspaceUiState?, workspaceStore: NovaWorkspaceStore?,
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
        onBack = { navigate(NovaDestination.home) }, onRetry = reload, onCreate = if (canCreate) ({ creating = true }) else null,
        loadLogo = if (workspace == null) remember(identity) { services.ownedCompanyLogos() }
            else workspaceStore?.let { store -> { id, _ -> store.companyLogo(id)?.let { bytes -> decodeLogo(bytes) } } })
}

/** One module page opened from a company, already narrowed to that company. */
@Composable
private fun CompanyPage(services: NovaRootServices, identity: IsgWorkspaceIdentity, scope: NovaPersonnelScope, company: String, name: String,
                        state: NovaPilotUiState, page: NovaCompanyPage, onBack: () -> Unit) {
    val canWrite = state.writable
    when (page) {
        NovaCompanyPage.Personnel -> NovaPersonnelDestination(scope, name, remember(scope) { services.personnelClient(scope) }, onBack,
            remember(scope) { services.directoryClient(scope) }, canWrite, employeeExtra = { employee, _ ->
            key(employee) { NovaEmployeeLearningCard({ services.learning(identity, company, employee.toString()) }, services.changes(identity)) }
        }, employeeCertificates = { employee, writable, back ->
            NovaEmployeeCertificatesScreen(remember(identity) { services.employeeCertificatesClient(identity, state.userName) }, company,
                employee.toString(), writable, back) { closeOthers ->
                NovaProcessGate(services.processClient(identity), "personnel_certificate", writable, closeOthers, initialCompany = company, parent = employee.toString())
            }
        })
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
            "ppe" -> NovaPPEExampleScreen(onBack)
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
            source = NovaFollowupPage.Row(kind, company, "", record, record, NovaActivityWords.title(detail.action), null, null, "active")
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
        "ppe" -> NovaPPEExampleScreen(onBack)
        else -> key(kind) { NovaProcessGate(services.processClient(identity), kind, canWrite, onBack, initialCompany = company) }
    }
}

private fun processKind(destination: NovaDestination) = when (destination) {
    NovaDestination.katipContracts -> "katip_contract"; NovaDestination.annualWorkPlans -> "annual_work_plan"
    NovaDestination.boardMeetings -> "board"; NovaDestination.visits, NovaDestination.newVisit -> "site_visit"
    NovaDestination.workPermits -> "work_permit"; else -> "contractor"
}

/** A module whose Android page is not ported yet says so plainly; it never pretends to work. */

/**
 * What a page shows while the pilot access cannot be confirmed (iOS `statusCard`): the workspace, its state, the
 * way to another workspace, and a retry.
 */
@Composable
private fun NovaPilotStatusPage(destination: NovaDestination, state: NovaPilotUiState, onWorkspaceSwitch: (() -> Unit)?, onRetry: () -> Unit,
                                onBack: () -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)
        .padding(top = 12.dp, bottom = 24.dp + novaTabBarInset), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        NovaPageHeading(destination.title, onBack = onBack)
        NovaCard(Modifier.fillMaxWidth(), padding = 12) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                NovaIcon("lock.shield", 18.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    state.workspaceLabel?.let { NovaText(it, style = NovaTypeToken.bodyStrong) }
                    NovaText(status(state), style = NovaTypeToken.metaQuiet)
                }
            }
        }
        NovaText("Bu sayfa için canlı pilot erişimi doğrulanamadı. Bağlantınızı kontrol edip tekrar deneyin.")
        NovaButton("Pilot erişimini tekrar kontrol et", onRetry, variant = NovaButtonVariant.Surface, symbol = "arrow.clockwise")
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

/** A stored logo, decoded off the main thread; an unreadable image keeps the initials. */
private suspend fun decodeLogo(bytes: ByteArray) = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
    android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
}

private fun companyItems(state: NovaPilotUiState, workspace: NovaWorkspaceUiState?): List<NovaCompanyItem> =
    if (workspace != null) workspace.companies.map { NovaCompanyItem(it.id, it.name,
        listOfNotNull(hazardTitle(it.hazardClass), it.sector).filter(String::isNotBlank).joinToString(" · "),
        progressCompleted = it.profileCompletionCount, progressTotal = 8) }
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

private fun menuStats(state: NovaPilotUiState, equipment: NovaEquipmentBoard?): List<NovaMenuStat> {
    val board = state.dashboard
    // A personal account has no workspace dashboard; its equipment page carries the dates instead (iOS).
    val upcoming = board?.let { (it.equipmentDueSoon + it.riskDueSoon).toString() } ?: equipment?.needsAttention?.toString() ?: "—"
    val overdue = board?.overdueNonconformities?.toString() ?: equipment?.let { (it.counts[NovaEquipmentState.overdue] ?: 0).toString() } ?: "—"
    val analyses = menuAnalysisCount(state)?.toString() ?: "—"
    return listOf(
        NovaMenuStat("upcoming", "Yaklaşan İşler", upcoming, "calendar.badge.clock", NovaDestination.periodicChecks),
        NovaMenuStat("overdue", "Süresi biten", overdue, "exclamationmark.triangle", NovaDestination.findings),
        NovaMenuStat("analyses", "Analiz", analyses, "photo.on.rectangle.angled", NovaDestination.analyses))
}

/** The menu's "Sıradaki işin": the first unfinished item or first step "Senin İçin" offers (iOS `menuNextAction`). */
private fun forYouNextAction(feed: NovaForYouFeed?, open: (NovaForYouCard) -> Unit): NovaMenuNextAction? {
    val steps = setOf("motivation.first_company", "motivation.first_personnel", "motivation.first_analysis")
    val card = feed?.let { (it.cards + it.more).firstOrNull { card -> card.kind == "continue" || card.key in steps } } ?: return null
    val copy = NovaForYouCopy.make(card) ?: return null
    return NovaMenuNextAction(copy.title, copy.symbol, NovaDestination.home, 0, 0, onSelect = { open(card) })
}

/**
 * Targets this session can open with every filter the card carries (iOS `forYouRoutes`). A card whose target is
 * missing here is never sent by the server.
 */
internal fun forYouRoutes(navigation: NovaNavigationState, workspaceExpert: Boolean): List<String> = listOf(
    "followup_record" to null, "followup" to NovaDestination.documentChecklist,
    "analysis" to NovaDestination.analyses, "photo_analysis" to NovaDestination.newAnalysis, "statistics" to NovaDestination.statistics,
    "risk_assessment" to NovaDestination.riskAssessments, "risk_wizard" to NovaDestination.riskAssessments,
    "emergency_wizard" to NovaDestination.emergencyPlans, "training_create" to NovaDestination.newTraining,
    "nonconformity_create" to NovaDestination.newFinding, "equipment" to NovaDestination.periodicChecks,
    "personnel" to NovaDestination.companies, "work_permit_forms" to NovaDestination.workPermits,
    "ppe_form" to NovaDestination.ppeHandovers, "company_create" to NovaDestination.newCompany,
    "nonconformity" to NovaDestination.findings, "checklist_run" to NovaDestination.checklists,
    "nonconformities" to NovaDestination.findings, "analyses" to NovaDestination.analyses,
    "trainings" to NovaDestination.training, "checklists" to NovaDestination.checklists,
).mapNotNull { (route, destination) ->
    // An organization's check list holds every member's runs and has no "mine" filter, so it cannot show what the card counted.
    route.takeIf { !((route == "company_create" || route == "checklists") && workspaceExpert) &&
        (destination == null || navigation.canOpen(destination)) }
}

private fun dashboardData(state: NovaPilotUiState, equipment: NovaEquipmentBoard?): NovaDashboardData {
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
        NovaMetricItem("equipment", equipment?.needsAttention?.toString() ?: "—", "Kontrol", "ilgi bekleyen",
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
    private val documents: NovaDocumentTrackingService,
    private val moduleEditor: NovaModuleEditorService,
    private val checklists: NovaChecklistService,
    private val checklistQueue: NovaChecklistOfflineQueue,
    private val training: NovaTrainingService,
    private val statistics: NovaStatisticsService,
    private val activity: NovaActivityService,
    val presence: NovaUsagePresence,
    val notebook: com.riskdetectedan.core.data.notebook.NotebookRollout,
    private val personnel: com.riskdetectedan.core.data.company.PersonnelRepository,
    private val overview: NovaOverviewService,
    private val companyRecords: com.riskdetectedan.core.data.company.CompanyRepository,
    private val companyCreate: NovaCompanyCreateService,
    private val learning: NovaEmployeeLearningService,
    private val analyses: NovaAnalysisService,
    val events: NovaRecordEvents,
    val forYou: NovaForYouService,
) : androidx.lifecycle.ViewModel() {
    private fun companies(identity: IsgWorkspaceIdentity): suspend () -> List<NovaCompanyOption> =
        { runCatching { findings.companyOptions(identity) }.getOrDefault(emptyList()) }
    fun fileClient(identity: IsgWorkspaceIdentity) = NovaFileClient(files, identity)

    /** A personal account's company logos for the list rows (iOS `CompanyService.logoImage`); one company read per list. */
    fun ownedCompanyLogos(): NovaCompanyLogoLoader {
        var paths: Map<String, String?>? = null
        val lock = kotlinx.coroutines.sync.Mutex()
        return { id, _ ->
            val known = lock.withLock {
                paths ?: (companyRecords.listCompanies(includeArchived = true) as? com.riskdetectedan.core.common.RdResult.Success)
                    ?.value?.associate { it.id.lowercase() to it.logoPath }?.also { paths = it }
            }
            known?.get(id.lowercase())?.let { path ->
                (companyRecords.downloadLogo(path) as? com.riskdetectedan.core.common.RdResult.Success)?.value?.let { decodeLogo(it) }
            }
        }
    }
    fun documentClient(identity: IsgWorkspaceIdentity) =
        NovaDocumentTrackingClient(portfolio = { documents.portfolio(identity, it) }, companies = companies(identity),
            detail = { company, id -> documents.detail(identity, company, id) })
    val analysis: NovaAnalysisService get() = analyses

    /** The analysis list over the account's (or organization's) analyses, read under [method]. */
    fun analysisListClient(identity: IsgWorkspaceIdentity, context: IsgWorkspaceContext?, method: suspend () -> NovaRiskMethod) = NovaAnalysisListClient(
        load = { offset -> analyses.summaries(identity, method(), offset = offset) },
        stats = { analyses.stats(identity, method()) },
        thumbnail = { id -> analyses.thumbnail(id, context) })

    fun analysisDetailClient(identity: IsgWorkspaceIdentity, context: IsgWorkspaceContext?, analysisId: String, method: suspend () -> NovaRiskMethod,
                             onAssigned: () -> Unit = {}) = NovaAnalysisDetailClient(
        load = { analyses.detail(analysisId, identity, method()) },
        photos = {
            analyses.photos(analysisId, context).mapNotNull { bytes ->
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }
            }
        },
        companies = { analyses.companyOptions(identity) },
        assign = { company -> analyses.assign(analysisId, company, identity); onAssigned() },
        workplaces = { company -> analyses.filingWorkplaces(identity, company) },
        file = { request -> analyses.file(request, analysisId, identity, null).also { if (it == NovaFindingOutcome.Opened) events.recordsChanged(identity.userId) } },
        edit = { change -> analyses.edit(change, identity) },
        remove = { item -> analyses.remove(analysisId, item.id, identity) },
        react = { item, section, reaction -> analyses.react(analysisId, item, section, reaction, identity) },
        report = { request -> analyses.report(request, identity, context) })
    /** Active personnel of one company, every page, capped like iOS at a thousand names. */
    private fun people(identity: IsgWorkspaceIdentity): suspend (String) -> List<NovaPersonOption> = { company ->
        val rows = mutableListOf<NovaPersonOption>()
        var cursor: String? = null
        do {
            val page = personnel.read(identity.userId, identity.sessionId, company, "employees", cursor = cursor)
            page["rows"]?.jsonArray?.forEach { row ->
                val entry = row.jsonObject
                fun text(key: String) = (entry[key] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() }
                rows += NovaPersonOption(entry.getValue("id").jsonPrimitive.content, entry.getValue("name").jsonPrimitive.content,
                    text("department_name"), text("job_title"))
            }
            cursor = page["next"]?.jsonPrimitive?.contentOrNull
        } while (cursor != null && rows.size < 1_000)
        rows
    }
    fun emergencyClient(identity: IsgWorkspaceIdentity) =
        NovaServiceEmergencyClient(emergency, identity, companies(identity), fileClient(identity), people(identity), moduleManage(identity))
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
    fun employeeCertificatesClient(identity: IsgWorkspaceIdentity, userName: String) = NovaEmployeeCertificatesClient(
        sessions = { company, after -> training.list(identity, company, after) }, training = trainingClient(identity, userName))
    fun trainingClient(identity: IsgWorkspaceIdentity, userName: String) =
        NovaServiceTrainingClient(training, identity, companies(identity), userName, people(identity))
    fun checklistClient(identity: IsgWorkspaceIdentity) = NovaServiceChecklistClient(checklists, checklistQueue, files, identity, companies(identity))
    fun companyOptions(identity: IsgWorkspaceIdentity) = companies(identity)
    suspend fun followup(identity: IsgWorkspaceIdentity, company: String?, status: String?, query: String, offset: Int, kind: String? = null) =
        followups.load(identity, company, status, kind, query, offset)
    suspend fun fileSources(identity: IsgWorkspaceIdentity, entry: NovaFileEntry) = followups.fileSources(identity, entry)
    /** This account's record changes, as the iOS `isgada.records.changed` notification. */
    fun changes(identity: IsgWorkspaceIdentity) = events.changed.filter { it.userId == identity.userId }.map { }
    fun processClient(identity: IsgWorkspaceIdentity) = NovaServiceProcessClient(process, identity, companies(identity), fileClient(identity))
    fun katipClient(identity: IsgWorkspaceIdentity) = NovaServiceKatipClient(katip, files, identity, companies(identity))
    fun ppeClient(identity: IsgWorkspaceIdentity) = NovaServicePPEClient(ppe, identity, companies(identity))
    fun appointmentClient(identity: IsgWorkspaceIdentity) =
        NovaServiceAppointmentClient(appointments, identity, companies(identity), fileClient(identity), moduleManage(identity))
    fun drillClient(identity: IsgWorkspaceIdentity) = NovaServiceDrillClient(drills, identity, companies(identity), moduleManage(identity))
    private fun moduleManage(identity: IsgWorkspaceIdentity) = NovaModuleManage(moduleEditor, identity, fileClient(identity))
    suspend fun equipmentSummary(identity: IsgWorkspaceIdentity) = equipment.board(identity, NovaEquipmentQuery(limit = 1))
    fun equipmentClient(identity: IsgWorkspaceIdentity) = NovaServiceEquipmentClient(equipment, identity, companies(identity), fileClient(identity))
    fun riskClient(identity: IsgWorkspaceIdentity) = NovaServiceRiskClient(risk, identity, companies(identity), fileClient(identity))

    fun noticeClient(identity: IsgWorkspaceIdentity) = NovaNoticeClient(
        feed = { scope -> notices.feed(identity, scope = scope) },
        read = { notices.read(identity, it) }, readAll = { notices.readAll(identity) },
        dismiss = { notices.dismiss(identity, it) }, dismissAll = { notices.dismissAll(identity) },
        restore = { notices.restore(identity, it) })
}
