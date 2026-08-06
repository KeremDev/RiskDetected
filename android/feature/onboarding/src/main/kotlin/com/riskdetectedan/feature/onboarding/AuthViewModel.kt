package com.riskdetectedan.feature.onboarding

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.auth.RdAppLanguage
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface AuthUiState {
    data object Idle : AuthUiState
    data object Loading : AuthUiState
    data object OtpSent : AuthUiState
    data object SignedIn : AuthUiState
    data class Failed(val message: String) : AuthUiState
}

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val googleAuthClient: GoogleAuthClient,
) : ViewModel() {

    private val _state = MutableStateFlow<AuthUiState>(AuthUiState.Idle)
    val state: StateFlow<AuthUiState> = _state.asStateFlow()

    fun sendEmailOtp(email: String, language: RdAppLanguage) {
        _state.value = AuthUiState.Loading
        viewModelScope.launch {
            _state.value = when (val result = authRepository.sendEmailOtp(email, language)) {
                is RdResult.Success -> AuthUiState.OtpSent
                is RdResult.Failure -> AuthUiState.Failed(result.message)
            }
        }
    }

    fun verifyEmailOtp(email: String, token: String) {
        _state.value = AuthUiState.Loading
        viewModelScope.launch {
            _state.value = when (val result = authRepository.verifyEmailOtp(email, token)) {
                is RdResult.Success -> AuthUiState.SignedIn
                is RdResult.Failure -> AuthUiState.Failed(result.message)
            }
        }
    }

    fun signInWithGoogle(context: Context) {
        _state.value = AuthUiState.Loading
        viewModelScope.launch {
            when (val tokenResult = googleAuthClient.requestIdToken(context)) {
                is RdResult.Failure -> {
                    _state.value = AuthUiState.Failed(tokenResult.message)
                    return@launch
                }
                is RdResult.Success -> {
                    val (idToken, rawNonce) = tokenResult.value
                    _state.value = when (
                        val signInResult =
                            authRepository.signInWithGoogleIdToken(idToken, rawNonce)
                    ) {
                        is RdResult.Success -> AuthUiState.SignedIn
                        is RdResult.Failure -> AuthUiState.Failed(signInResult.message)
                    }
                }
            }
        }
    }
}
