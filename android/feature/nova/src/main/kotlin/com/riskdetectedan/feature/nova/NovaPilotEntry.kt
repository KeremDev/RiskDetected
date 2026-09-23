package com.riskdetectedan.feature.nova

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.riskdetectedan.core.data.company.PersonnelRepository
import com.riskdetectedan.core.data.isg.IsgWorkspaceContext
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.designsystem.isg.*
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

/** Auth-owned identity only; the server decides every workspace and company. */
@HiltViewModel
class NovaSessionViewModel @Inject constructor(personnel: PersonnelRepository) : ViewModel() {
    val identity = personnel.workspaceIdentity.map { it?.let { value ->
        IsgWorkspaceIdentity(value.ownerID.toString(), value.sessionID.toString()) } }
    val initial: IsgWorkspaceIdentity? = personnel.workspaceIdentityNow()?.let {
        IsgWorkspaceIdentity(it.ownerID.toString(), it.sessionID.toString()) }
}

/** What the app shell lends the NOVA root: the regular profile page and anything that needs app routes. */
class NovaPilotSlots(
    val profile: @Composable (onBack: () -> Unit) -> Unit,
    /** The photo-analysis report list the archive's "Analiz raporları" tab shows (iOS `ReportView`). */
    val analysisReports: @Composable () -> Unit,
)

/**
 * The pilot entry (iOS `NovaIntegratedWorkspaceGate`). A personal account, or one
 * whose OSGB RPCs are unavailable, keeps the personal expert root; an OSGB
 * expert gets the same root over the organization; an OSGB manager gets the
 * management root.
 */
@Composable
fun NovaPilotEntry(slots: NovaPilotSlots, session: NovaSessionViewModel = hiltViewModel(),
                   store: NovaWorkspaceStore = hiltViewModel()) {
    val identity by session.identity.collectAsState(session.initial)
    val state by store.state.collectAsState()
    var choosing by remember { mutableStateOf(false) }
    LaunchedEffect(identity) { store.adopt(identity) }
    NovaTheme(dark = false) {
        NovaSuccessPresentation(identity?.userId) {
            when {
                identity == null || (state.selection == null && state.phase in setOf(NovaWorkspacePhase.signedOut, NovaWorkspacePhase.loading)) ->
                    NovaPageSurface { NovaLoadingView("Çalışma alanı yükleniyor…") }
                choosing || (state.contexts.isNotEmpty() && (state.phase == NovaWorkspacePhase.choosing ||
                    (state.phase == NovaWorkspacePhase.failed && state.selection == null))) ->
                    // A personal account (no OSGB yet) can always return to its own root.
                    NovaWorkspaceChooser(state, store, canCancel = state.selection != null || state.contexts.isEmpty(),
                        onSelect = { store.select(it); choosing = false }) { choosing = false }
                state.selection?.kind == "osgb" && state.isExpert ->
                    key("expert:${state.selection?.workspaceId}:${state.selection?.membership?.permissionRevision}") {
                        NovaPilotRoot(identity!!, state, slots, onWorkspaceSwitch = { choosing = true })
                    }
                state.selection?.kind == "osgb" ->
                    key("manager:${state.selection?.workspaceId}:${state.selection?.membership?.permissionRevision}") {
                        NovaOsgbManagerRoot(identity!!, state, store, slots)
                    }
                // The chooser is where an OSGB is created or joined, so it stays reachable whenever
                // the workspace RPCs answered (iOS lists the personal context for the same reason).
                else -> key("personal:${identity?.userId}") {
                    NovaPilotRoot(identity!!, null, slots, onWorkspaceSwitch = if (state.contexts.isNotEmpty() ||
                        state.phase == NovaWorkspacePhase.choosing) ({ choosing = true }) else null)
                }
            }
        }
    }
}

