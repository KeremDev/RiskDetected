package com.riskdetectedan.feature.analysis

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.analysis.AnalysisRepository
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.AnalysisStatus
import com.riskdetectedan.core.data.analysis.CreateAnalysisRequest
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.analysis.FindingPatch
import com.riskdetectedan.core.data.analysis.FindingsRepository
import com.riskdetectedan.core.data.analysis.PhotoRepository
import com.riskdetectedan.core.data.auth.AuthRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

sealed interface CreateAnalysisUiState {
    data object Idle : CreateAnalysisUiState
    data object Creating : CreateAnalysisUiState
    data object UploadingPhoto : CreateAnalysisUiState
    data object Submitting : CreateAnalysisUiState
    data class Polling(val analysisId: String) : CreateAnalysisUiState
    data class Completed(val analysisId: String, val findings: List<Finding>) : CreateAnalysisUiState
    data class CreatedWithoutPhoto(val analysisId: String) : CreateAnalysisUiState
    data class Failed(val message: String) : CreateAnalysisUiState
}

@HiltViewModel
class AnalysisViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val analysisRepository: AnalysisRepository,
    private val photoRepository: PhotoRepository,
    private val findingsRepository: FindingsRepository,
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

    private val _deleteError = MutableStateFlow<String?>(null)
    val deleteError: StateFlow<String?> = _deleteError.asStateFlow()

    private val _updateError = MutableStateFlow<String?>(null)
    val updateError: StateFlow<String?> = _updateError.asStateFlow()

    /**
     * Full submit flow, mirroring AnalysisService.swift's sequence: create -> upload photo(s)
     * -> invoke `analyze` -> poll for a terminal status. Without a photo, stops after create
     * (matches the backend requiring at least one photo before `analyze` will do anything
     * useful — no point invoking it with an empty photo_paths array).
     */
    fun createAnalysis(sector: AnalysisSector?, photoPath: String?) {
        val userId = authRepository.currentUserId
        if (userId == null) {
            _state.value = CreateAnalysisUiState.Failed("Önce giriş yapmalısın.")
            return
        }
        val canvas = "general" // only canvas wired so far; matches AnalysisRepository's default
        _state.value = CreateAnalysisUiState.Creating
        viewModelScope.launch {
            val request = CreateAnalysisRequest(
                userId = userId,
                title = sector?.titleTr ?: "Adsız analiz",
                canvas = canvas,
                sector = sector,
            )
            val analysisId = when (val created = analysisRepository.createAnalysis(request)) {
                is RdResult.Failure -> {
                    _state.value = CreateAnalysisUiState.Failed(created.message)
                    return@launch
                }
                is RdResult.Success -> created.value
            }

            val file = photoPath?.let { File(it) }
            if (file == null || !file.exists()) {
                _state.value = CreateAnalysisUiState.CreatedWithoutPhoto(analysisId)
                return@launch
            }

            _state.value = CreateAnalysisUiState.UploadingPhoto
            val jpegBytes = file.readBytes()
            val uploadedPath = when (
                val uploadResult =
                    photoRepository.uploadPhoto(userId, analysisId, sequenceIndex = 1, jpegBytes)
            ) {
                is RdResult.Success -> uploadResult.value
                is RdResult.Failure -> {
                    _state.value = CreateAnalysisUiState.Failed(uploadResult.message)
                    return@launch
                }
            }

            _state.value = CreateAnalysisUiState.Submitting
            when (
                val submitResult = analysisRepository.submitAnalyze(
                    analysisId = analysisId,
                    canvas = canvas,
                    sector = sector,
                    photoPaths = listOf(uploadedPath),
                )
            ) {
                is RdResult.Failure -> {
                    _state.value = CreateAnalysisUiState.Failed(submitResult.message)
                    return@launch
                }
                is RdResult.Success -> Unit
            }

            _state.value = CreateAnalysisUiState.Polling(analysisId)
            _state.value = when (val status = analysisRepository.pollAnalysisStatus(analysisId)) {
                is AnalysisStatus.Completed -> {
                    val findings = when (val result = findingsRepository.fetchFindings(analysisId)) {
                        is RdResult.Success -> result.value
                        // A completed analysis with an unreadable findings list is still worth
                        // showing as completed — surface an empty list rather than fail the
                        // whole screen over what's likely a transient read error.
                        is RdResult.Failure -> emptyList()
                    }
                    _findings.value = findings
                    CreateAnalysisUiState.Completed(analysisId, findings)
                }
                is AnalysisStatus.Failed ->
                    CreateAnalysisUiState.Failed(status.message ?: "Analiz başarısız oldu.")
                is AnalysisStatus.TimedOut ->
                    CreateAnalysisUiState.Failed("Analiz zaman aşımına uğradı.")
                is AnalysisStatus.InProgress ->
                    CreateAnalysisUiState.Failed("Analiz beklenmedik şekilde durdu: ${status.status}")
            }
        }
    }

    /** Mirrors the "delete" branch of mutate-analysis-finding (see FindingsRepository). Removes
     * the row from [findings] locally on success; leaves it in place and surfaces
     * [deleteError] on failure (e.g. `finding_version_conflict` if it was already edited
     * elsewhere) — no auto-retry, matches the edge function's "reload and try again" message. */
    fun deleteFinding(analysisId: String, finding: Finding) {
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
                is RdResult.Failure -> _deleteError.value = result.message
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
                is RdResult.Failure -> _updateError.value = result.message
            }
        }
    }

    fun clearUpdateError() {
        _updateError.value = null
    }
}
