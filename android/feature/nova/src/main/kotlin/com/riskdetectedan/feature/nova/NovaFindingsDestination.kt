package com.riskdetectedan.feature.nova

import androidx.compose.runtime.*
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.isg.IsgWorkspaceContext
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.NovaCompanyOption
import com.riskdetectedan.core.data.nova.NovaCompanyScope
import com.riskdetectedan.core.data.nova.NovaListPreset
import com.riskdetectedan.core.data.nova.NovaNonconformityEntry
import com.riskdetectedan.core.designsystem.isg.*

enum class NovaFindingsSurface { board, addFinding }

/**
 * The nonconformity surfaces (iOS `NovaPilotFindingsGate` board/addFinding):
 * each menu entry lands on exactly one page, a record opens in a popup.
 */
@Composable
fun NovaFindingsDestination(identity: IsgWorkspaceIdentity, surface: NovaFindingsSurface, canWrite: Boolean,
                            onNavigate: (NovaDestination) -> Unit, context: IsgWorkspaceContext? = null,
                            /** A record a home card asked for, opened over the board as soon as it is read. */
                            initialRecord: NovaRecordTarget? = null, onInitialRecordOpened: () -> Unit = {},
                            onRecordFailed: () -> Unit = {},
                            /** A home card's filter for the board. */
                            initialPreset: NovaListPreset? = null, onPresetCleared: () -> Unit = {},
                            viewModel: NovaFindingsViewModel = hiltViewModel()) {
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var manual by remember { mutableStateOf(false) }
    var record by remember { mutableStateOf<NovaNonconformityEntry?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    val celebrate = rememberNovaCelebrate()
    LaunchedEffect(identity) { companies = viewModel.companies(identity) }
    // The record is read the same way the board's rows are, with the company and workplace names the sheet shows.
    LaunchedEffect(initialRecord) {
        val target = initialRecord ?: return@LaunchedEffect
        if (surface != NovaFindingsSurface.board) return@LaunchedEffect
        onInitialRecordOpened()
        try {
            val scope = NovaCompanyScope(identity, target.companyId)
            val row = viewModel.service.detail(scope, target.id)
            val places = if (row.workplaceId == null) emptyList() else runCatching { viewModel.service.workplaces(scope) }.getOrDefault(emptyList())
            val names = companies.ifEmpty { viewModel.companies(identity) }
            record = NovaNonconformityEntry(row, target.companyId, names.firstOrNull { it.id.equals(target.companyId, true) }?.name.orEmpty(),
                places.firstOrNull { it.id == row.workplaceId }?.name)
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled } catch (_: Exception) { onRecordFailed() }
    }
    when {
        manual -> NovaManualNonconformityScreen(companies,
            workplaces = { company -> viewModel.service.workplaces(NovaCompanyScope(identity, company)) },
            save = { draft, photos ->
                val failure = viewModel.saveManual(identity, draft, photos)
                if (failure == null) { celebrate(NovaSuccessMessage.findingCreated); revision++; manual = false; onNavigate(NovaDestination.findings) }
                failure
            }, onBack = { manual = false })
        surface == NovaFindingsSurface.addFinding -> NovaAddFindingScreen(companies.isNotEmpty(),
            onAnalyses = { onNavigate(NovaDestination.analyses) }, onManual = { manual = true },
            onNewAnalysis = { onNavigate(NovaDestination.newAnalysis) }, onCompanies = { onNavigate(NovaDestination.companies) },
            onBack = { onNavigate(NovaDestination.findings) })
        else -> NovaNonconformityBoardScreen({ viewModel.board(identity) }, companies, novaTodayIso(), revision,
            onOpen = { record = it }, onCreate = { onNavigate(NovaDestination.newFinding) }, onBack = { onNavigate(NovaDestination.home) },
            initialPreset = initialPreset, onPresetCleared = onPresetCleared)
    }
    val entry = record
    NovaPopup(entry != null, { record = null; revision++ }, identifier = "nova.record") {
        if (entry != null) {
            // A record born from a photo finding reuses the finding page; the record sheet stands in when the source is gone.
            val record = @Composable { NovaNonconformityRecordSheet(entry, viewModel.recordClient(identity, entry), canWrite) }
            if (entry.row.cameFromFinding) key(entry.id) { NovaFiledFindingSheet(entry, identity, context, viewModel.analysis, canWrite, record) }
            else record()
        }
    }
}
