package com.riskdetectedan.feature.onboarding

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.auth.RdAppLanguage
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.release.AndroidRuntimeGateName
import com.riskdetectedan.core.data.release.ReleasePolicyRepository
import com.riskdetectedan.core.designsystem.R as RdR
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface AuthUiState {
    data object Idle : AuthUiState
    data object Loading : AuthUiState
    data object OtpSent : AuthUiState
    data object SignedIn : AuthUiState
    data class Failed(val error: AppErrorMessage) : AuthUiState
}

@HiltViewModel
class AuthViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val googleAuthClient: GoogleAuthClient,
    private val releasePolicyRepository: ReleasePolicyRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<AuthUiState>(AuthUiState.Idle)
    val state: StateFlow<AuthUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            authRepository.currentUserIdFlow.collectLatest { userId ->
                if (userId != null) _state.value = AuthUiState.SignedIn
            }
        }
    }

    fun sendEmailOtp(email: String, language: RdAppLanguage) {
        _state.value = AuthUiState.Loading
        viewModelScope.launch {
            if (!ensureAuthEnabled()) return@launch
            _state.value = when (val result = authRepository.sendEmailOtp(email, language)) {
                is RdResult.Success -> AuthUiState.OtpSent
                is RdResult.Failure -> AuthUiState.Failed(
                    AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_kod_gonderilemedi),
                    ),
                )
            }
        }
    }

    fun verifyEmailOtp(email: String, token: String) {
        _state.value = AuthUiState.Loading
        viewModelScope.launch {
            if (!ensureAuthEnabled()) return@launch
            _state.value = when (val result = authRepository.verifyEmailOtp(email, token)) {
                is RdResult.Success -> AuthUiState.SignedIn
                is RdResult.Failure -> AuthUiState.Failed(
                    AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_kod_dogrulanamadi),
                    ),
                )
            }
        }
    }

    fun signInWithGoogle(context: Context) {
        _state.value = AuthUiState.Loading
        viewModelScope.launch {
            if (!ensureAuthEnabled()) return@launch
            when (val tokenResult = googleAuthClient.requestIdToken(context)) {
                is RdResult.Failure -> {
                    _state.value = AuthUiState.Failed(
                        AppErrorMessages.make(
                            tokenResult.message,
                            context = context.getString(RdR.string.rd_google_giris_yapilamadi),
                        ),
                    )
                    return@launch
                }
                is RdResult.Success -> {
                    val (idToken, rawNonce, email, displayName) = tokenResult.value
                    _state.value = when (
                        val signInResult =
                            authRepository.signInWithGoogleIdToken(idToken, rawNonce, email, displayName)
                    ) {
                        is RdResult.Success -> AuthUiState.SignedIn
                        is RdResult.Failure -> AuthUiState.Failed(
                            AppErrorMessages.make(
                                signInResult.message,
                                context = context.getString(RdR.string.rd_google_giris_yapilamadi),
                            ),
                        )
                    }
                }
            }
        }
    }

    fun signInWithApple() {
        _state.value = AuthUiState.Loading
        viewModelScope.launch {
            if (!ensureAuthEnabled()) return@launch
            _state.value = when (val result = authRepository.signInWithAppleOAuth()) {
                // OAuth completion arrives asynchronously through the app deep link. Returning
                // to Idle prevents a cancelled Custom Tab from leaving the UI permanently busy.
                is RdResult.Success -> AuthUiState.Idle
                is RdResult.Failure -> AuthUiState.Failed(
                    AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_apple_giris_yapilamadi),
                    ),
                )
            }
        }
    }

    private suspend fun ensureAuthEnabled(): Boolean {
        val decision = releasePolicyRepository.resolveGate(AndroidRuntimeGateName.Auth)
        if (decision.enabled) return true
        _state.value = AuthUiState.Failed(
            AppErrorMessages.make(
                context.getString(RdR.string.rd_android_giris_kapali_format, decision.reason),
                context = context.getString(RdR.string.rd_giris_yapilamadi),
            ),
        )
        return false
    }
}