@Composable
private fun NovaWorkspaceChooser(state: NovaWorkspaceUiState, store: NovaWorkspaceStore, canCancel: Boolean,
                                 onSelect: (IsgWorkspaceContext) -> Unit, onClose: () -> Unit) {
    var access by remember { mutableStateOf<NovaWorkspaceAccess?>(null) }
    NovaPageSurface {
        Column(Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                if (canCancel) NovaBackButton(onClick = onClose)
                NovaText("Çalışma Alanı", Modifier.weight(1f), NovaTypeToken.screenTitle)
                Box(Modifier.size(48.dp).novaRowPress(onClick = store::refresh)
                    .semantics { contentDescription = "Çalışma alanlarını yenile" }, contentAlignment = Alignment.Center) {
                    NovaIcon("arrow.clockwise", 20.dp)
                }
            }
            NovaHelpHint("Yetkili olduğunuz çalışma alanını seçin.")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaCompactActionButton("OSGB oluştur", "building.2.crop.circle", Modifier.weight(1f), prominent = true,
                    identifier = "nova.workspace.create") { access = NovaWorkspaceAccess(create = true) }
                NovaCompactActionButton("Davete katıl", "envelope.open", Modifier.weight(1f),
                    identifier = "nova.workspace.accept") { access = NovaWorkspaceAccess(create = false) }
            }
            if (state.phase == NovaWorkspacePhase.failed) NovaEmptyState("Çalışma alanları yüklenemedi",
                "Bağlantınızı kontrol edip yeniden deneyin.")
            state.contexts.filter { it.kind == "osgb" }.forEach { context ->
                NovaCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress { onSelect(context) }
                    .testTag("nova.workspace.${context.workspaceId}"), padding = 14) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(44.dp).background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(13.dp)),
                            contentAlignment = Alignment.Center) { NovaIcon("building.2", 22.dp) }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            NovaText(context.name, style = NovaTypeToken.cardTitle)
                            NovaText(chooserRoleTitle(context.membership.role), style = NovaTypeToken.metaQuiet)
                        }
                        NovaIcon("chevron.right", 15.dp)
                    }
                }
            }
        }
    }
    val route = access
    NovaPopup(route != null, onDismissRequest = { access = null }, identifier = "nova.workspace.access") {
        if (route != null) NovaWorkspaceAccessEditor(route, store) { access = null; onClose() }
    }
}

/** One create/join attempt; its mutation id survives retries so a repeated tap cannot create twice. */
private class NovaWorkspaceAccess(val create: Boolean, val mutationId: String = UUID.randomUUID().toString())

/** OSGB name or invitation code, then the store opens the joined workspace (iOS `IsgWorkspaceAccessEditor`). */
@Composable
private fun NovaWorkspaceAccessEditor(route: NovaWorkspaceAccess, store: NovaWorkspaceStore, onDone: () -> Unit) {
    val celebrate = rememberNovaCelebrate()
    val coroutines = rememberCoroutineScope()
    var value by remember { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val clean = value.trim()
    val valid = if (route.create) clean.isNotEmpty() else clean.length == 64
    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaText(if (route.create) "OSGB çalışma alanı oluştur" else "OSGB davetini kabul et", style = NovaTypeToken.sectionTitle)
        NovaHelpHint(if (route.create) "Firmalarınızı ve uzman ekibinizi kişisel kayıtlardan ayrı yönetin."
            else "Size iletilen 64 karakterli davet kodunu girin.")
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            NovaTextField(if (route.create) "OSGB adı" else "Davet kodu", value, { value = it },
                identifier = if (route.create) "nova.workspace.name" else "nova.workspace.token", multiline = !route.create,
                keyboardType = if (route.create) KeyboardType.Text else KeyboardType.Ascii)
        }
        error?.let { NovaHelpHint(it) }
        NovaButton(if (saving) "Kaydediliyor…" else "Kaydet", {
            saving = true; error = null
            coroutines.launch {
                try {
                    if (route.create) store.createWorkspace(route.mutationId, clean) else store.acceptInvitation(route.mutationId, clean)
                    celebrate(if (route.create) "OSGB çalışma alanı oluşturuldu." else "OSGB daveti kabul edildi.")
                    onDone()
                } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                    error = "İşlem tamamlanamadı. Bilgileri kontrol edip yeniden deneyin."
                    saving = false
                }
            }
        }, enabled = valid && !saving, symbol = if (saving) "hourglass" else "checkmark")
    }
}

/** How the chooser names a membership (iOS `IsgWorkspaceChooser.role`). */
private fun chooserRoleTitle(role: String) = when (role) {
    "owner" -> "OSGB sahibi"
    "admin" -> "OSGB yöneticisi"
    else -> "İSG uzmanı"
}

/** Re-reads on every return to the foreground, like the iOS scene revalidation. */
@Composable
internal fun OnForeground(action: () -> Unit) {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val latest by rememberUpdatedState(action)
    DisposableEffect(lifecycle) {
        var backgrounded = false
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) backgrounded = true
            if (event == Lifecycle.Event.ON_START && backgrounded) { backgrounded = false; latest() }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
}
