package com.riskdetectedan.feature.reports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.analysis.HistoryItem
import com.riskdetectedan.core.data.analysis.HistoryRepository
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.reports.ReportsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface HistoryUiState {
    data object Loading : HistoryUiState
    data object SignedOut : HistoryUiState
    data class Loaded(val items: List<HistoryItem>) : HistoryUiState
    data class Failed(val message: String) : HistoryUiState
}

/** One-shot payload the screen consumes to hand the downloaded bytes off to a FileProvider +
 * ACTION_VIEW intent, then clears via [HistoryViewModel.clearReportFile] — the repository layer
 * stays Context-free (see ReportsRepository's doc comment), so writing to disk and launching an
 * intent is the feature layer's job. */
data class ReportFile(val bytes: ByteArray, val fileName: String, val mimeType: String)

@HiltViewModel
class HistoryViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val historyRepository: HistoryRepository,
    private val reportsRepository: ReportsRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<HistoryUiState>(HistoryUiState.Loading)
    val state: StateFlow<HistoryUiState> = _state.asStateFlow()

    private val _generatingReportForId = MutableStateFlow<String?>(null)
    val generatingReportForId: StateFlow<String?> = _generatingReportForId.asStateFlow()

    private val _reportError = MutableStateFlow<String?>(null)
    val reportError: StateFlow<String?> = _reportError.asStateFlow()

    private val _reportFile = MutableStateFlow<ReportFile?>(null)
    val reportFile: StateFlow<ReportFile?> = _reportFile.asStateFlow()

    init {
        load()
    }

    fun load() {
        val userId = authRepository.currentUserId
        if (userId == null) {
            _state.value = HistoryUiState.SignedOut
            return
        }
        _state.value = HistoryUiState.Loading
        viewModelScope.launch {
            _state.value = when (val result = historyRepository.listHistory(userId)) {
                is RdResult.Success -> HistoryUiState.Loaded(result.value)
                is RdResult.Failure -> HistoryUiState.Failed(result.message)
            }
        }
    }

    /** Mirrors calling `generate-excel-report` then fetching the resulting file, matching how
     * iOS's report flow both creates the archive row and hands the user a document — the two
     * separate repository calls (generate, then download) are sequential here since the client
     * needs the `storage_path` the first call returns before it can do the second. */
    fun generateReport(item: HistoryItem) {
        if (_generatingReportForId.value != null) return
        _generatingReportForId.value = item.id
        _reportError.value = null
        viewModelScope.launch {
            val report = when (val result = reportsRepository.generateExcelReport(item.id)) {
                is RdResult.Success -> result.value
                is RdResult.Failure -> {
                    _reportError.value = result.message
                    _generatingReportForId.value = null
                    return@launch
                }
            }
            when (val download = reportsRepository.downloadReportBytes(report.storagePath)) {
                is RdResult.Success -> _reportFile.value = ReportFile(
                    bytes = download.value,
                    fileName = report.fileName ?: "${report.documentNo ?: report.id}.xlsx",
                    mimeType = report.mimeType
                        ?: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                )
                is RdResult.Failure -> _reportError.value = download.message
            }
            _generatingReportForId.value = null
        }
    }

    fun clearReportFile() {
        _reportFile.value = null
    }

    fun clearReportError() {
        _reportError.value = null
    }
}
