package com.riskdetectedan.feature.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.data.isg.IsgWorkspaceContext
import com.riskdetectedan.core.data.isg.IsgWorkspaceDomain
import com.riskdetectedan.core.data.isg.IsgWorkspacePersonnelAdvancedKind
import com.riskdetectedan.core.data.isg.IsgWorkspaceRepository
import com.riskdetectedan.core.data.isg.IsgWorkspaceTrainingAdvancedKind
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import javax.inject.Inject

data class OsgbCompanyItem(
    val id: String,
    val name: String,
    val hazardClass: String,
    val version: Long,
)

internal fun parseOsgbCompanies(response: JsonObject): List<OsgbCompanyItem> =
    (response["rows"] as? JsonArray).orEmpty().mapNotNull { item ->
        val row = item as? JsonObject ?: return@mapNotNull null
        val id = row["company_id"]?.jsonPrimitive?.content ?: return@mapNotNull null
        OsgbCompanyItem(
            id = id,
            name = row["name"]?.jsonPrimitive?.content ?: "Firma",
            hazardClass = row["hazard_class"]?.jsonPrimitive?.content ?: "—",
            version = row["version"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
        )
    }

sealed interface OsgbWorkspacePage {
    data object Workspaces : OsgbWorkspacePage
    data object Companies : OsgbWorkspacePage
    data object Company : OsgbWorkspacePage
    data class Domain(val domain: IsgWorkspaceDomain) : OsgbWorkspacePage
    data class PersonnelAdvanced(val kind: IsgWorkspacePersonnelAdvancedKind) : OsgbWorkspacePage
    data class TrainingAdvanced(val kind: IsgWorkspaceTrainingAdvancedKind) : OsgbWorkspacePage
    data object Analyses : OsgbWorkspacePage
}

data class OsgbWorkspaceUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val workspaces: List<IsgWorkspaceContext> = emptyList(),
    val workspace: IsgWorkspaceContext? = null,
    val companies: List<OsgbCompanyItem> = emptyList(),
    val company: OsgbCompanyItem? = null,
    val dashboard: JsonObject? = null,
    val metrics: JsonObject? = null,
    val rows: List<JsonObject> = emptyList(),
    val selectedRow: JsonObject? = null,
    val notice: String? = null,
    val page: OsgbWorkspacePage = OsgbWorkspacePage.Workspaces,
) {
    val hasWorkspace: Boolean? get() = if (loading) null else workspaces.isNotEmpty()
}

