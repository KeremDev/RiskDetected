package com.riskdetectedan.feature.analysis

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.analysis.AnalysisRepository
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.AnalysisStatus
import com.riskdetectedan.core.data.analysis.CreateAnalysisRequest
import com.riskdetectedan.core.data.analysis.Finding
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
}
