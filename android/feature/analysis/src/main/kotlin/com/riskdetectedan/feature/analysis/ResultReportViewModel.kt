package com.riskdetectedan.feature.analysis

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.company.CompanyRepository
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.profile.ProfileRepository
import com.riskdetectedan.core.data.release.AndroidRuntimeGateName
import com.riskdetectedan.core.data.release.ReleasePolicyRepository
import com.riskdetectedan.core.data.reports.PdfReportFileName
import com.riskdetectedan.core.data.reports.PdfReportGenerator
import com.riskdetectedan.core.data.reports.PdfReportInput
import com.riskdetectedan.core.data.reports.ReportsRepository
import com.riskdetectedan.core.data.store.ReviewEligibilityRepository
import com.riskdetectedan.core.designsystem.R as RdR
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.inject.Inject

enum class ResultReportFormat { Pdf, Excel }

data class ResultReportRequest(
    val analysisId: String,
    val title: String,
    val canvasLabel: String,
    val createdAt: String?,
    val companyId: String?,
    val findings: List<Finding>,
    val coverPhotoBytes: ByteArray?,
)

data class ResultReportFile(
    val reportId: String,
    val bytes: ByteArray,
    val fileName: String,
    val mimeType: String,
)

sealed interface ResultReportUiState {
    data object Idle : ResultReportUiState
    data class Generating(val format: ResultReportFormat, val progress: Float) : ResultReportUiState
    data class Ready(val file: ResultReportFile) : ResultReportUiState
    data class Failed(val error: AppErrorMessage) : ResultReportUiState
}

/**
 * Result-screen counterpart of the archive report flow. It deliberately uses the same real
 * repositories/generator as History: PDF is rendered on-device and registered with its exact
 * page count; XLSX is produced by the server. The progress waypoints mirror iOS's presentation
 * controller while the underlying work remains authoritative and never gets cancelled merely
 * because the animation reaches a visual waypoint.
 */
