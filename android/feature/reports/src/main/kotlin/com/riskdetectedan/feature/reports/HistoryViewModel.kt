package com.riskdetectedan.feature.reports

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.analysis.AnalysisCanvas
import com.riskdetectedan.core.data.analysis.FindingsRepository
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.analysis.HistoryItem
import com.riskdetectedan.core.data.analysis.HistoryRepository
import com.riskdetectedan.core.data.analysis.PhotoRepository
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.company.Company
import com.riskdetectedan.core.data.company.CompanyRepository
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.profile.ProfileRepository
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.data.profile.UserProfile
import com.riskdetectedan.core.data.profile.resolvedLocalizationContext
import com.riskdetectedan.core.data.reports.PdfReportFileName
import com.riskdetectedan.core.data.reports.PdfReportGenerator
import com.riskdetectedan.core.data.reports.PdfReportInput
import com.riskdetectedan.core.data.reports.ReportQuotaUsage
import com.riskdetectedan.core.data.reports.ReportsRepository
import com.riskdetectedan.core.data.release.AndroidRuntimeGateName
import com.riskdetectedan.core.data.release.ReleasePolicyRepository
import com.riskdetectedan.core.data.store.ReviewEligibilityRepository
import com.riskdetectedan.core.data.telemetry.MetaAppEventsService
import com.riskdetectedan.core.designsystem.R as RdR
import com.riskdetectedan.core.designsystem.rdAnalysisCanvasTitleResource
import dagger.hilt.android.qualifiers.ApplicationContext
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

sealed interface ReportPreviewUiState {
    data object Idle : ReportPreviewUiState
    data object Loading : ReportPreviewUiState
    data class Loaded(val analysisId: String, val findings: List<Finding>) : ReportPreviewUiState
    data class Failed(val analysisId: String) : ReportPreviewUiState
}

/** One-shot payload the screen consumes to hand the downloaded bytes off to a FileProvider +
 * ACTION_VIEW intent, then clears via [HistoryViewModel.clearReportFile] — the repository layer
 * stays Context-free (see ReportsRepository's doc comment), so writing to disk and launching an
 * intent is the feature layer's job. */
data class ReportFile(val bytes: ByteArray, val fileName: String, val mimeType: String)

