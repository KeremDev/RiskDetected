package com.riskdetectedan.feature.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.support.SupportRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface SupportUiState {
    data object Idle : SupportUiState
    data object Sending : SupportUiState
    data class Sent(val supportId: String?) : SupportUiState
    data class Failed(val error: AppErrorMessage) : SupportUiState
}

@HiltViewModel
class SupportViewModel @Inject constructor(
    private val supportRepository: SupportRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<SupportUiState>(SupportUiState.Idle)
    val state: StateFlow<SupportUiState> = _state.asStateFlow()

    fun send(subject: String, message: String) {
        _state.value = SupportUiState.Sending
        viewModelScope.launch {
            _state.value = when (val result = supportRepository.send(subject, message)) {
                is RdResult.Success -> SupportUiState.Sent(result.value.supportId)
                is RdResult.Failure -> SupportUiState.Failed(
                    AppErrorMessages.make(result.message, context = "Destek talebi gönderilemedi"),
                )
            }
        }
    }
}
