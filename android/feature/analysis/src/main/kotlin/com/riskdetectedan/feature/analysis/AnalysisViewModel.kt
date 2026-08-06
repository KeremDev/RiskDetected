package com.riskdetectedan.feature.analysis

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.analysis.AnalysisRepository
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.CreateAnalysisRequest
import com.riskdetectedan.core.data.auth.AuthRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface CreateAnalysisUiState {
    data object Idle : CreateAnalysisUiState
    data object Creating : CreateAnalysisUiState
    data class Created(val analysisId: String) : CreateAnalysisUiState
    data class Failed(val message: String) : CreateAnalysisUiState
}

@HiltViewModel
class AnalysisViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val analysisRepository: AnalysisRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<CreateAnalysisUiState>(CreateAnalysisUiState.Idle)
    val state: StateFlow<CreateAnalysisUiState> = _state.asStateFlow()

    fun createAnalysis(sector: AnalysisSector?) {
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
            _state.value = when (val result = analysisRepository.createAnalysis(request)) {
                is RdResult.Success -> CreateAnalysisUiState.Created(result.value)
                is RdResult.Failure -> CreateAnalysisUiState.Failed(result.message)
            }
        }
    }
}
