package com.riskdetectedan.app.reports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.reports.Report
import com.riskdetectedan.core.data.reports.ReportsRepository
import com.riskdetectedan.feature.reports.ReportFile
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface GeneratedReportsUiState {
    data object Loading : GeneratedReportsUiState
    data object SignedOut : GeneratedReportsUiState
    data class Loaded(val items: List<Report>) : GeneratedReportsUiState
    data class Failed(val error: AppErrorMessage) : GeneratedReportsUiState
}

private const val REPORTS_CONTEXT = "Rapor işlemi tamamlanamadı"

/**
 * Faz R — real "Raporlar" tab, distinct from `feature:reports`'s [com.riskdetectedan.feature.reports.HistoryViewModel]
 * (that one lists the `analyses` history/Analizler tab and *generates* new reports; this one lists
 * already-generated `reports` rows and *opens* them). Reuses [ReportFile] — the same
 * bytes/fileName/mimeType one-shot payload shape `feature:reports` already established for the
 * FileProvider hand-off — rather than inventing a second identical type, `app` already depends on
 * `feature:reports` for [com.riskdetectedan.feature.reports.ReportsScreen].
 */
@HiltViewModel
class GeneratedReportsViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val reportsRepository: ReportsRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<GeneratedReportsUiState>(GeneratedReportsUiState.Loading)
    val state: StateFlow<GeneratedReportsUiState> = _state.asStateFlow()

    private val _openingReportId = MutableStateFlow<String?>(null)
    val openingReportId: StateFlow<String?> = _openingReportId.asStateFlow()

    private val _reportError = MutableStateFlow<AppErrorMessage?>(null)
    val reportError: StateFlow<AppErrorMessage?> = _reportError.asStateFlow()

    private val _reportFile = MutableStateFlow<ReportFile?>(null)
    val reportFile: StateFlow<ReportFile?> = _reportFile.asStateFlow()

    init {
        load()
    }

    fun load() {
        val userId = authRepository.currentUserId
        if (userId == null) {
            _state.value = GeneratedReportsUiState.SignedOut
            return
        }
        _state.value = GeneratedReportsUiState.Loading
        viewModelScope.launch {
            _state.value = when (val result = reportsRepository.listReports(userId)) {
                is RdResult.Success -> GeneratedReportsUiState.Loaded(result.value)
                is RdResult.Failure -> GeneratedReportsUiState.Failed(
                    AppErrorMessages.make(result.message, context = REPORTS_CONTEXT),
                )
            }
        }
    }

    /** Downloads an already-generated report's bytes and hands them off via [reportFile] — no
     * generate step needed here, unlike `HistoryViewModel.generateReport`, since these rows
     * already exist in `reports`. */
    fun openReport(report: Report) {
        if (_openingReportId.value != null) return
        _openingReportId.value = report.id
        _reportError.value = null
        viewModelScope.launch {
            when (val download = reportsRepository.downloadReportBytes(report.storagePath)) {
                is RdResult.Success -> _reportFile.value = ReportFile(
                    bytes = download.value,
                    fileName = report.fileName ?: "${report.documentNo ?: report.id}.xlsx",
                    mimeType = report.mimeType
                        ?: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                )
                is RdResult.Failure ->
                    _reportError.value = AppErrorMessages.make(download.message, context = REPORTS_CONTEXT)
            }
            _openingReportId.value = null
        }
    }

    fun clearReportFile() {
        _reportFile.value = null
    }

    fun clearReportError() {
        _reportError.value = null
    }
}
