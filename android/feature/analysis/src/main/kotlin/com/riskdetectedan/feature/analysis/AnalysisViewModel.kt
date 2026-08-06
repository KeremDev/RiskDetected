package com.riskdetectedan.feature.analysis

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.analysis.AnalysisRepository
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.CreateAnalysisRequest
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
    data class Created(val analysisId: String, val photoUploaded: Boolean) : CreateAnalysisUiState
    data class Failed(val message: String) : CreateAnalysisUiState
}

@HiltViewModel
class AnalysisViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val analysisRepository: AnalysisRepository,
    private val photoRepository: PhotoRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<CreateAnalysisUiState>(CreateAnalysisUiState.Idle)
    val state: StateFlow<CreateAnalysisUiState> = _state.asStateFlow()

    /**
     * Creates the `analyses` row and, if a captured photo is available, uploads it. Does NOT
     * call `analyze` yet — that's still separate, larger, unbuilt work (AI routing, polling).
     */
    fun createAnalysis(sector: AnalysisSector?, photoPath: String?) {
        val userId = authRepository.currentUserId
        if (userId == null) {
            _state.value = CreateAnalysisUiState.Failed("Önce giriş yapmalısın.")
            return
        }
        _state.value = CreateAnalysisUiState.Creating
        viewModelScope.launch {
            val request = CreateAnalysisRequest(
                userId = userId,
                title = sector?.titleTr ?: "Adsız analiz",
                sector = sector,
            )
            when (val created = analysisRepository.createAnalysis(request)) {
                is RdResult.Failure -> {
                    _state.value = CreateAnalysisUiState.Failed(created.message)
                    return@launch
                }
                is RdResult.Success -> {
                    val analysisId = created.value
                    val file = photoPath?.let { File(it) }
                    if (file == null || !file.exists()) {
                        _state.value = CreateAnalysisUiState.Created(analysisId, photoUploaded = false)
                        return@launch
                    }
                    _state.value = CreateAnalysisUiState.UploadingPhoto
                    val jpegBytes = file.readBytes()
                    _state.value = when (
                        val uploadResult =
                            photoRepository.uploadPhoto(userId, analysisId, sequenceIndex = 1, jpegBytes)
                    ) {
                        is RdResult.Success -> CreateAnalysisUiState.Created(analysisId, photoUploaded = true)
                        is RdResult.Failure -> CreateAnalysisUiState.Failed(uploadResult.message)
                    }
                }
            }
        }
    }
}
