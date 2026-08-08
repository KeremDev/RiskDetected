package com.riskdetectedan.feature.reports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.analysis.AnalysisCanvas
import com.riskdetectedan.core.data.analysis.FindingsRepository
import com.riskdetectedan.core.data.analysis.HistoryItem
import com.riskdetectedan.core.data.analysis.HistoryRepository
import com.riskdetectedan.core.data.analysis.PhotoRepository
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.company.CompanyRepository
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.profile.ProfileRepository
import com.riskdetectedan.core.data.reports.PdfReportFileName
import com.riskdetectedan.core.data.reports.PdfReportGenerator
import com.riskdetectedan.core.data.reports.PdfReportInput
import com.riskdetectedan.core.data.reports.ReportsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.inject.Inject

sealed interface HistoryUiState {
    data object Loading : HistoryUiState
    data object SignedOut : HistoryUiState
    data class Loaded(val items: List<HistoryItem>) : HistoryUiState
    data class Failed(val error: AppErrorMessage) : HistoryUiState
}

private const val REPORTS_CONTEXT = "Rapor işlemi tamamlanamadı"

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
    private val findingsRepository: FindingsRepository,
    private val photoRepository: PhotoRepository,
    private val companyRepository: CompanyRepository,
    private val profileRepository: ProfileRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<HistoryUiState>(HistoryUiState.Loading)
    val state: StateFlow<HistoryUiState> = _state.asStateFlow()

    private val _generatingReportForId = MutableStateFlow<String?>(null)
    val generatingReportForId: StateFlow<String?> = _generatingReportForId.asStateFlow()

    /** Separate from [generatingReportForId] — Excel (server-side) and PDF (on-device) generation
     * can't collide in practice (both gate on the same button being disabled while their own flag
     * is set), but keeping them distinct avoids one flow's spinner showing on the other's row. */
    private val _generatingPdfForId = MutableStateFlow<String?>(null)
    val generatingPdfForId: StateFlow<String?> = _generatingPdfForId.asStateFlow()

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
            _state.value = HistoryUiState.SignedOut
            return
        }
        _state.value = HistoryUiState.Loading
        viewModelScope.launch {
            _state.value = when (val result = historyRepository.listHistory(userId)) {
                is RdResult.Success -> HistoryUiState.Loaded(result.value)
                is RdResult.Failure -> HistoryUiState.Failed(
                    AppErrorMessages.make(result.message, context = REPORTS_CONTEXT),
                )
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
                    _reportError.value = AppErrorMessages.make(result.message, context = REPORTS_CONTEXT)
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
                is RdResult.Failure -> _reportError.value = AppErrorMessages.make(download.message, context = REPORTS_CONTEXT)
            }
            _generatingReportForId.value = null
        }
    }

    /**
     * Real on-device PDF report generation (DEC-09) — real port of the client-orchestration half
     * of `ResultView.swift`'s `generateAndSharePDF`/`storeReport`: gather the analysis's real
     * data (findings/photos/company/profile — none of it kept around locally past the original
     * capture, since this can run against a long-past History item), render via
     * [PdfReportGenerator] off the main thread, upload + register through the real shared
     * `register-report` edge function (server-side quota enforcement, same as every other
     * report/analysis write path — this repository makes no local entitlement decision).
     *
     * Data-gathering failures are treated differently by importance: findings are required (no
     * point generating a reportless PDF); photos/company/profile are each best-effort — a missing
     * company logo or an unreadable profile still produces a real, useful report, just without
     * that one optional detail (mirrors this whole port's "never invent, degrade gracefully"
     * pattern rather than failing the entire generation over an optional decoration).
     */
    fun generatePdfReport(item: HistoryItem, method: String = "fine_kinney", kind: String = "standard") {
        if (_generatingPdfForId.value != null) return
        _generatingPdfForId.value = item.id
        _reportError.value = null
        val userId = authRepository.currentUserId
        if (userId == null) {
            _reportError.value = AppErrorMessages.make("Önce giriş yapmalısın.", context = REPORTS_CONTEXT)
            _generatingPdfForId.value = null
            return
        }
        viewModelScope.launch {
            val findings = when (val result = findingsRepository.fetchFindings(item.id)) {
                is RdResult.Success -> result.value
                is RdResult.Failure -> {
                    _reportError.value = AppErrorMessages.make(result.message, context = REPORTS_CONTEXT)
                    _generatingPdfForId.value = null
                    return@launch
                }
            }

            val photos = (photoRepository.listPhotos(item.id) as? RdResult.Success)?.value.orEmpty()
            val coverPhotoBytes = photos.firstOrNull()?.let { photo ->
                (photoRepository.downloadPhoto(photo.storagePath) as? RdResult.Success)?.value
            }

            val profile = (profileRepository.fetchProfile(userId) as? RdResult.Success)?.value
            val company = item.companyId?.let { companyId ->
                (companyRepository.listCompanies() as? RdResult.Success)?.value?.firstOrNull { it.id == companyId }
            }
            val companyLogoBytes = company?.logoPath?.let { path ->
                (companyRepository.downloadLogo(path) as? RdResult.Success)?.value
            }

            val canvasLabel = AnalysisCanvas.all.firstOrNull { it.id == item.canvas }?.title ?: item.canvas

            val pdfBytes = withContext(Dispatchers.Default) {
                PdfReportGenerator.generate(
                    PdfReportInput(
                        kind = kind,
                        method = method,
                        title = item.title,
                        canvasLabel = canvasLabel,
                        createdAt = item.createdAt,
                        findings = findings,
                        companyName = company?.name,
                        companyAddress = company?.address,
                        companyLogoBytes = companyLogoBytes,
                        preparedByName = profile?.displayName ?: "—",
                        preparedByTitle = profile?.title,
                        certificateNumber = profile?.certificateNumber,
                        coverPhotoBytes = coverPhotoBytes,
                    ),
                )
            }

            val fileNameSlug = PdfReportFileName.build(item.title, item.id, kind, method)
            when (
                val registered = reportsRepository.uploadAndRegisterPdfReport(
                    userId = userId,
                    analysisId = item.id,
                    pdfBytes = pdfBytes,
                    fileNameSlug = fileNameSlug,
                    kind = kind,
                    method = method,
                    title = item.title,
                    pageCount = maxOf(1, 1 + findings.size / 4),
                    companyId = item.companyId,
                )
            ) {
                is RdResult.Success -> _reportFile.value = ReportFile(
                    bytes = pdfBytes,
                    fileName = registered.value.fileName ?: fileNameSlug,
                    mimeType = "application/pdf",
                )
                is RdResult.Failure -> _reportError.value = AppErrorMessages.make(registered.message, context = REPORTS_CONTEXT)
            }
            _generatingPdfForId.value = null
        }
    }

    fun clearReportFile() {
        _reportFile.value = null
    }

    fun clearReportError() {
        _reportError.value = null
    }
}
