package com.riskdetectedan.feature.nova

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
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
            NovaDestination.companies, NovaDestination.newCompany -> NovaCompaniesScreen(
                companies = companyItems(state, workspace),
                isLoading = state.overview == null && !state.overviewFailed && workspace == null,
                error = if (state.overviewFailed && workspace == null) "Firmalar yüklenemedi. Lütfen tekrar deneyin." else null,
                isOwnedList = workspace == null,
                onSelect = { viewModel.showUnavailable() },
                onBack = { navigate(NovaDestination.home) }, onRetry = viewModel::reload)
            NovaDestination.riskAssessments -> NovaRiskScreen(services.riskClient(identity), state.writable,
                onBack = { navigate(NovaDestination.home) })
            NovaDestination.periodicChecks -> NovaEquipmentScreen(services.equipmentClient(identity), state.writable,
                onBack = { navigate(NovaDestination.home) })
            NovaDestination.emergencyPlans -> NovaEmergencyScreen(services.emergencyClient(identity), state.writable,
                onBack = { navigate(NovaDestination.home) })
            NovaDestination.drills -> NovaDrillScreen(services.drillClient(identity), state.writable, onBack = { navigate(NovaDestination.home) })
            else -> NovaModulePending(destination, state, onWorkspaceSwitch) { navigate(NovaDestination.home) }
        }
    }
    NovaNoticeDialog(state.message, "İSGADA pilot", viewModel::dismissMessage)
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
    private val personnel: com.riskdetectedan.core.data.company.PersonnelRepository,
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
    fun drillClient(identity: IsgWorkspaceIdentity) = NovaServiceDrillClient(drills, identity, companies(identity))
    fun equipmentClient(identity: IsgWorkspaceIdentity) = NovaServiceEquipmentClient(equipment, identity, companies(identity), fileClient(identity))
    fun riskClient(identity: IsgWorkspaceIdentity) = NovaServiceRiskClient(risk, identity, companies(identity), fileClient(identity))

    fun noticeClient(identity: IsgWorkspaceIdentity) = NovaNoticeClient(
        feed = { scope -> notices.feed(identity, scope = scope) },
        read = { notices.read(identity, it) }, readAll = { notices.readAll(identity) },
        dismiss = { notices.dismiss(identity, it) }, dismissAll = { notices.dismissAll(identity) },
        restore = { notices.restore(identity, it) })
}
