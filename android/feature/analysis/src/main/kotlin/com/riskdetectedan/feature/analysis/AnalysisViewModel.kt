package com.riskdetectedan.feature.analysis

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdClientMetadata
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.analysis.AnalysisRepository
import com.riskdetectedan.core.data.analysis.AnalysisResultSummary
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.AnalysisStatus
import com.riskdetectedan.core.data.analysis.CreateAnalysisRequest
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.analysis.FindingPatch
import com.riskdetectedan.core.data.analysis.FindingsRepository
import com.riskdetectedan.core.data.analysis.InFlightAnalysis
import com.riskdetectedan.core.data.analysis.InFlightAnalysisStore
import com.riskdetectedan.core.data.analysis.PendingAnalysisSubmission
import com.riskdetectedan.core.data.analysis.PhotoRepository
import com.riskdetectedan.core.data.analysis.PlanCapabilities
import com.riskdetectedan.core.data.analysis.PlanCapabilitiesRepository
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.profile.ProfileRepository
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.data.release.AndroidRuntimeGateName
import com.riskdetectedan.core.data.release.ReleasePolicyRepository
import com.riskdetectedan.core.designsystem.R as RdR
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import javax.inject.Inject

sealed interface CreateAnalysisUiState {
    data object Idle : CreateAnalysisUiState
    data object Creating : CreateAnalysisUiState
    data object UploadingPhoto : CreateAnalysisUiState
    data object Submitting : CreateAnalysisUiState
    data class Polling(val analysisId: String) : CreateAnalysisUiState
    data class Finalizing(val analysisId: String) : CreateAnalysisUiState
    data class Completed(val analysisId: String, val findings: List<Finding>) : CreateAnalysisUiState
    data class CreatedWithoutPhoto(val analysisId: String) : CreateAnalysisUiState
    data class Failed(val error: AppErrorMessage) : CreateAnalysisUiState
}

internal object AnalysisSubmissionGuard {
    fun canStart(state: CreateAnalysisUiState): Boolean =
        state is CreateAnalysisUiState.Idle ||
            state is CreateAnalysisUiState.Failed ||
            state is CreateAnalysisUiState.CreatedWithoutPhoto
}

