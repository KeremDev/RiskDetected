package com.riskdetectedan.feature.reports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.analysis.HistoryItem
import com.riskdetectedan.core.data.analysis.HistoryRepository
import com.riskdetectedan.core.data.auth.AuthRepository
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

@HiltViewModel
class HistoryViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val historyRepository: HistoryRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<HistoryUiState>(HistoryUiState.Loading)
    val state: StateFlow<HistoryUiState> = _state.asStateFlow()

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
}
