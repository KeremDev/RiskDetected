package com.riskdetectedan.feature.nova

import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.NovaExpertTicket
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import com.riskdetectedan.core.data.isg.NovaExpertWorkspace
import com.riskdetectedan.core.data.nova.NovaCompanySummary
import com.riskdetectedan.core.data.nova.NovaNoticeFeed
import com.riskdetectedan.core.data.nova.NovaNoticeService
import com.riskdetectedan.core.data.nova.NovaOverviewService
import com.riskdetectedan.core.data.profile.ProfileRepository
import com.riskdetectedan.core.designsystem.isg.*
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

data class NovaPilotUiState(
    val identity: IsgWorkspaceIdentity? = null,
    val workspace: NovaExpertWorkspace? = null,
    val workspaceLabel: String? = null,
    val navigation: NovaNavigationState = NovaNavigationState(UUID.randomUUID().toString(), NovaWorkspaceRole.personnel.destinations),
    val userName: String = "",
    val avatar: ImageBitmap? = null,
    val overview: List<NovaCompanySummary>? = null,
    val overviewFailed: Boolean = false,
    val notices: NovaNoticeFeed = NovaNoticeFeed.empty,
    val dashboard: NovaWorkspaceDashboard? = null,
    val message: String? = null,
) {
    val ready: Boolean get() = identity != null
    val isWorkspaceExpert: Boolean get() = workspace != null
    val writable: Boolean get() = ready && (workspace?.canOperate ?: true)
    val activeCompanies: List<NovaCompanySummary>? get() = if (ready) overview?.filter { !it.isArchived } else null
}

/**
 * The single expert root (iOS `NovaPilotRoot`). Personal experts and OSGB
 * experts see the same pages; only the transport ticket differs.
 */
@HiltViewModel
class NovaPilotViewModel @Inject constructor(
    private val transport: NovaExpertTransport,
    private val overviewService: NovaOverviewService,
    private val noticeService: NovaNoticeService,
    private val profiles: ProfileRepository,
    private val auth: AuthRepository,
) : ViewModel() {
    private val mutable = MutableStateFlow(NovaPilotUiState())
    val state = mutable.asStateFlow()
    private var ticket: NovaExpertTicket? = null
    private var loads: Job? = null
    private var profileJob: Job? = null

    /** Identity observation lives with the gate; this only adopts what it is given. */
    fun bind(identity: IsgWorkspaceIdentity?, workspace: NovaExpertWorkspace?, workspaceLabel: String?,
             dashboard: NovaWorkspaceDashboard?) {
        val current = state.value
        if (current.identity == identity && current.workspace == workspace) {
            if (current.dashboard != dashboard || current.workspaceLabel != workspaceLabel)
                mutable.value = current.copy(dashboard = dashboard, workspaceLabel = workspaceLabel)
            return
        }
        ticket?.let(transport::release)
        ticket = identity?.let { transport.bind(it, workspace) }
        val role = if (workspace != null) NovaWorkspaceRole.osgbExpert else NovaWorkspaceRole.personnel
        mutable.value = NovaPilotUiState(identity = identity, workspace = workspace, workspaceLabel = workspaceLabel,
            navigation = NovaNavigationState(UUID.randomUUID().toString(), role.destinations), dashboard = dashboard,
            userName = if (current.identity == identity) current.userName else "",
            avatar = if (current.identity == identity) current.avatar else null)
        if (identity != null) { reload(); loadProfile(identity) }
    }

    fun apply(event: NovaNavigationEvent, epoch: String) {
        val current = state.value
        mutable.value = current.copy(navigation = current.navigation.apply(event, epoch))
    }

    fun navigate(destination: NovaDestination) {
        val current = state.value
        if (!current.navigation.canOpen(destination)) {
            mutable.value = current.copy(message = "Bu modül hazırlanıyor. Bu build’de henüz canlı işlem yapmıyor.")
            return
        }
        apply(NovaNavigationEvent.Navigate(destination), current.navigation.epoch)
    }

    fun showUnavailable() {
        mutable.value = state.value.copy(message = "Bu modül hazırlanıyor. Bu build’de henüz canlı işlem yapmıyor.")
    }

    fun showMessage(text: String) { mutable.value = state.value.copy(message = text) }
    fun dismissMessage() { mutable.value = state.value.copy(message = null) }

    /** Overview and bell reload together after a scene return, a save or a mark. */
    fun reload() {
        val identity = state.value.identity ?: return
        val expected = ticket
        loads?.cancel()
        loads = viewModelScope.launch {
            launch {
                try {
                    val overview = overviewService.overview(identity)
                    if (ticket === expected) mutable.value = state.value.copy(overview = overview, overviewFailed = false)
                } catch (cancelled: CancellationException) { throw cancelled
                } catch (_: Exception) {
                    if (ticket === expected) mutable.value = state.value.copy(overviewFailed = true)
                }
            }
            launch {
                val feed = runCatching { noticeService.feed(identity) }.getOrNull()
                if (feed != null && ticket === expected) mutable.value = state.value.copy(notices = feed)
            }
        }
    }

    /** A mark is never applied locally; the server states the counts and the bell asks again. */
    fun markNotice(action: String, key: String? = null) {
        val identity = state.value.identity ?: return
        viewModelScope.launch {
            runCatching {
                when (action) {
                    "read" -> noticeService.read(identity, key!!)
                    "read_all" -> noticeService.readAll(identity)
                    "dismiss" -> noticeService.dismiss(identity, key!!)
                    "dismiss_all" -> noticeService.dismissAll(identity)
                    "restore" -> noticeService.restore(identity, key!!)
                }
            }
            val feed = runCatching { noticeService.feed(identity) }.getOrNull()
            if (feed != null && state.value.identity == identity) mutable.value = state.value.copy(notices = feed)
        }
    }

    fun signOut() { viewModelScope.launch { auth.signOut() } }

    private fun loadProfile(identity: IsgWorkspaceIdentity) {
        profileJob?.cancel()
        profileJob = viewModelScope.launch {
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

    override fun onCleared() {
        ticket?.let(transport::release)
        super.onCleared()
    }

}
