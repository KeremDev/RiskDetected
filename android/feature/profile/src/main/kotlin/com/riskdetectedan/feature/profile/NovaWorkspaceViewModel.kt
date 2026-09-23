package com.riskdetectedan.feature.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.data.company.*
import com.riskdetectedan.core.designsystem.isg.*
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import java.util.UUID
import javax.inject.Inject

internal data class NovaWorkspaceState(
    val host: NovaSessionHost = NovaSessionHost(setOf(NovaDestination.companies)),
    val company: UUID? = null,
    val capability: PersonnelWorkspaceCapability? = null,
    val resolving: Boolean = true,
) {
    val available: Boolean get() = host.phase == NovaHostPhase.ready && capability?.canRead == true
    val scope: NovaPersonnelScope? get() {
        val actor = host.identity ?: return null
        val selected = company ?: return null
        if (!available || capability?.companyID != selected) return null
        return NovaPersonnelScope(actor.userID, actor.sessionID, selected, host.navigation.epoch)
    }
    val canWrite: Boolean get() = scope != null && capability?.canWrite == true
    /** Personnel has its own pilot grant; the general capability still reflects paid access for the other modules (iOS). */
    val canWritePersonnel: Boolean get() = scope != null && capability?.canRead == true && capability.archived != true
}

@HiltViewModel
internal class NovaWorkspaceViewModel @Inject constructor(private val repository: PersonnelRepository, private val companies: CompanyRepository): ViewModel() {
    private val mutableState = MutableStateFlow(NovaWorkspaceState())
    val state = mutableState.asStateFlow()
    private var observer: Job? = null
    private var request: Job? = null
    private val rawPersonnel = repository.novaClient { state.value.scope }
    private val rawDirectory = repository.novaDirectoryClient { state.value.scope }
    val personnel = NovaPersonnelClient(rawPersonnel.employees, rawPersonnel.departments, rawPersonnel.detail, { intent ->
        if (state.value.scope != intent.scope || !state.value.canWritePersonnel) throw NovaPersonnelFailure(NovaPersonnelFailure.Kind.denied)
        rawPersonnel.save(intent)
    }, rawPersonnel.pending)
    val directory = rawDirectory.copy(save = { intent -> requireWritable(intent.scope); rawDirectory.save(intent) })
    private fun requireWritable(scope: NovaPersonnelScope) {
        if (state.value.scope != scope || !state.value.canWrite) throw NovaPersonnelFailure(NovaPersonnelFailure.Kind.denied)
    }
    suspend fun loadCompanies(archived: Boolean) = companies.loadNovaOwnedCompanies(archived)
    fun start() {
        if (observer != null) return
        adopt(repository.workspaceIdentityNow())
        observer = viewModelScope.launch { repository.workspaceIdentity.collect { adopt(it) } }
    }
    private fun adopt(identity: PersonnelWorkspaceIdentity?) {
        val next = identity?.let { NovaSessionIdentity(it.ownerID, it.sessionID) }
        val old = state.value
        if (old.host.identity == next && (old.capability != null || request != null)) return
        request?.cancel(); request = null
        mutableState.value = NovaWorkspaceState(host = old.host.adopt(next), resolving = next != null)
        if (next != null) refresh()
    }
    fun select(company: UUID?) { mutableState.value = state.value.copy(company = company); refresh() }
    fun refresh() {
        val identity = repository.workspaceIdentityNow()
        val hostIdentity = state.value.host.identity
        if (identity == null || hostIdentity != NovaSessionIdentity(identity.ownerID, identity.sessionID)) { adopt(identity); return }
        request?.cancel()
        val host = state.value.host.beginAvailabilityRefresh()
        val ticket = host.pending ?: return
        val company = state.value.company
        mutableState.value = state.value.copy(host = host, capability = null, resolving = true)
        request = viewModelScope.launch {
            try {
                val capability = repository.workspaceAvailability(identity, company)
                currentCoroutineContext().ensureActive()
                val current = state.value
                if (current.host.pending !== ticket || current.company != company || repository.workspaceIdentityNow() != identity) return@launch
                val ready = current.host.resolve(ticket, identity.ownerID, if (capability.canRead) setOf(NovaDestination.companies) else emptySet())
                mutableState.value = current.copy(host = ready, capability = capability, resolving = false)
                request = null
            } catch (_: Exception) {
                currentCoroutineContext().ensureActive()
                val current = state.value
                if (current.host.pending === ticket) { mutableState.value = current.copy(host = current.host.fail(ticket), capability = null, resolving = false); request = null }
            }
        }
    }
    fun stop() {
        observer?.cancel(); observer = null; request?.cancel(); request = null
        mutableState.value = NovaWorkspaceState(host = state.value.host.adopt(null), resolving = false)
    }
}
