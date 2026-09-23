package com.riskdetectedan.feature.nova

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.data.isg.IsgWorkspaceContext
import com.riskdetectedan.core.data.isg.IsgWorkspaceGatewayFailure
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.IsgWorkspaceRepository
import com.riskdetectedan.core.data.isg.NovaExpertWorkspace
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import java.util.UUID
import javax.inject.Inject

/** One OSGB company as the workspace lists it. */
data class NovaWorkspaceCompany(val id: String, val name: String, val hazardClass: String, val sector: String?,
                                val version: Long, val email: String? = null, val declaredEmployeeCount: Int? = null,
                                val address: String? = null, val responsibleName: String? = null, val responsiblePhone: String? = null,
                                val responsibleEmail: String? = null, val profileVersion: Long? = null) {
    /** Filled profile fields out of eight, as the company list's progress shows them. */
    val profileCompletionCount: Int get() = listOf(sector, email, address, responsibleName, responsiblePhone, responsibleEmail, hazardClass)
        .count { !it.isNullOrBlank() } + if (declaredEmployeeCount == null) 0 else 1
}

/** Aggregate counters for the selected workspace (iOS `IsgWorkspaceDashboard`). */
data class NovaWorkspaceDashboard(
    val companyId: String?, val companies: Long, val experts: Long?,
    val openNonconformities: Long, val overdueNonconformities: Long,
    val visitsTotal: Long, val visitsLast30: Long, val trainingPlanned: Long, val trainingCompleted: Long,
    val equipmentDueSoon: Long, val riskDueSoon: Long,
) {
    companion object {
        fun parse(value: JsonObject): NovaWorkspaceDashboard {
            fun n(group: String, key: String) = value[group]?.jsonObject?.get(key)?.jsonPrimitive?.longOrNull ?: 0L
            return NovaWorkspaceDashboard(value["company_id"]?.jsonPrimitive?.contentOrNull, n("companies", "total"),
                value["experts"]?.jsonObject?.get("total")?.jsonPrimitive?.longOrNull,
                n("nonconformities", "open"), n("nonconformities", "overdue"), n("visits", "total"),
                n("visits", "last_30_days"), n("training", "planned"), n("training", "completed"),
                n("deadlines", "equipment_due_soon"), n("deadlines", "risk_due_soon"))
        }
    }
}

enum class NovaWorkspacePhase { signedOut, loading, choosing, ready, failed }

data class NovaWorkspaceUiState(
    val phase: NovaWorkspacePhase = NovaWorkspacePhase.signedOut,
    val contexts: List<IsgWorkspaceContext> = emptyList(),
    val selection: IsgWorkspaceContext? = null,
    val selectedCompanyId: String? = null,
    val dashboard: NovaWorkspaceDashboard? = null,
    val companies: List<NovaWorkspaceCompany> = emptyList(),
) {
    val expertWorkspace: NovaExpertWorkspace? get() = selection?.let(NovaExpertWorkspace::of)
    val isExpert: Boolean get() = selection?.membership?.role == "expert"
}

/**
 * Session-owned OSGB workspace state (iOS `IsgWorkspaceStore`). A personal
 * account with no organization simply ends in [NovaWorkspacePhase.choosing]
 * with no contexts, and the personal expert root is shown.
 */
@HiltViewModel
class NovaWorkspaceStore @Inject constructor(private val repository: IsgWorkspaceRepository) : ViewModel() {
    private val mutable = MutableStateFlow(NovaWorkspaceUiState())
    val state = mutable.asStateFlow()
    private var identity: IsgWorkspaceIdentity? = null
    private var generation = UUID.randomUUID().toString()
    private var request: Job? = null

    fun adopt(next: IsgWorkspaceIdentity?) {
        if (identity == next) return
        identity = next
        invalidate(keepContexts = false)
        if (next == null) { mutable.value = NovaWorkspaceUiState(); return }
        mutable.value = NovaWorkspaceUiState(phase = NovaWorkspacePhase.loading)
        load(next, preferred = null)
    }

    fun refresh() {
        val current = identity ?: return
        val preferred = state.value.selection?.workspaceId
        // Revalidation is not a workspace switch; keep the routing identity while content reloads.
        invalidate(keepContexts = true)
        mutable.value = state.value.copy(phase = NovaWorkspacePhase.loading, companies = emptyList(), dashboard = null,
            selectedCompanyId = null)
        load(current, preferred)
    }

    fun select(context: IsgWorkspaceContext) {
        val current = identity ?: return
        if (context.membership.userId != current.userId || !context.canRead || context !in state.value.contexts) return
        invalidate(keepContexts = true)
        mutable.value = state.value.copy(selection = context, phase = NovaWorkspacePhase.loading,
            companies = emptyList(), dashboard = null, selectedCompanyId = null)
        val token = generation
        request = viewModelScope.launch { resolve(context, current, token) }
    }

    private val logoLock = kotlinx.coroutines.sync.Mutex()

    /**
     * A company's logo from its file archive, for the list row (iOS `loadNovaWorkspaceCompanyLogo`). Reads run one at
     * a time because each one scopes the repository to its company.
     */
    suspend fun companyLogo(companyId: String): ByteArray? = logoLock.withLock {
        val context = state.value.selection ?: return@withLock null
        val page = repository.domain(context, companyId, com.riskdetectedan.core.data.isg.IsgWorkspaceDomain.FILES)
        val row = com.riskdetectedan.core.data.isg.IsgWorkspaceRecords.snapshot(com.riskdetectedan.core.data.isg.IsgWorkspaceDomain.FILES, page, null)
            .rows.firstOrNull { it.fact("category") == "company_logo" } ?: return@withLock null
        repository.downloadAsset(context, row.assetId ?: return@withLock null)
    }

