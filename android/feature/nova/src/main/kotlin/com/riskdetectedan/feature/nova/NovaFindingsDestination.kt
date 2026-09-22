package com.riskdetectedan.feature.nova

import androidx.compose.runtime.*
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.NovaCompanyOption
import com.riskdetectedan.core.data.nova.NovaCompanyScope
import com.riskdetectedan.core.data.nova.NovaNonconformityEntry
import com.riskdetectedan.core.designsystem.isg.*

enum class NovaFindingsSurface { board, addFinding }

/**
 * The nonconformity surfaces (iOS `NovaPilotFindingsGate` board/addFinding):
 * each menu entry lands on exactly one page, a record opens in a popup.
 */
@Composable
fun NovaFindingsDestination(identity: IsgWorkspaceIdentity, surface: NovaFindingsSurface, canWrite: Boolean,
                            onNavigate: (NovaDestination) -> Unit, viewModel: NovaFindingsViewModel = hiltViewModel()) {
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var manual by remember { mutableStateOf(false) }
    var record by remember { mutableStateOf<NovaNonconformityEntry?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    val celebrate = rememberNovaCelebrate()
    LaunchedEffect(identity) { companies = viewModel.companies(identity) }
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
            onOpen = { record = it }, onCreate = { onNavigate(NovaDestination.newFinding) }, onBack = { onNavigate(NovaDestination.home) })
    }
    val entry = record
    NovaPopup(entry != null, { record = null; revision++ }, identifier = "nova.record") {
        if (entry != null) NovaNonconformityRecordSheet(entry, viewModel.recordClient(identity, entry), canWrite)
    }
}