@HiltViewModel
class ResultReportViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val reportsRepository: ReportsRepository,
    private val companyRepository: CompanyRepository,
    private val profileRepository: ProfileRepository,
    private val releasePolicyRepository: ReleasePolicyRepository,
    private val pdfReportGenerator: PdfReportGenerator,
    private val reviewEligibilityRepository: ReviewEligibilityRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<ResultReportUiState>(ResultReportUiState.Idle)
    val state: StateFlow<ResultReportUiState> = _state.asStateFlow()
    private var progressJob: Job? = null

    fun generate(request: ResultReportRequest, kind: String, method: String, format: ResultReportFormat) {
        if (_state.value is ResultReportUiState.Generating) return
        _state.value = ResultReportUiState.Generating(format, 0.07f)
        startProgress(format)
        viewModelScope.launch {
            val result = when (format) {
                ResultReportFormat.Pdf -> generatePdf(request, kind, method)
                ResultReportFormat.Excel -> generateExcel(request.analysisId, method)
            }
            progressJob?.cancel()
            progressJob = null
            when (result) {
                is RdResult.Success -> {
                    reviewEligibilityRepository.recordSuccessfulReport(result.value.reportId)
                    _state.value = ResultReportUiState.Generating(format, 1f)
                    delay(480)
                    _state.value = ResultReportUiState.Ready(result.value)
                }
                is RdResult.Failure -> _state.value = ResultReportUiState.Failed(
                    AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_rapor_islemi_tamamlanamadi),
                    ),
                )
            }
        }
    }

    fun clearReadyFile() {
        if (_state.value is ResultReportUiState.Ready) _state.value = ResultReportUiState.Idle
    }

    fun clearError() {
        if (_state.value is ResultReportUiState.Failed) _state.value = ResultReportUiState.Idle
    }

    private fun startProgress(format: ResultReportFormat) {
        progressJob?.cancel()
        progressJob = viewModelScope.launch {
            val waypoints = listOf(.12f, .18f, .23f, .31f, .38f, .46f, .54f, .61f, .68f, .71f, .76f, .81f, .86f, .90f)
            for (point in waypoints) {
                delay(420)
                val current = _state.value
                if (current !is ResultReportUiState.Generating) return@launch
                _state.value = current.copy(format = format, progress = maxOf(current.progress, point))
            }
            while (_state.value is ResultReportUiState.Generating) {
                delay(850)
                val current = _state.value as? ResultReportUiState.Generating ?: return@launch
                _state.value = current.copy(progress = (current.progress + .01f).coerceAtMost(.94f))
            }
        }
    }

    private suspend fun generatePdf(
        request: ResultReportRequest,
        kind: String,
        method: String,
    ): RdResult<ResultReportFile> {
        val userId = authRepository.currentUserId
            ?: return RdResult.Failure("auth_required", context.getString(RdR.string.rd_once_giris_yapmalisin))
        val gate = releasePolicyRepository.resolveGate(AndroidRuntimeGateName.PdfReports)
        if (!gate.enabled) {
            return RdResult.Failure(
                "pdf_gate_closed",
                context.getString(RdR.string.rd_android_pdf_kapali_format, gate.reason),
            )
        }

        val profile = (profileRepository.fetchProfile(userId) as? RdResult.Success)?.value
        val company = request.companyId?.let { companyId ->
            (companyRepository.listCompanies(includeArchived = true) as? RdResult.Success)
                ?.value?.firstOrNull { it.id == companyId }
        }
        val companyLogoBytes = company?.logoPath?.let { path ->
            (companyRepository.downloadLogo(path) as? RdResult.Success)?.value
        }
        val generated = try {
            withContext(Dispatchers.Default) {
                pdfReportGenerator.generate(
                    PdfReportInput(
                        kind = kind,
                        method = method,
                        title = request.title,
                        canvasLabel = request.canvasLabel,
                        createdAt = request.createdAt,
                        findings = request.findings,
                        companyName = company?.name ?: profile?.companyName,
                        companyAddress = company?.address,
                        companyLogoBytes = companyLogoBytes,
                        preparedByName = profile?.displayName ?: context.getString(RdR.string.rd_emdash),
                        preparedByTitle = profile?.title,
                        certificateNumber = profile?.certificateNumber,
                        coverPhotoBytes = request.coverPhotoBytes,
                    ),
                )
            }
        } catch (t: Throwable) {
            return RdResult.Failure("pdf_render_failed", t.message ?: context.getString(RdR.string.rd_pdf_olusturulamadi), t)
        }

        val fileName = PdfReportFileName.build(request.title, request.analysisId, kind, method)
        return when (
            val registered = reportsRepository.uploadAndRegisterPdfReport(
                userId = userId,
                analysisId = request.analysisId,
                pdfBytes = generated.bytes,
                fileNameSlug = fileName,
                kind = kind,
                method = method,
                title = request.title,
                pageCount = generated.pageCount,
                companyId = request.companyId,
            )
        ) {
            is RdResult.Success -> RdResult.Success(
                ResultReportFile(
                    reportId = registered.value.id,
                    bytes = generated.bytes,
                    fileName = registered.value.fileName ?: fileName,
                    mimeType = "application/pdf",
                ),
            )
            is RdResult.Failure -> RdResult.Failure(registered.code, registered.message, registered.cause)
        }
    }

    private suspend fun generateExcel(analysisId: String, method: String): RdResult<ResultReportFile> {
        val report = when (val generated = reportsRepository.generateExcelReport(analysisId, method)) {
            is RdResult.Success -> generated.value
            is RdResult.Failure -> return RdResult.Failure(generated.code, generated.message, generated.cause)
        }
        return when (val downloaded = reportsRepository.downloadReportBytes(report.storagePath)) {
            is RdResult.Success -> RdResult.Success(
                ResultReportFile(
                    reportId = report.id,
                    bytes = downloaded.value,
                    fileName = report.fileName ?: "${report.documentNo ?: report.id}.xlsx",
                    mimeType = report.mimeType
                        ?: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                ),
            )
            is RdResult.Failure -> RdResult.Failure(downloaded.code, downloaded.message, downloaded.cause)
        }
    }
}