    /** Creates an OSGB and opens it (iOS `IsgWorkspaceStore.createWorkspace`). */
    suspend fun createWorkspace(mutationId: String, name: String): IsgWorkspaceContext =
        join { repository.createOsgbWorkspace(mutationId, name) }

    /** Joins an OSGB by invitation code and opens it (iOS `IsgWorkspaceStore.acceptInvitation`). */
    suspend fun acceptInvitation(mutationId: String, token: String): IsgWorkspaceContext =
        join { repository.acceptOsgbInvitation(mutationId, token) }

    private suspend fun join(action: suspend () -> IsgWorkspaceContext): IsgWorkspaceContext {
        val current = identity ?: throw IsgWorkspaceGatewayFailure("AUTH_REQUIRED")
        val context = action()
        if (identity != current) throw IsgWorkspaceGatewayFailure("STALE_SESSION")
        mutable.value = state.value.copy(contexts = (state.value.contexts.filter { it.workspaceId != context.workspaceId } + context)
            .sortedBy { it.workspaceId.lowercase() })
        select(context)
        return context
    }

    fun selectCompany(companyId: String?) {
        val current = identity ?: return
        val value = state.value
        val selection = value.selection ?: return
        if (value.phase != NovaWorkspacePhase.ready) return
        if (companyId != null && value.companies.none { it.id == companyId }) return
        if (selection.kind == "osgb" && value.isExpert && companyId == null) return
        invalidate(keepContexts = true)
        mutable.value = value.copy(selectedCompanyId = companyId, dashboard = null, phase = NovaWorkspacePhase.loading)
        val token = generation
        request = viewModelScope.launch {
            try {
                val dashboard = NovaWorkspaceDashboard.parse(repository.dashboard(selection, companyId))
                if (!isCurrent(token, current) || state.value.selectedCompanyId != companyId) return@launch
                mutable.value = state.value.copy(dashboard = dashboard, phase = NovaWorkspacePhase.ready)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                if (token == generation) mutable.value = state.value.copy(dashboard = null, phase = NovaWorkspacePhase.failed)
            }
        }
    }

    private fun load(expected: IsgWorkspaceIdentity, preferred: String?) {
        val token = generation
        request = viewModelScope.launch {
            try {
                val values = repository.listOsgbWorkspaces()
                if (!isCurrent(token, expected)) return@launch
                mutable.value = state.value.copy(contexts = values)
                val previous = preferred?.let { id -> values.firstOrNull { it.workspaceId == id } }
                when {
                    previous != null -> select(previous)
                    values.size == 1 -> select(values.single())
                    else -> mutable.value = state.value.copy(selection = null, phase = NovaWorkspacePhase.choosing)
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                if (isCurrent(token, expected)) mutable.value = state.value.copy(phase = NovaWorkspacePhase.failed)
            }
        }
    }

    private suspend fun resolve(context: IsgWorkspaceContext, expected: IsgWorkspaceIdentity, token: String) {
        try {
            val loaded = mutableListOf<NovaWorkspaceCompany>()
            var cursor: String? = null
            var pages = 0
            while (pages++ < 100) {
                val rows = parseCompanies(repository.companies(context, cursor))
                if (!isCurrent(token, expected)) return
                loaded += rows
                if (rows.size < 100) break
                cursor = rows.last().id
            }
            // A single-company workspace opens ready for work for every role; an expert
            // always lands on a company because every module needs one.
            val company = if (context.membership.role == "expert") loaded.firstOrNull()?.id
                else loaded.singleOrNull()?.id
            val dashboard = if (company == null && context.membership.role == "expert") null
                else NovaWorkspaceDashboard.parse(repository.dashboard(context, company))
            if (!isCurrent(token, expected) || state.value.selection?.workspaceId != context.workspaceId) return
            mutable.value = state.value.copy(companies = loaded, selectedCompanyId = company, dashboard = dashboard,
                phase = NovaWorkspacePhase.ready)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            if (token != generation) return
            mutable.value = state.value.copy(selection = null, companies = emptyList(), dashboard = null,
                selectedCompanyId = null, phase = NovaWorkspacePhase.failed)
        }
    }

    private fun parseCompanies(response: JsonObject): List<NovaWorkspaceCompany> =
        (response["rows"] as? JsonArray).orEmpty().mapNotNull { item ->
            val row = item as? JsonObject ?: return@mapNotNull null
            fun text(key: String) = (row[key] as? JsonPrimitive)?.contentOrNull?.takeIf { (row[key] as JsonPrimitive).isString }
            NovaWorkspaceCompany(text("company_id") ?: return@mapNotNull null, text("name") ?: "Firma", text("hazard_class") ?: "",
                text("sector"), row["version"]?.jsonPrimitive?.longOrNull ?: 0, text("email"),
                (row["declared_employee_count"] as? JsonPrimitive)?.intOrNull, text("address"), text("responsible_name"),
                text("responsible_phone"), text("responsible_email"), (row["profile_version"] as? JsonPrimitive)?.longOrNull)
        }

    private fun isCurrent(token: String, expected: IsgWorkspaceIdentity) = token == generation && identity == expected

    private fun invalidate(keepContexts: Boolean) {
        generation = UUID.randomUUID().toString()
        request?.cancel(); request = null
        if (!keepContexts) repository.clearSelection()
    }
}