@HiltViewModel
class HistoryViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val historyRepository: HistoryRepository,
    private val reportsRepository: ReportsRepository,
    private val findingsRepository: FindingsRepository,
    private val photoRepository: PhotoRepository,
    private val companyRepository: CompanyRepository,
    private val profileRepository: ProfileRepository,
    private val releasePolicyRepository: ReleasePolicyRepository,
    private val pdfReportGenerator: PdfReportGenerator,
    private val reviewEligibilityRepository: ReviewEligibilityRepository,
    private val metaAppEvents: MetaAppEventsService,
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

    private val _deletingId = MutableStateFlow<String?>(null)
    val deletingId: StateFlow<String?> = _deletingId.asStateFlow()

    private val _deleteError = MutableStateFlow<AppErrorMessage?>(null)
    val deleteError: StateFlow<AppErrorMessage?> = _deleteError.asStateFlow()

    /** Real gap sweep finding (2026-08-09): `HistoryView.swift`'s company filter
     * (`companyFilterButton`/`CompanyPickerSheet`, gated `if app.currentTier.isPaid`) was
     * entirely missing on Android. [companies] feeds the picker list, [userTier] gates whether
     * the filter entry point shows at all (same paid-only restriction as iOS), both loaded
     * alongside history so the filter button is ready the moment the list itself is. */
    private val _companies = MutableStateFlow<List<Company>>(emptyList())
    val companies: StateFlow<List<Company>> = _companies.asStateFlow()

    private val _userTier = MutableStateFlow(SubscriptionTier.Free)
    val userTier: StateFlow<SubscriptionTier> = _userTier.asStateFlow()

    private val _profile = MutableStateFlow<UserProfile?>(null)
    val profile: StateFlow<UserProfile?> = _profile.asStateFlow()

    private val _reportPreview = MutableStateFlow<ReportPreviewUiState>(ReportPreviewUiState.Idle)
    val reportPreview: StateFlow<ReportPreviewUiState> = _reportPreview.asStateFlow()

    private val _reportQuotaUsage = MutableStateFlow<ReportQuotaUsage?>(null)
    val reportQuotaUsage: StateFlow<ReportQuotaUsage?> = _reportQuotaUsage.asStateFlow()

    private val _selectedCompanyFilter = MutableStateFlow<Company?>(null)
    val selectedCompanyFilter: StateFlow<Company?> = _selectedCompanyFilter.asStateFlow()

    fun setCompanyFilter(company: Company?) {
        _selectedCompanyFilter.value = company
    }

    /** Real port of `loadRecentItems()`'s `firstPhotoPaths(analysisIDs:)` call — analysisId ->
     * first (lowest sequence_index) Storage path, feeds [com.riskdetectedan.app.home.
     * RecentAnalysisRingCard]'s thumbnail. Best-effort: a failed fetch just leaves the map empty,
     * same as iOS's own `catch { paths = [:] }` (a missing thumbnail is not worth failing the
     * whole recent-analyses section over). */
    private val _photoPaths = MutableStateFlow<Map<String, String>>(emptyMap())
    val photoPaths: StateFlow<Map<String, String>> = _photoPaths.asStateFlow()

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
            when (val result = historyRepository.listHistory(userId)) {
                is RdResult.Success -> {
                    _state.value = HistoryUiState.Loaded(result.value)
                    // Same prefix(8) scope as iOS's loadRecentItems() — Home's ring row only
                    // ever shows 8, no point fetching paths for the rest of a 50-row history page.
                    val recentIds = result.value.take(8).map { it.id }
                    _photoPaths.value = (photoRepository.firstPhotoPaths(recentIds) as? RdResult.Success)
                        ?.value.orEmpty()
                }
                is RdResult.Failure -> _state.value = HistoryUiState.Failed(
                    AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_rapor_islemi_tamamlanamadi),
                    ),
                )
            }
            _companies.value = (companyRepository.listCompanies() as? RdResult.Success)?.value.orEmpty()
            val profile = (profileRepository.fetchProfile(userId) as? RdResult.Success)?.value
            _profile.value = profile
            val tier = profile?.tier ?: SubscriptionTier.Free
            _userTier.value = tier
            _reportQuotaUsage.value = (reportsRepository.fetchQuotaUsage(userId, tier) as? RdResult.Success)?.value
        }
    }

    fun loadReportPreview(item: HistoryItem) {
        val loaded = _reportPreview.value as? ReportPreviewUiState.Loaded
        if (loaded?.analysisId == item.id) return
        _reportPreview.value = ReportPreviewUiState.Loading
        viewModelScope.launch {
            _reportPreview.value = when (val result = findingsRepository.fetchFindings(item.id)) {
                is RdResult.Success -> ReportPreviewUiState.Loaded(item.id, result.value)
                is RdResult.Failure -> ReportPreviewUiState.Failed(item.id)
            }
        }
    }

    fun clearReportPreview() {
        _reportPreview.value = ReportPreviewUiState.Idle
    }

    /** Mirrors calling `generate-excel-report` then fetching the resulting file, matching how
     * iOS's report flow both creates the archive row and hands the user a document — the two
     * separate repository calls (generate, then download) are sequential here since the client
     * needs the `storage_path` the first call returns before it can do the second. */
    fun generateReport(item: HistoryItem, method: String? = null, companyId: String? = item.companyId) {
        if (_generatingReportForId.value != null) return
        _generatingReportForId.value = item.id
        _reportError.value = null
        viewModelScope.launch {
            val localization = _profile.value.resolvedLocalizationContext()
            val report = when (val result = reportsRepository.generateExcelReport(
                analysisId = item.id,
                method = method ?: localization.defaultRiskMethod,
                companyId = companyId,
                localization = localization,
            )) {
                is RdResult.Success -> result.value.also {
                    // The backend has created the report row at this boundary. A later local
                    // download failure must not erase that real conversion.
                    metaAppEvents.reportCreated(it.id, "xlsx")
                }
                is RdResult.Failure -> {
                    _reportError.value = AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_rapor_islemi_tamamlanamadi),
                    )
                    _generatingReportForId.value = null
                    return@launch
                }
            }
            when (val download = reportsRepository.downloadReportBytes(report.storagePath)) {
                is RdResult.Success -> {
                    _reportFile.value = ReportFile(
                        bytes = download.value,
                        fileName = report.fileName ?: "${report.documentNo ?: report.id}.xlsx",
                        mimeType = report.mimeType
                            ?: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    )
                    reviewEligibilityRepository.recordSuccessfulReport(report.id)
                }
                is RdResult.Failure -> _reportError.value = AppErrorMessages.make(
                    download.message,
                    context = context.getString(RdR.string.rd_rapor_islemi_tamamlanamadi),
                )
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
    fun generatePdfReport(
        item: HistoryItem,
        method: String? = null,
        kind: String = "standard",
        companyId: String? = item.companyId,
        preparedByName: String? = null,
        preparedByTitle: String? = null,
        certificateNumber: String? = null,
    ) {
        if (_generatingPdfForId.value != null) return
        _generatingPdfForId.value = item.id
        _reportError.value = null
        val userId = authRepository.currentUserId
        if (userId == null) {
            _reportError.value = AppErrorMessages.make(
                context.getString(RdR.string.rd_once_giris_yapmalisin),
                context = context.getString(RdR.string.rd_rapor_islemi_tamamlanamadi),
            )
            _generatingPdfForId.value = null
            return
        }
        viewModelScope.launch {
            val runtimeGate = releasePolicyRepository.resolveGate(AndroidRuntimeGateName.PdfReports)
            if (!runtimeGate.enabled) {
                _reportError.value = AppErrorMessages.make(
                    context.getString(RdR.string.rd_android_pdf_kapali_format, runtimeGate.reason),
                    context = context.getString(RdR.string.rd_rapor_islemi_tamamlanamadi),
                )
                _generatingPdfForId.value = null
                return@launch
            }
            val findings = when (val result = findingsRepository.fetchFindings(item.id)) {
                is RdResult.Success -> result.value
                is RdResult.Failure -> {
                    _reportError.value = AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_rapor_islemi_tamamlanamadi),
                    )
                    _generatingPdfForId.value = null
                    return@launch
                }
            }

            val photos = (photoRepository.listPhotos(item.id) as? RdResult.Success)?.value.orEmpty()
            val coverPhotoBytesList = photos.take(5).mapNotNull { photo ->
                (photoRepository.downloadPhoto(photo.storagePath) as? RdResult.Success)?.value
            }
            val coverPhotoBytes = coverPhotoBytesList.firstOrNull()

            val profile = (profileRepository.fetchProfile(userId) as? RdResult.Success)?.value
            val localization = profile.resolvedLocalizationContext()
            val resolvedMethod = method ?: localization.defaultRiskMethod
            val company = companyId?.let { selectedCompanyId ->
                (companyRepository.listCompanies() as? RdResult.Success)?.value?.firstOrNull { it.id == selectedCompanyId }
            }
            val companyLogoBytes = company?.logoPath?.let { path ->
                (companyRepository.downloadLogo(path) as? RdResult.Success)?.value
            }

            val canvasLabel = rdAnalysisCanvasTitleResource(item.canvas)?.let(context::getString)
                ?: AnalysisCanvas.all.firstOrNull { it.id == item.canvas }?.title
                ?: item.canvas

            val generatedPdf = try {
                withContext(Dispatchers.Default) {
                    pdfReportGenerator.generate(
                        PdfReportInput(
                            analysisId = item.id,
                            kind = kind,
                            method = resolvedMethod,
                            title = item.title,
                            canvasLabel = canvasLabel,
                            createdAt = item.createdAt,
                            findings = findings,
                            companyName = company?.name,
                            companyAddress = company?.address,
                            companyLogoBytes = companyLogoBytes,
                            preparedByName = preparedByName?.trim()?.takeIf { it.isNotEmpty() }
                                ?: profile?.displayName
                                ?: context.getString(RdR.string.rd_emdash),
                            preparedByTitle = preparedByTitle?.trim()?.takeIf { it.isNotEmpty() }
                                ?: profile?.title,
                            certificateNumber = certificateNumber?.trim()?.takeIf { it.isNotEmpty() }
                                ?: profile?.certificateNumber,
                            coverPhotoBytes = coverPhotoBytes,
                            coverPhotoBytesList = coverPhotoBytesList,
                            analysisSummary = item.aiSummary,
                            analysisSectorLabel = item.analysisSector,
                            languageCode = localization.appLanguage,
                        ),
                    )
                }
            } catch (t: Throwable) {
                _reportError.value = AppErrorMessages.make(
                    t,
                    context = context.getString(RdR.string.rd_pdf_olusturulamadi),
                )
                _generatingPdfForId.value = null
                return@launch
            }

            val fileNameSlug = PdfReportFileName.build(item.title, item.id, kind, resolvedMethod)
            when (
                val registered = reportsRepository.uploadAndRegisterPdfReport(
                    userId = userId,
                    analysisId = item.id,
                    pdfBytes = generatedPdf.bytes,
                    fileNameSlug = fileNameSlug,
                    kind = kind,
                    method = resolvedMethod,
                    title = item.title,
                    pageCount = generatedPdf.pageCount,
                    companyId = companyId,
                    localization = localization,
                )
            ) {
                is RdResult.Success -> {
                    metaAppEvents.reportCreated(registered.value.id, "pdf")
                    _reportFile.value = ReportFile(
                        bytes = generatedPdf.bytes,
                        fileName = registered.value.fileName ?: fileNameSlug,
                        mimeType = "application/pdf",
                    )
                    reviewEligibilityRepository.recordSuccessfulReport(registered.value.id)
                }
                is RdResult.Failure -> _reportError.value = AppErrorMessages.make(
                    registered.message,
                    context = context.getString(RdR.string.rd_rapor_islemi_tamamlanamadi),
                )
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

    /** Real gap sweep finding (2026-08-09): History had no delete action at all — real port of
     * `HistoryView.swift`'s `deleteAnalysis(_:)`, see [HistoryRepository.deleteAnalysis]'s doc
     * comment for the storage+row cleanup it does. Removes the row from local state on success,
     * same "no full refetch needed" reasoning as [com.riskdetectedan.feature.analysis.
     * AnalysisViewModel]'s finding-delete — deletion doesn't change any *other* row's data, a
     * local list-remove is honest here. */
    fun deleteAnalysis(item: HistoryItem) {
        if (_deletingId.value != null) return
        _deletingId.value = item.id
        _deleteError.value = null
        viewModelScope.launch {
            when (val result = historyRepository.deleteAnalysis(item.id)) {
                is RdResult.Success -> {
                    val current = _state.value as? HistoryUiState.Loaded
                    if (current != null) {
                        _state.value = current.copy(items = current.items.filterNot { it.id == item.id })
                    }
                }
                is RdResult.Failure -> _deleteError.value = AppErrorMessages.make(
                    result.message,
                    context = context.getString(RdR.string.rd_rapor_islemi_tamamlanamadi),
                )
            }
            _deletingId.value = null
        }
    }

    fun clearDeleteError() {
        _deleteError.value = null
    }
}
