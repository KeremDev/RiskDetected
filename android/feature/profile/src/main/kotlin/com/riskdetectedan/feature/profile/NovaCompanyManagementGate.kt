package com.riskdetectedan.feature.profile

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.IconButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.riskdetectedan.core.designsystem.isg.*

/** Only the management entry uses this gate; analysis/report company pickers are unchanged. */
@Composable
fun CompanyListScreen(onBack: (() -> Unit)? = null, viewModel: CompanyViewModel = hiltViewModel()) {
    val workspace: NovaWorkspaceViewModel = hiltViewModel()
    val state by workspace.state.collectAsState()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var legacy by remember(state.host.identity) { mutableStateOf(false) }
    val close = onBack ?: {}
    DisposableEffect(workspace, lifecycle) {
        workspace.start()
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_RESUME) workspace.refresh() }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer); workspace.stop() }
    }
    when {
        state.resolving -> NovaPageSurface {
            Column(Modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                CircularProgressIndicator(); NovaText("Firma erişimi doğrulanıyor…")
                WorkspaceAction("Kapat", Icons.Outlined.Close, close)
            }
            BackHandler(onBack = close)
        }
        state.available && !legacy -> key(state.host.navigation.epoch) {
            state.scope?.let { scope ->
                NovaCompanyWorkspace(scope, state.capability?.companyName ?: "Firma", state.canWrite, state.canWritePersonnel, workspace.personnel,
                    workspace.directory) { workspace.select(null) }
            } ?: NovaPageSurface {
                Column {
                    Box(Modifier.weight(1f)) {
                        NovaCompanyDestination(state.host, workspace::loadCompanies, includeArchived = true, onSelect = workspace::select, onBack = close)
                    }
                    Box(Modifier.padding(18.dp)) { WorkspaceAction("Firma ekle / düzenle", Icons.Outlined.Business) { legacy = true } }
                }
                BackHandler(onBack = close)
            }
        }
        else -> Column {
            if (legacy && state.available) Box(Modifier.padding(12.dp)) {
                WorkspaceAction("Personel ve işyeri yönetimine dön", Icons.Outlined.ChevronLeft) { legacy = false; workspace.select(null) }
            }
            Box(Modifier.weight(1f)) { LegacyCompanyListScreen(onBack, viewModel) }
        }
    }
}

@Composable
internal fun NovaCompanyWorkspace(scope: NovaPersonnelScope, companyName: String, canWrite: Boolean, canWritePersonnel: Boolean,
                                  personnel: NovaPersonnelClient, directory: NovaDirectoryClient, onBack: () -> Unit) {
    var educationOpen by remember(scope) { mutableStateOf(false) }
    var personnelOpen by remember(scope) { mutableStateOf(false) }
    var catalog by remember(scope) { mutableStateOf<NovaDirectoryKind?>(null) }
    when {
        educationOpen -> EducationScreen(com.riskdetectedan.core.data.company.PersonnelWorkspaceIdentity(scope.ownerID,scope.sessionID),canWrite,{educationOpen=false})
        personnelOpen -> NovaPersonnelDestination(scope, companyName, personnel, { personnelOpen = false }, directory, canWritePersonnel)
        catalog != null -> NovaDirectoryDestination(scope, catalog!!, client = directory, canWrite = canWrite) { catalog = null }
        else -> NovaPageSurface {
            BackHandler(onBack = onBack)
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) { IconButton(onBack) { NovaGlyph(Icons.Outlined.ChevronLeft, "Geri") }; NovaText(companyName, style = NovaTypeToken.screenTitle) }
                if (!canWrite) NovaCard { Column {
                    Row { NovaGlyph(Icons.Outlined.Lock, null); NovaText("Salt okunur · kayıtlarınız korunuyor") }
                    NovaText("Yeni kayıt ve düzenleme şu anda kullanılamıyor.", style = NovaTypeToken.metaQuiet)
                } }
                WorkspaceAction("Eğitimler", Icons.Outlined.School) { educationOpen = true }
                WorkspaceAction("Personeller", Icons.Outlined.PeopleOutline) { personnelOpen = true }
                listOf(NovaDirectoryKind.workplaces to Icons.Outlined.Business, NovaDirectoryKind.departments to Icons.Outlined.AccountTree,
                    NovaDirectoryKind.jobs to Icons.Outlined.WorkOutline, NovaDirectoryKind.contractors to Icons.Outlined.Business).forEach { (kind, icon) ->
                    WorkspaceAction(kind.title, icon) { catalog = kind }
                }
            }
        }
    }
}

@Composable
private fun WorkspaceAction(title: String, icon: ImageVector, onClick: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        NovaGlyph(icon, null); NovaButton(title, onClick, variant = NovaButtonVariant.Surface)
    }
}