@HiltViewModel
class OsgbWorkspaceViewModel @Inject constructor(
    private val repository: IsgWorkspaceRepository,
) : ViewModel() {
    private val mutableState = MutableStateFlow(OsgbWorkspaceUiState())
    val state = mutableState.asStateFlow()

    init { refreshWorkspaces() }

    fun refreshWorkspaces() {
        load {
            val workspaces = repository.listOsgbWorkspaces()
            val only = workspaces.singleOrNull()
            mutableState.value = OsgbWorkspaceUiState(
                loading = false,
                workspaces = workspaces,
                workspace = only,
                page = if (only == null) OsgbWorkspacePage.Workspaces else OsgbWorkspacePage.Companies,
            )
            if (only != null) refreshCompanies()
        }
    }

    fun selectWorkspace(workspace: IsgWorkspaceContext) {
        mutableState.value = state.value.copy(workspace = workspace, company = null,
            rows = emptyList(), metrics = null, dashboard = null, page = OsgbWorkspacePage.Companies)
        refreshCompanies()
    }

    fun refreshCompanies() {
        val workspace = state.value.workspace ?: return
        load(keepContent = true) {
            val companiesResponse = repository.companies(workspace)
            val dashboard = repository.dashboard(workspace, null)
            val companies = parseOsgbCompanies(companiesResponse)
            mutableState.value = state.value.copy(loading = false, error = null,
                companies = companies, dashboard = dashboard, page = OsgbWorkspacePage.Companies)
        }
    }

    fun selectCompany(company: OsgbCompanyItem) {
        val workspace = state.value.workspace ?: return
        mutableState.value = state.value.copy(company = company, rows = emptyList(), metrics = null,
            selectedRow = null, page = OsgbWorkspacePage.Company, loading = true, error = null)
        viewModelScope.launch {
            try {
                val dashboard = repository.dashboard(workspace, company.id)
                mutableState.value = state.value.copy(loading = false, dashboard = dashboard)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Throwable) {
                mutableState.value = state.value.copy(loading = false, error = "Firma özeti yüklenemedi.")
            }
        }
    }

    fun openDomain(domain: IsgWorkspaceDomain) {
        val workspace = state.value.workspace ?: return
        val company = state.value.company ?: return
        mutableState.value = state.value.copy(page = OsgbWorkspacePage.Domain(domain), loading = true,
            error = null, rows = emptyList(), metrics = null, selectedRow = null)
        viewModelScope.launch {
            try {
                val rowsRequest = async { repository.domain(workspace, company.id, domain) }
                val metricsRequest = async { repository.domainMetrics(workspace, company.id, domain) }
                val response = rowsRequest.await()
                mutableState.value = state.value.copy(
                    loading = false,
                    rows = (response["rows"] as? JsonArray).orEmpty().mapNotNull { it as? JsonObject },
                    metrics = metricsRequest.await(),
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Throwable) {
                mutableState.value = state.value.copy(loading = false, error = "Kayıtlar yüklenemedi.")
            }
        }
    }

    fun openPersonnelAdvanced(kind: IsgWorkspacePersonnelAdvancedKind) {
        val workspace = state.value.workspace ?: return
        val company = state.value.company ?: return
        readAdvanced(OsgbWorkspacePage.PersonnelAdvanced(kind)) {
            repository.personnelAdvanced(workspace, company.id, kind)
        }
    }

    fun openTrainingAdvanced(kind: IsgWorkspaceTrainingAdvancedKind) {
        val workspace = state.value.workspace ?: return
        val company = state.value.company ?: return
        readAdvanced(OsgbWorkspacePage.TrainingAdvanced(kind)) {
            repository.trainingAdvanced(workspace, company.id, kind)
        }
    }

    fun openAnalyses() {
        val workspace = state.value.workspace ?: return
        val company = state.value.company ?: return
        readAdvanced(OsgbWorkspacePage.Analyses) { repository.analyses(workspace, company.id) }
    }

    fun openAnalysis(row: JsonObject) {
        val workspace = state.value.workspace ?: return
        val company = state.value.company ?: return
        val id = row["id"]?.jsonPrimitive?.content ?: return
        load(keepContent = true) {
            val detail = repository.analysis(workspace, company.id, id)
            mutableState.value = state.value.copy(loading = false, selectedRow = detail, error = null)
        }
    }

    fun createExport(format: String) {
        val workspace = state.value.workspace ?: return
        val company = state.value.company ?: return
        val detail = state.value.selectedRow ?: return
        val analysis = detail["analysis"] as? JsonObject ?: return
        val id = analysis["id"]?.jsonPrimitive?.content ?: return
        load(keepContent = true) {
            repository.createExport(workspace, company.id, id, format)
            mutableState.value = state.value.copy(loading = false,
                notice = if (format == "pdf") "PDF raporu hazırlanıyor." else "Excel raporu hazırlanıyor.")
        }
    }

    private fun readAdvanced(page: OsgbWorkspacePage, request: suspend () -> JsonObject) {
        mutableState.value = state.value.copy(page = page, loading = true, error = null,
            rows = emptyList(), metrics = null, selectedRow = null)
        viewModelScope.launch {
            try {
                val response = request()
                mutableState.value = state.value.copy(loading = false,
                    rows = (response["rows"] as? JsonArray).orEmpty().mapNotNull { it as? JsonObject })
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Throwable) {
                mutableState.value = state.value.copy(loading = false, error = "Kayıtlar yüklenemedi.")
            }
        }
    }

    fun selectRow(row: JsonObject?) { mutableState.value = state.value.copy(selectedRow = row, notice = null) }

    fun back(): Boolean {
        val current = state.value
        return when (current.page) {
            is OsgbWorkspacePage.Domain, is OsgbWorkspacePage.PersonnelAdvanced,
            is OsgbWorkspacePage.TrainingAdvanced, OsgbWorkspacePage.Analyses -> {
                mutableState.value = current.copy(page = OsgbWorkspacePage.Company, rows = emptyList(),
                    metrics = null, selectedRow = null, error = null); true
            }
            OsgbWorkspacePage.Company -> {
                mutableState.value = current.copy(page = OsgbWorkspacePage.Companies, company = null,
                    rows = emptyList(), metrics = null, selectedRow = null, error = null); true
            }
            OsgbWorkspacePage.Companies -> if (current.workspaces.size > 1) {
                mutableState.value = current.copy(page = OsgbWorkspacePage.Workspaces, workspace = null,
                    companies = emptyList(), dashboard = null, error = null); true
            } else false
            OsgbWorkspacePage.Workspaces -> false
        }
    }

    private fun load(keepContent: Boolean = false, block: suspend () -> Unit) {
        mutableState.value = if (keepContent) state.value.copy(loading = true, error = null)
        else OsgbWorkspaceUiState(loading = true)
        viewModelScope.launch {
            try { block() }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Throwable) {
                mutableState.value = state.value.copy(loading = false,
                    error = "OSGB çalışma alanı şu anda yüklenemedi.")
            }
        }
    }

    override fun onCleared() {
        repository.clearSelection()
        super.onCleared()
    }
}
