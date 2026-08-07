package com.riskdetectedan.feature.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.account.AccountRepository
import com.riskdetectedan.core.data.auth.AuthRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface AccountDeletionUiState {
    data object Idle : AccountDeletionUiState
    data object Requesting : AccountDeletionUiState
    data object Completed : AccountDeletionUiState
    data class Failed(val message: String) : AccountDeletionUiState
}

@HiltViewModel
class AccountDeletionViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val accountRepository: AccountRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<AccountDeletionUiState>(AccountDeletionUiState.Idle)
    val state: StateFlow<AccountDeletionUiState> = _state.asStateFlow()

    fun confirmDeletion() {
        _state.value = AccountDeletionUiState.Requesting
        viewModelScope.launch {
            when (
                val result =
                    accountRepository.requestAccountDeletion(authRepository.currentUserEmail)
            ) {
                is RdResult.Success -> {
                    // Mirrors AnalysisService.swift's caller clearing the local session once
                    // shouldClearLocalSession is true — sign-out is the ViewModel's explicit
                    // responsibility, not a hidden repository side effect (see
                    // AccountRepository's doc comment).
                    authRepository.signOut()
                    _state.value = AccountDeletionUiState.Completed
                }
                is RdResult.Failure -> _state.value = AccountDeletionUiState.Failed(result.message)
            }
        }
    }
}