@HiltViewModel
class AnalysisViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val analysisRepository: AnalysisRepository,
    private val photoRepository: PhotoRepository,
    private val findingsRepository: FindingsRepository,
    private val inFlightStore: InFlightAnalysisStore,
    private val profileRepository: ProfileRepository,
    private val planCapabilitiesRepository: PlanCapabilitiesRepository,
    private val releasePolicyRepository: ReleasePolicyRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<CreateAnalysisUiState>(CreateAnalysisUiState.Idle)
    val state: StateFlow<CreateAnalysisUiState> = _state.asStateFlow()

    /**
     * Separate mutable copy of the completed findings list, kept in sync with
     * [CreateAnalysisUiState.Completed] but independently updatable — [deleteFinding] mutates
     * this in place instead of reconstructing a new `Completed` state, since the analysisId
     * inside that state doesn't change and re-fetching the whole findings list after every
     * single delete would be wasteful (mirrors optimistic local removal; the edge function is
     * still the source of truth and a failed delete restores the row).
     */
    private val _findings = MutableStateFlow<List<Finding>>(emptyList())
    val findings: StateFlow<List<Finding>> = _findings.asStateFlow()

    private val _deleteError = MutableStateFlow<AppErrorMessage?>(null)
    val deleteError: StateFlow<AppErrorMessage?> = _deleteError.asStateFlow()

    private val _updateError = MutableStateFlow<AppErrorMessage?>(null)
    val updateError: StateFlow<AppErrorMessage?> = _updateError.asStateFlow()

    private val _capabilities = MutableStateFlow(PlanCapabilities.forTier(SubscriptionTier.Free))
    val capabilities: StateFlow<PlanCapabilities> = _capabilities.asStateFlow()

    private val _resultSummary = MutableStateFlow<AnalysisResultSummary?>(null)
    val resultSummary: StateFlow<AnalysisResultSummary?> = _resultSummary.asStateFlow()

    private val _resultPhotoBytes = MutableStateFlow<List<ByteArray>>(emptyList())
    val resultPhotoBytes: StateFlow<List<ByteArray>> = _resultPhotoBytes.asStateFlow()

    /**
     * Full submit flow, mirroring AnalysisService.swift's sequence: create -> upload photo(s)
     * -> invoke `analyze` -> poll for a terminal status. Without a photo, stops after create
     * (matches the backend requiring at least one photo before `analyze` will do anything
     * useful — no point invoking it with an empty photo_paths array). [photoPaths] supports the
     * real multi-photo flow (Faz O, up to `PlanCapabilities.safeMaxPhotosPerAnalysis` — iOS caps
     * this at 3 regardless of tier — via Home's real `PhotoTraySheet`); `sequenceIndex` is
     * 1-based per photo position, matching the single-photo path's existing convention.
     *
     * [canvasIds] mirrors AnalysisService.swift's real canvas-selection contract (Faz Q,
     * 2026-08-08): `canvas` (the `analyses` row + primary AnalyzeRequestBody field) = the
     * lexicographically-sorted-first id, `canvases` = the full sorted selection — matches the
     * Swift comment "canvas field = primary (first sorted) id — legacy single-id contract
     * korunuyor" exactly. Defaults to `["general"]` for any caller that doesn't have a real
     * [com.riskdetectedan.core.data.analysis.AnalysisCanvas] selection yet (e.g. the quick-scan
     * Capture route, which still bypasses CanvasSheet entirely).
     */
    fun createAnalysis(
        sector: AnalysisSector?,
        photoPaths: List<String>,
        canvasIds: List<String> = listOf("general"),
        analysisMode: String = "standard",
    ) {
        if (!AnalysisSubmissionGuard.canStart(_state.value)) return
        val userId = authRepository.currentUserId
        if (userId == null) {
            _state.value = CreateAnalysisUiState.Failed(
                AppErrorMessages.make(
                    context.getString(RdR.string.rd_once_giris_yapmalisin),
                    context = context.getString(RdR.string.rd_analiz_tamamlanamadi),
                ),
            )
            return
        }
        // Absolute safety ceiling. The tier/release-gate limit is resolved below before a row is
        // created, while the backend remains authoritative at submit time.
        // regardless of tier (the tier-based 1/3 cap is a *lower* bound gate, this is the
        // absolute ceiling AnalysisService.swift itself enforces before ever calling the server).
        if (photoPaths.size > 3) {
            _state.value = CreateAnalysisUiState.Failed(
                AppErrorMessages.make(
                    context.getString(RdR.string.rd_en_fazla_uc_fotograf),
                    context = context.getString(RdR.string.rd_analiz_tamamlanamadi),
                ),
            )
            return
        }
            val sortedCanvasIds = canvasIds.sorted().ifEmpty { listOf("general") }
            val canvas = sortedCanvasIds.first()
        _state.value = CreateAnalysisUiState.Creating
        viewModelScope.launch {
            val runtimeGate = releasePolicyRepository.resolveGate(AndroidRuntimeGateName.AnalysisSubmit)
            if (!runtimeGate.enabled) {
                _state.value = CreateAnalysisUiState.Failed(
                    AppErrorMessages.make(
                        context.getString(RdR.string.rd_android_analiz_kapali_format, runtimeGate.reason),
                        context = context.getString(RdR.string.rd_analiz_tamamlanamadi),
                    ),
                )
                return@launch
            }
            val profile = (profileRepository.fetchProfile(userId) as? RdResult.Success)?.value
            val tier = profile?.tier ?: SubscriptionTier.Free
            val capabilities = resolveCapabilities(tier)
            _capabilities.value = capabilities
            val riskMethod = profile?.preferredMethod
                ?.takeIf { it == "fine_kinney" || it == "matrix_5x5" }
                ?: RdClientMetadata.DEFAULT_RISK_METHOD
            if (analysisMode == "detailed" && !capabilities.canUseDetailedAnalysis) {
                _state.value = CreateAnalysisUiState.Failed(
                    AppErrorMessages.make(
                        context.getString(RdR.string.rd_detayli_analiz_uyelik_gerekir),
                        context = context.getString(RdR.string.rd_analiz_tamamlanamadi),
                    ),
                )
                return@launch
            }
            if (photoPaths.size > capabilities.maxPhotosPerAnalysis) {
                _state.value = CreateAnalysisUiState.Failed(
                    AppErrorMessages.make(
                        context.getString(
                            RdR.string.rd_plan_fotograf_limiti_format,
                            capabilities.maxPhotosPerAnalysis,
                        ),
                        context = context.getString(RdR.string.rd_analiz_tamamlanamadi),
                    ),
                )
                return@launch
            }
            val inputFingerprint = submissionFingerprint(
                userId = userId,
                sectorId = sector?.id,
                photoPaths = photoPaths,
                canvasIds = sortedCanvasIds,
                analysisMode = analysisMode,
            )
            val pendingSubmission = inFlightStore.pendingFor(userId, inputFingerprint)
                ?: PendingAnalysisSubmission(
                    submissionId = UUID.randomUUID().toString(),
                    userId = userId,
                    inputFingerprint = inputFingerprint,
                    startedAtMillis = System.currentTimeMillis(),
                ).also(inFlightStore::savePending)
            val request = CreateAnalysisRequest(
                userId = userId,
                title = sector?.titleTr ?: context.getString(RdR.string.rd_adsiz_analiz),
                canvas = canvas,
                sector = sector,
                clientSubmissionId = pendingSubmission.submissionId,
                primaryMethod = riskMethod,
            )
            val analysisId = when (val created = analysisRepository.createAnalysis(request)) {
                is RdResult.Failure -> {
                    _state.value = CreateAnalysisUiState.Failed(
                        AppErrorMessages.make(
                            created.message,
                            context = context.getString(RdR.string.rd_analiz_tamamlanamadi),
                        ),
                    )
                    return@launch
                }
                is RdResult.Success -> created.value
            }
            inFlightStore.clearPending(pendingSubmission.submissionId)

            val files = photoPaths.map { File(it) }.filter { it.exists() }
            if (files.isEmpty()) {
                _state.value = CreateAnalysisUiState.CreatedWithoutPhoto(analysisId)
                return@launch
            }

            // Real port of runPhotoAnalysis's InFlightAnalysisStore.shared.save — right after
            // create, before upload/submit, so a process death anywhere past this point (upload,
            // submit, or during the multi-minute poll) still has a record to resume from. Cleared
            // at every terminal state below.
            inFlightStore.save(
                InFlightAnalysis(
                    analysisId = analysisId,
                    userId = userId,
                    photoCount = files.size,
                    startedAtMillis = System.currentTimeMillis(),
                    title = request.title,
                ),
            )

            _state.value = CreateAnalysisUiState.UploadingPhoto
            val uploadedPaths = mutableListOf<String>()
            for ((index, file) in files.withIndex()) {
                val jpegBytes = file.readBytes()
                when (
                    val uploadResult =
                        photoRepository.uploadPhoto(userId, analysisId, sequenceIndex = index + 1, jpegBytes)
                ) {
                    is RdResult.Success -> uploadedPaths.add(uploadResult.value)
                    is RdResult.Failure -> {
                        val error = AppErrorMessages.make(
                            uploadResult.message,
                            context = context.getString(RdR.string.rd_analiz_tamamlanamadi),
                        )
                        failAnalysisAndCleanup(userId, analysisId, uploadedPaths, error.message)
                        _state.value = CreateAnalysisUiState.Failed(error)
                        return@launch
                    }
                }
            }

            _state.value = CreateAnalysisUiState.Submitting
            when (
                val submitResult = analysisRepository.submitAnalyze(
                    analysisId = analysisId,
                    canvas = canvas,
                    canvases = sortedCanvasIds,
                    analysisMode = analysisMode,
                    sector = sector,
                    photoPaths = uploadedPaths,
                    riskMethod = riskMethod,
                )
            ) {
                is RdResult.Failure -> {
                    // Real port of recoverPhotoSubmissionIfServerAccepted: a network/timeout
                    // failure here doesn't necessarily mean the server never got the request —
                    // probe status a few times before trusting the client-side failure. If it
                    // recovers, fall straight through to polling below as if submit succeeded.
                    if (!probeSubmissionRecovery(analysisId)) {
                        val error = AppErrorMessages.make(
                            submitResult.message,
                            context = context.getString(RdR.string.rd_analiz_tamamlanamadi),
                        )
                        failAnalysisAndCleanup(userId, analysisId, uploadedPaths, error.message)
                        _state.value = CreateAnalysisUiState.Failed(error)
                        return@launch
                    }
                }
                is RdResult.Success -> Unit
            }

            pollAndHandleResult(analysisId, photoCount = uploadedPaths.size)
        }
    }

    private fun submissionFingerprint(
        userId: String,
        sectorId: String?,
        photoPaths: List<String>,
        canvasIds: List<String>,
        analysisMode: String,
    ): String {
        val canonical = listOf(
            userId,
            sectorId.orEmpty(),
            analysisMode,
            canvasIds.joinToString(","),
            photoPaths.joinToString("|") { path ->
                val file = File(path)
                "$path:${file.length()}:${file.lastModified()}"
            },
        ).joinToString("\n")
        return MessageDigest.getInstance("SHA-256")
            .digest(canonical.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }
    }

    /**
     * Shared by the normal create->upload->submit flow and [resumeIfInFlight] — real port of the
     * status-handling half of `waitForCompletedResult`'s caller. Always clears the in-flight
     * record on a terminal outcome (mirrors iOS's `InFlightAnalysisStore.shared.clear` calls
     * inside `waitForCompletedResult` on both the completed and failed paths, plus
     * `resumeAnalysis`'s caller-side clear).
     */
    private suspend fun pollAndHandleResult(analysisId: String, photoCount: Int) {
        _state.value = CreateAnalysisUiState.Polling(analysisId)
        val status = analysisRepository.pollAnalysisStatus(analysisId, photoCount = photoCount)
        // Real port of iOS's clear-call placement: `completed`/`failed` (genuinely terminal
        // server-side statuses) clear the record. A deadline timeout does NOT clear — the server
        // may still be working past the client's own wall-clock poll deadline, and leaving the
        // record lets a later relaunch pick the poll back up (matches waitForCompletedResult
        // exactly: its post-loop timeout throw has no clear() call, unlike the completed/failed
        // branches inside the loop).
        if (status is AnalysisStatus.Completed || status is AnalysisStatus.Failed) {
            inFlightStore.clear(analysisId)
        }
        val nextState = when (status) {
            is AnalysisStatus.Completed -> {
                val findings = when (val result = findingsRepository.fetchFindings(analysisId)) {
                    is RdResult.Success -> result.value
                    // A completed analysis with an unreadable findings list is still worth
                    // showing as completed — surface an empty list rather than fail the
                    // whole screen over what's likely a transient read error.
                    is RdResult.Failure -> emptyList()
                }
                _findings.value = findings
                _state.value = CreateAnalysisUiState.Finalizing(analysisId)
                loadResultContext(analysisId)
                // iOS completes the progress ring before revealing the result. Keeping this
                // short hand-off also prevents a completed result from briefly rendering without
                // its source-photo mosaic and metadata while those final reads are still running.
                delay(520)
                CreateAnalysisUiState.Completed(analysisId, findings)
            }
            is AnalysisStatus.Failed ->
                CreateAnalysisUiState.Failed(
                    AppErrorMessages.make(
                        status.message ?: context.getString(RdR.string.rd_analiz_basarisiz),
                        context = context.getString(RdR.string.rd_analiz_tamamlanamadi),
                    ),
                )
            is AnalysisStatus.TimedOut ->
                CreateAnalysisUiState.Failed(
                    AppErrorMessages.make(
                        context.getString(RdR.string.rd_analiz_zaman_asimi),
                        context = context.getString(RdR.string.rd_analiz_tamamlanamadi),
                    ),
                )
            is AnalysisStatus.InProgress ->
                CreateAnalysisUiState.Failed(
                    AppErrorMessages.make(
                        context.getString(RdR.string.rd_analiz_beklenmedik_durdu_format, status.status),
                        context = context.getString(RdR.string.rd_analiz_tamamlanamadi),
                    ),
                )
        }
        _state.value = nextState
    }

    /** Loads the same result metadata and source photographs iOS keeps in AnalysisResultBundle. */
    private suspend fun loadResultContext(analysisId: String) {
        _resultSummary.value = (analysisRepository.fetchResultSummary(analysisId) as? RdResult.Success)?.value
        val photos = (photoRepository.listPhotos(analysisId) as? RdResult.Success)?.value.orEmpty()
        _resultPhotoBytes.value = photos.mapNotNull { photo ->
            (photoRepository.downloadPhoto(photo.storagePath) as? RdResult.Success)?.value
        }
    }

    /** Opens a completed history row in the exact same result surface used by a fresh analysis. */
    fun openCompletedAnalysis(analysisId: String) {
        val current = _state.value
        if ((current as? CreateAnalysisUiState.Completed)?.analysisId == analysisId ||
            (current as? CreateAnalysisUiState.Finalizing)?.analysisId == analysisId
        ) return
        val userId = authRepository.currentUserId ?: return
        _state.value = CreateAnalysisUiState.Finalizing(analysisId)
        viewModelScope.launch {
            _capabilities.value = resolveCapabilities(userId)
            val findings = (findingsRepository.fetchFindings(analysisId) as? RdResult.Success)?.value.orEmpty()
            _findings.value = findings
            loadResultContext(analysisId)
            delay(520)
            _state.value = CreateAnalysisUiState.Completed(analysisId, findings)
        }
    }

    /**
     * Real port of `resumeInFlightAnalysisIfNeeded` + `resumeAnalysis` — checks for an in-flight
     * record belonging to [userId] and, if found, jumps straight into polling for it (skips
     * create/upload/submit entirely, exactly like iOS's `resumeAnalysis` which calls
     * `waitForCompletedResult` directly). Returns whether a resume actually started, so the
     * caller (Home, in this port — mirrors iOS's own Home-driven trigger) knows whether to
     * navigate into the Analysis screen at all.
     */
    fun resumeIfInFlight(): Boolean {
        val userId = authRepository.currentUserId ?: return false
        val inFlight = inFlightStore.load(userId) ?: return false
        _state.value = CreateAnalysisUiState.Polling(inFlight.analysisId)
        viewModelScope.launch {
            _capabilities.value = resolveCapabilities(userId)
            pollAndHandleResult(inFlight.analysisId, photoCount = inFlight.photoCount)
        }
        return true
    }

    /**
     * Real port of `recoverPhotoSubmissionIfServerAccepted` — probes `analyses.status` at
     * 2s/3s/5s delays (matches iOS's exact probe schedule). If the status ever moves away from
     * `"pending"` at any probe, the server actually accepted and started processing the request
     * despite the client-side failure (a network blip after the request landed, a slow response
     * the client's own timeout gave up on first) — returns `true`, telling the caller to
     * continue straight into polling as if submit had succeeded. Only returns `false` (genuinely
     * not recovered) once every probe still reads `"pending"` — mirrors iOS's real
     * `guard lastStatus == "pending" else { return false }` after the loop: an unreadable status
     * (all three probes themselves failing to fetch) also returns `false` rather than guessing.
     */
    private suspend fun probeSubmissionRecovery(analysisId: String): Boolean {
        val probeDelaysMillis = longArrayOf(2_000, 3_000, 5_000)
        for (delayMillis in probeDelaysMillis) {
            delay(delayMillis)
            val result = analysisRepository.fetchAnalysisStatus(analysisId)
            if (result is RdResult.Success && result.value != "pending") return true
        }
        return false
    }

    /**
     * Real port of `markAnalysisSubmissionFailedIfStillPending` + `cleanupUploadedPhotos`'s real
     * call pattern (see [AnalysisRepository.markFailedIfPending]'s doc comment for why this is a
     * single atomic conditional UPDATE here instead of iOS's fetch-then-update): mark the
     * `analyses` row failed only if the server hasn't already started processing it, and only
     * then delete whatever photos were uploaded so far — never touch photos a real in-progress
     * analysis might still be using. Both steps are best-effort (never surfaced as a second
     * error to the UI) — the caller has already classified and is about to show the real failure
     * that triggered this cleanup; a cleanup failure on top of that would just be noise.
     */
    private suspend fun failAnalysisAndCleanup(userId: String, analysisId: String, uploadedPaths: List<String>, message: String) {
        val markedFailed = when (val result = analysisRepository.markFailedIfPending(analysisId, message)) {
            is RdResult.Success -> result.value
            is RdResult.Failure -> false
        }
        if (markedFailed) {
            photoRepository.deleteUploadedPhotos(userId, analysisId, uploadedPaths)
            inFlightStore.clear(analysisId)
        }
    }

    /** Mirrors the "delete" branch of mutate-analysis-finding (see FindingsRepository). Removes
     * the row from [findings] locally on success; leaves it in place and surfaces
     * [deleteError] on failure (e.g. `finding_version_conflict` if it was already edited
     * elsewhere) — no auto-retry, matches the edge function's "reload and try again" message. */
    fun deleteFinding(analysisId: String, finding: Finding) {
        if (!_capabilities.value.canEditAIFindings) {
            _deleteError.value = AppErrorMessages.make(
                context.getString(RdR.string.rd_bulgu_duzenleme_kapali),
                context = context.getString(RdR.string.rd_bulgu_silinemedi),
            )
            return
        }
        viewModelScope.launch {
            when (
                val result = findingsRepository.deleteFinding(
                    analysisId = analysisId,
                    findingId = finding.id,
                    expectedFindingVersion = finding.findingVersion,
                )
            ) {
                is RdResult.Success ->
                    _findings.value = _findings.value.filterNot { it.id == finding.id }
                is RdResult.Failure ->
                    _deleteError.value = AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_analiz_tamamlanamadi),
                    )
            }
        }
    }

    fun clearDeleteError() {
        _deleteError.value = null
    }

    /** Mirrors the "update" branch of mutate-analysis-finding, text-field subset only (see
     * FindingsRepository/FindingPatch doc comments). Refetches the findings list on success
     * rather than patching the local row in place — the server also bumps
     * `finding_version`/recomputes the analysis rollup, and trusting a locally-guessed new
     * version would risk a spurious `finding_version_conflict` on the *next* edit. */
    fun updateFinding(analysisId: String, finding: Finding, patch: FindingPatch) {
        if (!_capabilities.value.canEditAIFindings) {
            _updateError.value = AppErrorMessages.make(
                context.getString(RdR.string.rd_bulgu_duzenleme_kapali),
                context = context.getString(RdR.string.rd_bulgu_kaydedilemedi),
            )
            return
        }
        viewModelScope.launch {
            when (
                val result = findingsRepository.updateFinding(
                    analysisId = analysisId,
                    findingId = finding.id,
                    expectedFindingVersion = finding.findingVersion,
                    patch = patch,
                )
            ) {
                is RdResult.Success -> {
                    _updateError.value = null
                    when (val refreshed = findingsRepository.fetchFindings(analysisId)) {
                        is RdResult.Success -> _findings.value = refreshed.value
                        // Update itself succeeded — keep showing the (now slightly stale) local
                        // list rather than fail the screen over a transient re-read error.
                        is RdResult.Failure -> Unit
                    }
                }
                is RdResult.Failure ->
                    _updateError.value = AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_analiz_tamamlanamadi),
                    )
            }
        }
    }

    fun clearUpdateError() {
        _updateError.value = null
    }

    private suspend fun resolveCapabilities(userId: String): PlanCapabilities {
        val tier = (profileRepository.fetchProfile(userId) as? RdResult.Success)?.value?.tier
            ?: SubscriptionTier.Free
        return resolveCapabilities(tier)
    }

    private suspend fun resolveCapabilities(tier: SubscriptionTier): PlanCapabilities {
        return (planCapabilitiesRepository.fetchCapabilities(tier) as? RdResult.Success)?.value
            ?: PlanCapabilities.forTier(tier)
    }
}
