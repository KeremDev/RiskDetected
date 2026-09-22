package com.riskdetectedan.feature.nova

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.NovaNoticeEntry
import com.riskdetectedan.core.data.nova.NovaNoticeService
import com.riskdetectedan.core.data.nova.NovaNoticeWords
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
            NovaDestination.companies, NovaDestination.newCompany -> NovaCompaniesScreen(
                companies = companyItems(state, workspace),
                isLoading = state.overview == null && !state.overviewFailed && workspace == null,
                error = if (state.overviewFailed && workspace == null) "Firmalar yüklenemedi. Lütfen tekrar deneyin." else null,
                isOwnedList = workspace == null,
                onSelect = { viewModel.showUnavailable() },
                onBack = { navigate(NovaDestination.home) }, onRetry = viewModel::reload)
            else -> NovaModulePending(destination, state, onWorkspaceSwitch) { navigate(NovaDestination.home) }
        }
    }
    state.message?.let { message ->
        AlertDialog(onDismissRequest = viewModel::dismissMessage, confirmButton = {
            TextButton(onClick = viewModel::dismissMessage) { NovaText("Tamam", style = NovaTypeToken.button) }
        }, title = { NovaText("İSGADA pilot", style = NovaTypeToken.sheetTitle) }, text = { NovaText(message) })
    }
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
class NovaRootServices @javax.inject.Inject constructor(private val notices: NovaNoticeService) : androidx.lifecycle.ViewModel() {
    fun noticeClient(identity: IsgWorkspaceIdentity) = NovaNoticeClient(
        feed = { scope -> notices.feed(identity, scope = scope) },
        read = { notices.read(identity, it) }, readAll = { notices.readAll(identity) },
        dismiss = { notices.dismiss(identity, it) }, dismissAll = { notices.dismissAll(identity) },
        restore = { notices.restore(identity, it) })
}
