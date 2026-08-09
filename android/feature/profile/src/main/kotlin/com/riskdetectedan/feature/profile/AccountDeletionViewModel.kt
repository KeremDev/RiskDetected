package com.riskdetectedan.feature.profile

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.account.AccountRepository
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.auth.RdAppLanguage
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.designsystem.R as RdR
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface AccountDeletionUiState {
    data object Idle : AccountDeletionUiState
    data class VerificationSent(val email: String) : AccountDeletionUiState
    data object Requesting : AccountDeletionUiState
    data object Completed : AccountDeletionUiState
    data class Failed(val error: AppErrorMessage) : AccountDeletionUiState
}

@HiltViewModel
class AccountDeletionViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val accountRepository: AccountRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<AccountDeletionUiState>(AccountDeletionUiState.Idle)
    val state: StateFlow<AccountDeletionUiState> = _state.asStateFlow()

    fun sendVerification() {
        val email = authRepository.currentUserEmail
        if (email.isNullOrBlank()) {
            _state.value = AccountDeletionUiState.Failed(
                AppErrorMessages.make(
                    context.getString(RdR.string.rd_dogrulanabilir_eposta_yok),
                    context = context.getString(RdR.string.rd_kimlik_dogrulanamadi),
                ),
            )
            return
        }
        _state.value = AccountDeletionUiState.Requesting
        viewModelScope.launch {
            _state.value = when (val result = authRepository.sendEmailOtp(email, RdAppLanguage.Turkish)) {
                is RdResult.Success -> AccountDeletionUiState.VerificationSent(email)
                is RdResult.Failure -> AccountDeletionUiState.Failed(
                    AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_dogrulama_kodu_gonderilemedi),
                    ),
                )
            }
        }
    }

    fun confirmDeletion(email: String, token: String) {
        _state.value = AccountDeletionUiState.Requesting
        viewModelScope.launch {
            when (val verification = authRepository.verifyEmailOtp(email, token.trim())) {
                is RdResult.Failure -> {
                    _state.value = AccountDeletionUiState.Failed(
                        AppErrorMessages.make(
                            verification.message,
                            context = context.getString(RdR.string.rd_kimlik_dogrulanamadi),
                        ),
                    )
                    return@launch
                }
                is RdResult.Success -> Unit
            }
            when (val result = accountRepository.requestAccountDeletion(email)) {
                is RdResult.Success -> {
                    authRepository.signOut()
                    _state.value = AccountDeletionUiState.Completed
                }
                is RdResult.Failure -> _state.value = AccountDeletionUiState.Failed(
                    AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_hesap_silme_talebi_kaydedilemedi),
                    ),
                )
            }
        }
    }

    fun reset() {
        _state.value = AccountDeletionUiState.Idle
    }
}
